# 20-20 Toolbox · VOSR 2.0 Local Bridge

Lokální GPU bridge pro nové režimy **VOSR 2.0 Scene 2× / 4×** v Toolbox Upscaleru.

Toolbox dál používá Real-ESRGAN pro původní browserové režimy. VOSR 2.0 je skutečný 1.4B PyTorch/CUDA model, proto běží mimo prohlížeč a web s ním komunikuje pouze přes `127.0.0.1:8092`. Obrázek se nikam neuploaduje.

## Požadavky

- Windows 10/11 64-bit
- NVIDIA GPU + aktuální ovladač (`nvidia-smi` musí fungovat)
- Python 3.10–3.12
- Git for Windows
- dostatek místa pro Python runtime a modely

Oficiální VOSR requirements používají PyTorch 2.5.1 + CUDA 12.1 a Triton 3.1. Na Windows setup nahrazuje linuxový balíček `triton` kompatibilním `triton-windows 3.1.x`.

## Instalace

1. Spusť `setup.bat`.
2. Setup stáhne oficiální VOSR zdrojáky, CUDA Python balíčky a pouze checkpointy potřebné pro VOSR 2.0.
3. Po dokončení spusť `run_bridge.bat` a nech okno otevřené.
4. Otevři Toolbox → Upscaler → **VOSR 2.0 Scene 2×** nebo **VOSR 2.0 Scene 4×**.

Modelová data mají přibližně 7,7 GB: VOSR2 (~5,58 GB), Qwen Image VAE 2D (~178 MB) a DINO/torch cache (~1,92 GB).

## API

- `GET http://127.0.0.1:8092/health`
- `POST http://127.0.0.1:8092/upscale?scale=2`
- `POST http://127.0.0.1:8092/upscale?scale=4`

POST tělo je PNG; odpověď je PNG.

## Zdroj modelu

- https://github.com/cswry/VOSR
- https://huggingface.co/CSWRY/VOSR

VOSR repozitář uvádí Apache-2.0 licenci pro svůj kód, není-li uvedeno jinak. Externí modelové assety mohou mít vlastní podmínky; před redistribucí checkpointů je ověř zvlášť.
