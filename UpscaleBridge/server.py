from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

HOST = "127.0.0.1"
PORT = int(os.environ.get("TOOLBOX_VOSR_PORT", "8092"))
MAX_UPLOAD = int(os.environ.get("TOOLBOX_VOSR_MAX_UPLOAD", str(64 * 1024 * 1024)))
MAX_JOB_SECONDS = int(os.environ.get("TOOLBOX_VOSR_TIMEOUT", "3600"))

ROOT = Path(__file__).resolve().parent
VOSR_DIR = ROOT / "runtime" / "VOSR"
CKPT_DIR = VOSR_DIR / "preset" / "ckpts"
VOSR2_DIR = CKPT_DIR / "VOSR2"
QWEN_DIR = CKPT_DIR / "Qwen-Image-vae-2d"
TORCH_CACHE = CKPT_DIR / "torch_cache"
INFERENCE = VOSR_DIR / "inference_vosr_onestep.py"

JOB_LOCK = threading.Lock()
PROCESS_LOCK = threading.Lock()
CURRENT_PROCESS: subprocess.Popen | None = None
CANCEL_REQUESTED = threading.Event()
PROGRESS_LOCK = threading.Lock()
JOB_PROGRESS = {
    "active": False,
    "phase": "idle",
    "phase_label": "Připraveno",
    "done": 0,
    "total": 1,
    "percent": 0.0,
    "started_at": 0.0,
    "updated_at": 0.0,
}

PHASE_RANGES = {
    "model_load": (5.0, 18.0, "Načítám VOSR modely"),
    "vae_encode": (18.0, 30.0, "VAE encode"),
    "dino": (30.0, 42.0, "DINOv2 analýza"),
    "dit": (42.0, 88.0, "VOSR DiT"),
    "vae_decode": (88.0, 97.0, "VAE decode"),
    "save": (97.0, 99.5, "Ukládám výsledek"),
}

def set_job_progress(phase: str, done: int = 0, total: int = 1, *, active: bool | None = None, message: str | None = None) -> None:
    total = max(1, int(total or 1))
    done = max(0, min(total, int(done or 0)))
    lo, hi, label = PHASE_RANGES.get(phase, (0.0, 99.0, phase))
    frac = done / total
    pct = lo + (hi - lo) * frac
    now = time.time()
    with PROGRESS_LOCK:
        if active is not None:
            JOB_PROGRESS["active"] = bool(active)
        JOB_PROGRESS["phase"] = phase
        JOB_PROGRESS["phase_label"] = message or label
        JOB_PROGRESS["done"] = done
        JOB_PROGRESS["total"] = total
        JOB_PROGRESS["percent"] = round(pct, 2)
        JOB_PROGRESS["updated_at"] = now

def reset_job_progress() -> None:
    now = time.time()
    with PROGRESS_LOCK:
        JOB_PROGRESS.update({
            "active": True,
            "phase": "starting",
            "phase_label": "Spouštím VOSR",
            "done": 0,
            "total": 1,
            "percent": 2.0,
            "started_at": now,
            "updated_at": now,
        })

def progress_payload() -> dict:
    with PROGRESS_LOCK:
        p = dict(JOB_PROGRESS)
    started = float(p.get("started_at") or 0)
    p["elapsed_seconds"] = max(0.0, time.time() - started) if started else 0.0
    return p

def parse_progress_line(line: str) -> None:
    marker = "TOOLBOX_PROGRESS|"
    if marker not in line:
        return
    try:
        payload = line.split(marker, 1)[1].strip()
        phase, done, total = payload.split("|", 2)
        set_job_progress(phase.strip(), int(done), int(total), active=True)
    except Exception:
        pass


def _glob_any(path: Path, patterns: tuple[str, ...]) -> bool:
    return path.is_dir() and any(any(path.glob(p)) for p in patterns)


def models_ready() -> bool:
    return (
        INFERENCE.is_file()
        and (VOSR2_DIR / "args.json").is_file()
        and _glob_any(VOSR2_DIR, ("*.safetensors", "**/*.safetensors"))
        and (QWEN_DIR / "config.json").is_file()
        and _glob_any(QWEN_DIR, ("*.safetensors", "**/*.safetensors"))
        and TORCH_CACHE.is_dir()
        and any(TORCH_CACHE.iterdir())
    )


