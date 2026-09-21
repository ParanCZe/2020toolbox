from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
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
    exe = shutil.which("nvidia-smi")
    if not exe:
        return {"detected": False, "error": "nvidia-smi nebylo nalezeno"}
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
        if p.returncode != 0 or not line:
            return {"detected": False, "error": (p.stderr or "nvidia-smi selhalo").strip()}
        parts = [x.strip() for x in line.split(",")]
        if len(parts) < 6:
            return {"detected": True, "name": line}
        name, util, mem_used, mem_total, temp, power = parts[:6]
        return {
            "detected": True,
            "name": name,
            "utilization_gpu": float(util or 0),
            "memory_used_mb": float(mem_used or 0),
            "memory_total_mb": float(mem_total or 0),
            "temperature_c": float(temp or 0),
            "power_w": float(power or 0),
        }
    except Exception as exc:
        return {"detected": False, "error": str(exc)}


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
        "version": "1.3.0",
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
    server_version = "ToolboxVOSR/1.3.0"

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

        quality = str(query.get("quality", ["fast"])[0]).lower()
        quality_presets = {
            "fast": {"tile": 512, "overlap": 32},
            "quality": {"tile": 768, "overlap": 48},
            "max": {"tile": 1024, "overlap": 64},
        }
        if quality not in quality_presets:
            self._json(400, {"error": "Neznámý VOSR quality preset."})
            return
        preset = quality_presets[quality]

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
                if target_max > preset["tile"]:
                    cmd += ["--tile_size", str(preset["tile"]), "--tile_overlap", str(preset["overlap"])]
                if target_max > 4096:
                    vae_overlap = 32 if quality == "fast" else 48 if quality == "quality" else 64
                    cmd += ["--vae_tile_size", "1024", "--vae_tile_overlap", str(vae_overlap)]

                env = os.environ.copy()
                env["PYTHONUTF8"] = "1"
                env.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
                print(f"[VOSR Bridge] Preset: {quality.upper()} · tile {preset['tile']} · overlap {preset['overlap']} · scale {scale}x")
                print("[VOSR Bridge] Spouštím:", " ".join(f'"{x}"' if " " in x else x for x in cmd))

                CANCEL_REQUESTED.clear()
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
                    )
                    with PROCESS_LOCK:
                        CURRENT_PROCESS = p
                    try:
                        stdout, stderr = p.communicate(timeout=MAX_JOB_SECONDS)
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
                        stdout, stderr = p.communicate()
                        self._json(504, {"error": "VOSR inference překročila časový limit."})
                        return
                finally:
                    with PROCESS_LOCK:
                        CURRENT_PROCESS = None

                if CANCEL_REQUESTED.is_set():
                    CANCEL_REQUESTED.clear()
                    self._json(499, {"error": "VOSR byl zastaven uživatelem.", "cancelled": True})
                    return

                result = out / "input.png"
                if p.returncode != 0 or not result.is_file():
                    tail = "\n".join(((stderr or "") + "\n" + (stdout or "")).splitlines()[-40:])
                    print("[VOSR Bridge] Inference selhala. Poslední výstup:")
                    print(tail or "(bez výstupu)")
                    self._json(500, {"error": "VOSR inference selhala.", "detail": tail})
                    return

                payload = result.read_bytes()
                self.send_response(200)
                self._cors()
                self.send_header("Content-Type", "image/png")
                self.send_header("Content-Length", str(len(payload)))
                self.send_header("X-Toolbox-Engine", "VOSR-2.0")
                self.send_header("X-Toolbox-Quality", quality)
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
