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


def gpu_info() -> tuple[bool, str]:
    exe = shutil.which("nvidia-smi")
    if not exe:
        return False, "nvidia-smi nebylo nalezeno"
    try:
        p = subprocess.run(
            [exe, "--query-gpu=name,memory.total", "--format=csv,noheader"],
            capture_output=True,
            text=True,
            timeout=8,
            check=False,
        )
        info = (p.stdout or p.stderr or "").strip()
        return p.returncode == 0, info
    except Exception as exc:
        return False, str(exc)


def health_payload() -> dict:
    gpu, info = gpu_info()
    mready = models_ready()
    return {
        "name": "20-20 Toolbox VOSR Bridge",
        "version": "1.1.0",
        "ready": bool(mready and gpu),
        "models_ready": mready,
        "gpu_detected": gpu,
        "gpu": info,
        "busy": JOB_LOCK.locked(),
        "port": PORT,
        "vosr_dir": str(VOSR_DIR),
        "checkpoint": str(VOSR2_DIR),
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "ToolboxVOSR/1.1"

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
        if urlparse(self.path).path != "/health":
            self._json(404, {"error": "Not found"})
            return
        self._json(200, health_payload())

    def do_POST(self) -> None:
        parsed = urlparse(self.path)

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

        try:
            scale = int(parse_qs(parsed.query).get("scale", ["4"])[0])
        except ValueError:
            scale = 4
        if scale not in (2, 4):
            self._json(400, {"error": "Podporovaný scale je 2 nebo 4."})
            return

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
                if target_max > 512:
                    cmd += ["--tile_size", "512", "--tile_overlap", "32"]
                if target_max > 4096:
                    cmd += ["--vae_tile_size", "1024", "--vae_tile_overlap", "32"]

                env = os.environ.copy()
                env["PYTHONUTF8"] = "1"
                env.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
                print("[VOSR Bridge] Spouštím:", " ".join(f'"{x}"' if " " in x else x for x in cmd))

                try:
                    p = subprocess.run(
                        cmd,
                        cwd=str(VOSR_DIR),
                        env=env,
                        capture_output=True,
                        text=True,
                        timeout=MAX_JOB_SECONDS,
                        check=False,
                    )
                except subprocess.TimeoutExpired:
                    self._json(504, {"error": "VOSR inference překročila časový limit."})
                    return

                result = out / "input.png"
                if p.returncode != 0 or not result.is_file():
                    tail = "\n".join(((p.stderr or "") + "\n" + (p.stdout or "")).splitlines()[-24:])
                    self._json(500, {"error": "VOSR inference selhala.", "detail": tail})
                    return

                payload = result.read_bytes()
                self.send_response(200)
                self._cors()
                self.send_header("Content-Type", "image/png")
                self.send_header("Content-Length", str(len(payload)))
                self.send_header("X-Toolbox-Engine", "VOSR-2.0")
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