def gpu_telemetry() -> dict:
    def safe_float(value, default=0.0):
        try:
            s = str(value).strip().strip('"').strip("'")
            if not s or s.upper() in {"N/A", "[N/A]", "NA", "NONE", "-"}:
                return default
            return float(s.replace(",", "."))
        except Exception:
            return default

    exe = shutil.which("nvidia-smi") or shutil.which("nvidia-smi.exe")
    if not exe and os.name == "nt":
        candidates = [
            Path(os.environ.get("WINDIR", r"C:\\Windows")) / "System32" / "nvidia-smi.exe",
            Path(r"C:\\Program Files\\NVIDIA Corporation\\NVSMI\\nvidia-smi.exe"),
        ]
        exe = next((str(p) for p in candidates if p.is_file()), None)

    if exe:
        try:
            p = subprocess.run(
                [
                    exe,
                    "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw",
                    "--format=csv,noheader,nounits",
                ],
                capture_output=True,
                text=True,
                timeout=8,
                check=False,
            )
            line = (p.stdout or "").strip().splitlines()[0] if p.stdout else ""
            if p.returncode == 0 and line:
                parts = [x.strip() for x in line.split(",")]
                if len(parts) >= 6:
                    name, util, mem_used, mem_total, temp, power = parts[:6]
                    return {
                        "detected": True,
                        "name": name or "NVIDIA GPU",
                        "utilization_gpu": safe_float(util),
                        "memory_used_mb": safe_float(mem_used),
                        "memory_total_mb": safe_float(mem_total),
                        "temperature_c": safe_float(temp),
                        "power_w": safe_float(power),
                    }
                return {"detected": True, "name": line}
        except Exception:
            pass

    # Fallback: PyTorch CUDA is authoritative enough for VOSR execution even if
    # nvidia-smi telemetry is unavailable or a driver field returns N/A.
    try:
        import torch
        if torch.cuda.is_available():
            props = torch.cuda.get_device_properties(0)
            return {
                "detected": True,
                "name": torch.cuda.get_device_name(0),
                "utilization_gpu": 0.0,
                "memory_used_mb": float(torch.cuda.memory_allocated(0) / 1024 / 1024),
                "memory_total_mb": float(props.total_memory / 1024 / 1024),
                "temperature_c": 0.0,
                "power_w": 0.0,
            }
    except Exception as exc:
        return {"detected": False, "error": f"GPU telemetry selhala: {exc}"}

    return {"detected": False, "error": "NVIDIA GPU nebyla nalezena"}


def gpu_info() -> tuple[bool, str]:
    g = gpu_telemetry()
    if not g.get("detected"):
        return False, str(g.get("error") or "GPU nenalezena")
    name = g.get("name") or "NVIDIA GPU"
    total = g.get("memory_total_mb")
    suffix = f", {int(total)} MiB" if isinstance(total, (int, float)) and total else ""
    return True, f"{name}{suffix}"


def _dir_size(path: Path) -> int:
    if not path.exists():
        return 0
    total = 0
    try:
        for p in path.rglob("*"):
            try:
                if p.is_file():
                    total += p.stat().st_size
            except OSError:
                pass
    except OSError:
        pass
    return total


def storage_payload() -> dict:
    venv = ROOT / ".venv"
    runtime = ROOT / "runtime"
    venv_bytes = _dir_size(venv)
    runtime_bytes = _dir_size(runtime)
    models_bytes = _dir_size(CKPT_DIR)
    total = venv_bytes + runtime_bytes
    try:
        usage = shutil.disk_usage(ROOT)
        free = usage.free
        disk_total = usage.total
    except OSError:
        free = 0
        disk_total = 0
    return {
        "venv_bytes": venv_bytes,
        "runtime_bytes": runtime_bytes,
        "models_bytes": models_bytes,
        "total_bytes": total,
        "disk_free_bytes": free,
        "disk_total_bytes": disk_total,
    }


