# 20-20 Toolbox · VOSR 2.0 Local Bridge

Lokální GPU bridge pro režimy **VOSR 2.0 Scene 2× / 4×** v Toolbox Upscaleru.

Toolbox dál používá Real-ESRGAN pro lehké browserové režimy. VOSR 2.0 je 1.4B PyTorch/CUDA model, proto běží mimo prohlížeč a Toolbox s ním komunikuje jen přes `127.0.0.1:8092`. Obrázek se nikam neuploaduje.

## One-click instalace

Uživatel potřebuje pouze:

- Windows 10/11 64-bit
- NVIDIA GPU
- aktuální NVIDIA ovladač (`nvidia-smi` musí fungovat)
- internet pro první instalaci
- přibližně 14–18 GB volného místa po instalaci; během instalace může být dočasně potřeba 20+ GB

**Python, Git ani CUDA Toolkit není potřeba instalovat ručně.**

Tlačítko **Stáhnout VOSR Bridge instalátor** stáhne jediný `install.bat`. Ten automaticky:

1. vytvoří `%LOCALAPPDATA%\20-20-TOOLBOX\UpscaleBridge`,
2. stáhne portable **uv** runtime,
3. přes uv stáhne vlastní izolovaný **CPython 3.10** přímo do složky bridge,
4. stáhne pinned VOSR zdrojáky jako ZIP — není potřeba Git,
5. vytvoří lokální `.venv`,
6. nainstaluje PyTorch CUDA + VOSR dependencies + `triton-windows`,
7. stáhne VOSR2 checkpoint, Qwen VAE a DINO cache,
8. ověří CUDA, vyčistí instalační cache a spustí bridge.

Runtime se nepřidává do systémového PATH a nemění systémovou instalaci Pythonu.

Portable Python je spravovaný přes uv; uv oficiálně podporuje stahování vlastních CPython buildů pro Windows.

## Velikost

Modelová data mají přibližně 7,7 GB:

- VOSR2 ~5,58 GB
- Qwen Image VAE 2D ~178 MB
- DINO / torch cache ~1,92 GB

Zbytek tvoří Python, PyTorch CUDA a další knihovny. Celkem počítej přibližně **14–18 GB**.

## Spuštění

Po instalaci se bridge spustí automaticky. Později ho můžeš spustit souborem `run_bridge.bat`.

V Toolboxu vyber **VOSR 2.0 Scene 2×** nebo **VOSR 2.0 Scene 4×**.

## API

- `GET http://127.0.0.1:8092/health`
- `POST http://127.0.0.1:8092/upscale?scale=2`
- `POST http://127.0.0.1:8092/upscale?scale=4`

POST tělo je PNG; odpověď je PNG.

## Zdroj modelu

- https://github.com/cswry/VOSR
- https://huggingface.co/CSWRY/VOSR

VOSR repo uvádí Apache-2.0 licenci pro svůj kód, není-li uvedeno jinak. Externí modelové assety mohou mít vlastní podmínky.


## Cleanup

Toolbox Upscaler má blok **AI STORAGE / CLEANUP**. Při běžícím bridge tlačítko po potvrzení ukončí VOSR Bridge a odstraní pouze Toolbox-owned AI data: `.venv`, `runtime`, VOSR checkpointy, portable Python/PyTorch knihovny a vyhrazené AI cache složky pod `%LOCALAPPDATA%\\20-20-TOOLBOX`. Ostatní uživatelská Hugging Face/Python data mimo Toolbox se nemažou.

Pokud bridge neběží nebo je starší verze bez `/cleanup`, Toolbox stáhne `cleanup_ai.bat` jako bezpečný fallback k ručnímu spuštění.