def health_payload() -> dict:
    gpu, info = gpu_info()
    mready = models_ready()
    tel = gpu_telemetry()
    return {
        "name": "20-20 Toolbox VOSR Bridge",
        "version": "1.4.0",
        "advanced_settings": True,
        "vosr_defaults": {
            "tile": 512,
            "tile_overlap": 32,
            "vae_tile": 1024,
            "vae_overlap": 32,
        },
        "ready": bool(mready and gpu),
        "models_ready": mready,
        "gpu_detected": gpu,
        "gpu": info,
        "gpu_telemetry": tel,
        "busy": JOB_LOCK.locked(),
        "cancel_requested": CANCEL_REQUESTED.is_set(),
        "port": PORT,
        "vosr_dir": str(VOSR_DIR),
        "checkpoint": str(VOSR2_DIR),
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "ToolboxVOSR/1.4.0"

    def log_message(self, fmt: str, *args) -> None:
        print(f"[VOSR Bridge] {self.address_string()} - {fmt % args}")

    def _cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Private-Network", "true")
        self.send_header("Cache-Control", "no-store")

    def _json(self, status: int, payload: dict) -> None:
        raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self._cors()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self._cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/health":
            self._json(200, health_payload())
            return
        if path == "/telemetry":
            payload = gpu_telemetry()
            payload["busy"] = JOB_LOCK.locked()
            payload["cancel_requested"] = CANCEL_REQUESTED.is_set()
            self._json(200, payload)
            return
        if path == "/progress":
            payload = progress_payload()
            payload["busy"] = JOB_LOCK.locked()
            payload["cancel_requested"] = CANCEL_REQUESTED.is_set()
            self._json(200, payload)
            return
        if path == "/storage":
            self._json(200, storage_payload())
            return
        self._json(404, {"error": "Not found"})

    def do_POST(self) -> None:
        global CURRENT_PROCESS
        parsed = urlparse(self.path)

        if parsed.path == "/cancel":
            with PROCESS_LOCK:
                proc = CURRENT_PROCESS
            if proc is None or proc.poll() is not None:
                CANCEL_REQUESTED.clear()
                self._json(200, {"ok": True, "message": "Žádný VOSR proces právě neběží."})
                return
            CANCEL_REQUESTED.set()
            try:
                if os.name == "nt":
                    subprocess.run(
                        ["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                        capture_output=True,
                        text=True,
                        timeout=12,
                        check=False,
                    )
                else:
                    proc.terminate()
                self._json(202, {"ok": True, "message": "STOP odeslán VOSR procesu."})
            except Exception as exc:
                self._json(500, {"error": f"VOSR se nepodařilo zastavit: {exc}"})
            return

        if parsed.path == "/cleanup":
            if JOB_LOCK.locked():
                self._json(409, {"error": "VOSR právě zpracovává obrázek. Cleanup spusť až po dokončení."})
                return
            script = ROOT / "cleanup_ai.bat"
            if not script.is_file():
                self._json(500, {"error": "Cleanup skript nebyl nalezen. Aktualizuj VOSR Bridge instalátor."})
                return
            try:
                flags = 0
                if os.name == "nt":
                    flags = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0) | getattr(subprocess, "DETACHED_PROCESS", 0)
                subprocess.Popen(
                    ["cmd.exe", "/c", "start", "", "/min", str(script), "--wait-pid", str(os.getpid())],
                    cwd=str(ROOT),
                    creationflags=flags,
                    close_fds=True,
                )
                self._json(202, {"ok": True, "message": "Cleanup spuštěn. Bridge se ukončí a AI data se smažou."})
                threading.Thread(target=self.server.shutdown, daemon=True).start()
            except Exception as exc:
                self._json(500, {"error": f"Cleanup se nepodařilo spustit: {exc}"})
            return

        if parsed.path != "/upscale":
            self._json(404, {"error": "Not found"})
            return

        h = health_payload()
        if not h["models_ready"]:
            self._json(503, {"error": "VOSR 2.0 modely nejsou nainstalované. Spusť setup.bat."})
            return
        if not h["gpu_detected"]:
            self._json(503, {"error": "Nebyla nalezena NVIDIA GPU / nvidia-smi."})
            return

        query = parse_qs(parsed.query)
        try:
            scale = int(query.get("scale", ["4"])[0])
        except ValueError:
            scale = 4
        if scale not in (2, 4):
            self._json(400, {"error": "Podporovaný scale je 2 nebo 4."})
            return

        preset = str(query.get("preset", ["balanced"])[0] or "balanced").lower()
        dino_mode = "shared" if preset == "fast4060" else "exact"

        def query_choice(name: str, default: int, allowed: tuple[int, ...]) -> int:
            try:
                value = int(query.get(name, [str(default)])[0])
            except (TypeError, ValueError):
                return default
            return value if value in allowed else default

        # Advanced settings are opt-in. These defaults reproduce the clean/original
        # VOSR path exactly: DiT 512 / overlap 32 + VAE 1024 / overlap 32.
        tile_size = query_choice("tile", 512, (128, 256, 384, 512, 768, 1024))
        tile_overlap = query_choice("tile_overlap", 32, (0, 16, 32, 64, 96, 128))
        vae_tile_size = query_choice("vae_tile", 1024, (512, 768, 1024, 1536, 2048))
        vae_tile_overlap = query_choice("vae_overlap", 32, (0, 16, 32, 64, 96, 128))
        if tile_overlap >= tile_size:
            tile_overlap = 32
        if vae_tile_overlap >= vae_tile_size:
            vae_tile_overlap = 32

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_UPLOAD:
            self._json(413, {"error": f"Neplatná nebo příliš velká data (limit {MAX_UPLOAD // 1024 // 1024} MB)."})
            return
        raw = self.rfile.read(length)
        if len(raw) != length:
            self._json(400, {"error": "Obrázek nebyl přijat celý."})
            return

        if not JOB_LOCK.acquire(blocking=False):
            self._json(429, {"error": "VOSR právě zpracovává jiný obrázek."})
            return

        try:
            from PIL import Image

            with tempfile.TemporaryDirectory(prefix="toolbox-vosr-") as td:
                work = Path(td)
                inp = work / "input.png"
                out = work / "out"
                inp.write_bytes(raw)
                out.mkdir(parents=True, exist_ok=True)

                try:
                    with Image.open(inp) as im:
                        im.verify()
                    with Image.open(inp) as im:
                        width, height = im.size
                except Exception:
                    self._json(400, {"error": "Vstup není platný obrázek."})
                    return

                target_max = max(width * scale, height * scale)
                cmd = [
                    sys.executable,
                    str(INFERENCE),
                    "-c", str(VOSR2_DIR),
                    "-i", str(inp),
                    "-o", str(out),
                    "-u", str(scale),
                    "--force_rerun",
                ]
                # Defaults keep the clean/original VOSR path. Custom values are
                # only used when the advanced controls explicitly send them.
                if target_max > tile_size:
                    cmd += ["--tile_size", str(tile_size), "--tile_overlap", str(tile_overlap)]
                if target_max > 4096:
                    cmd += ["--vae_tile_size", str(vae_tile_size), "--vae_tile_overlap", str(vae_tile_overlap)]

                env = os.environ.copy()
                env["PYTHONUTF8"] = "1"
                env["TOOLBOX_DINO_MODE"] = dino_mode
                env.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
                print(
                    f"[VOSR Bridge] Scene {scale}x · preset {preset} · DINO {dino_mode} · "
                    f"tile {tile_size} / overlap {tile_overlap} · VAE tile {vae_tile_size} / overlap {vae_tile_overlap}"
                )
                print("[VOSR Bridge] Spouštím:", " ".join(f'"{x}"' if " " in x else x for x in cmd))

                CANCEL_REQUESTED.clear()
                reset_job_progress()
                stdout = ""
                stderr = ""
                try:
                    p = subprocess.Popen(
                        cmd,
                        cwd=str(VOSR_DIR),
                        env=env,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        bufsize=1,
                        encoding="utf-8",
                        errors="replace",
                    )
                    with PROCESS_LOCK:
                        CURRENT_PROCESS = p

                    out_lines: list[str] = []
                    err_lines: list[str] = []

                    def consume(stream, sink: list[str], prefix: str) -> None:
                        if stream is None:
                            return
                        for line in iter(stream.readline, ""):
                            line = line.rstrip("\r\n")
                            sink.append(line)
                            if len(sink) > 400:
                                del sink[:-250]
                            parse_progress_line(line)
                            if line:
                                print(f"[VOSR {prefix}] {line}")
                        try:
                            stream.close()
                        except Exception:
                            pass

                    t_out = threading.Thread(target=consume, args=(p.stdout, out_lines, "OUT"), daemon=True)
                    t_err = threading.Thread(target=consume, args=(p.stderr, err_lines, "ERR"), daemon=True)
                    t_out.start()
                    t_err.start()

                    try:
                        p.wait(timeout=MAX_JOB_SECONDS)
                    except subprocess.TimeoutExpired:
                        if os.name == "nt":
                            subprocess.run(
                                ["taskkill", "/PID", str(p.pid), "/T", "/F"],
                                capture_output=True,
                                text=True,
                                timeout=12,
                                check=False,
                            )
                        else:
                            p.kill()
                        p.wait(timeout=15)
                        with PROGRESS_LOCK:
                            JOB_PROGRESS["active"] = False
                            JOB_PROGRESS["phase_label"] = "Timeout"
                        self._json(504, {"error": "VOSR inference překročila časový limit."})
                        return
                    finally:
                        t_out.join(timeout=2)
                        t_err.join(timeout=2)

                    stdout = "\n".join(out_lines)
                    stderr = "\n".join(err_lines)
                finally:
                    with PROCESS_LOCK:
                        CURRENT_PROCESS = None

                if CANCEL_REQUESTED.is_set():
                    CANCEL_REQUESTED.clear()
                    with PROGRESS_LOCK:
                        JOB_PROGRESS["active"] = False
                        JOB_PROGRESS["phase"] = "cancelled"
                        JOB_PROGRESS["phase_label"] = "Zastaveno"
                    self._json(499, {"error": "VOSR byl zastaven uživatelem.", "cancelled": True})
                    return

                result = out / "input.png"
                if p.returncode != 0 or not result.is_file():
                    tail = "\n".join(((stderr or "") + "\n" + (stdout or "")).splitlines()[-40:])
                    print("[VOSR Bridge] Inference selhala. Poslední výstup:")
                    print(tail or "(bez výstupu)")
                    with PROGRESS_LOCK:
                        JOB_PROGRESS["active"] = False
                        JOB_PROGRESS["phase"] = "error"
                        JOB_PROGRESS["phase_label"] = "Inference selhala"
                    self._json(500, {"error": "VOSR inference selhala.", "detail": tail})
                    return

                set_job_progress("save", 1, 1, active=False, message="Hotovo")
                with PROGRESS_LOCK:
                    JOB_PROGRESS["percent"] = 100.0
                    JOB_PROGRESS["phase"] = "done"
                    JOB_PROGRESS["phase_label"] = "Hotovo"
                payload = result.read_bytes()
                self.send_response(200)
                self._cors()
                self.send_header("Content-Type", "image/png")
                self.send_header("Content-Length", str(len(payload)))
                self.send_header("X-Toolbox-Engine", "VOSR-2.0")
                self.send_header("X-Toolbox-Scale", str(scale))
                self.send_header("X-Toolbox-Tile", str(tile_size))
                self.send_header("X-Toolbox-Tile-Overlap", str(tile_overlap))
                self.send_header("X-Toolbox-VAE-Tile", str(vae_tile_size))
                self.send_header("X-Toolbox-VAE-Overlap", str(vae_tile_overlap))
                self.send_header("X-Toolbox-Preset", preset)
                self.send_header("X-Toolbox-DINO", dino_mode)
                self.end_headers()
                self.wfile.write(payload)
        except BrokenPipeError:
            pass
        except Exception as exc:
            self._json(500, {"error": f"Bridge selhal: {exc}"})
        finally:
            JOB_LOCK.release()


def main() -> None:
    print("=" * 66)
    print("20-20 TOOLBOX · VOSR 2.0 LOCAL BRIDGE")
    print(f"http://{HOST}:{PORT}")
    h = health_payload()
    print("Modely:", "OK" if h["models_ready"] else "CHYBÍ — spusť setup.bat")
    print("GPU:", h["gpu"] if h["gpu_detected"] else "NENALEZENA")
    print("Bridge přijímá spojení pouze z tohoto počítače (127.0.0.1).")
    print("=" * 66)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
