from __future__ import annotations

import shutil
import tempfile
import urllib.request
import zipfile
from pathlib import Path

from huggingface_hub import snapshot_download

ROOT = Path(__file__).resolve().parent
VOSR_DIR = ROOT / "runtime" / "VOSR"
CKPT_DIR = VOSR_DIR / "preset" / "ckpts"
TORCH_CACHE = CKPT_DIR / "torch_cache"

DINO_REPO_DIR = TORCH_CACHE / "facebookresearch_dinov2_main"
DINO_CKPT_DIR = TORCH_CACHE / "checkpoints"
DINO_WEIGHT = DINO_CKPT_DIR / "dinov2_vitl14_pretrain.pth"

DINO_ZIP_URL = "https://github.com/facebookresearch/dinov2/archive/refs/heads/main.zip"
DINO_WEIGHT_URL = "https://dl.fbaipublicfiles.com/dinov2/dinov2_vitl14/dinov2_vitl14_pretrain.pth"

if not VOSR_DIR.is_dir():
    raise SystemExit("Chybí runtime/VOSR. Nejdřív spusť setup.bat.")

CKPT_DIR.mkdir(parents=True, exist_ok=True)
TORCH_CACHE.mkdir(parents=True, exist_ok=True)

print("Stahuju oficiální VOSR 2.0 model a Qwen VAE z Hugging Face (CSWRY/VOSR)…")
snapshot_download(
    repo_id="CSWRY/VOSR",
    repo_type="model",
    local_dir=str(CKPT_DIR),
    allow_patterns=[
        "VOSR2/**",
        "Qwen-Image-vae-2d/**",
    ],
    max_workers=4,
)

# Starší verze downloaderu snapshotovala celý torch_cache z Hugging Face.
# Na Windows to může narazit na MAX_PATH uvnitř:
# .cache/huggingface/download/.../.github/workflows/<dlouhý-hash>.incomplete
# Tyto soubory nejsou pro inference potřeba. DINOv2 proto připravujeme
# přímo z oficiálního Meta repozitáře a checkpointu.
legacy_torch_cache = CKPT_DIR / ".cache" / "huggingface" / "download" / "torch_cache"
shutil.rmtree(legacy_torch_cache, ignore_errors=True)

if not (DINO_REPO_DIR / "hubconf.py").is_file():
    print("Připravuju DINOv2 zdrojové soubory (bez GitHub workflow/test metadata)…")
    DINO_REPO_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="toolbox-dinov2-", dir=str(ROOT / "runtime")) as td:
        zip_path = Path(td) / "dinov2-main.zip"
        urllib.request.urlretrieve(DINO_ZIP_URL, zip_path)
        with zipfile.ZipFile(zip_path, "r") as zf:
            for member in zf.infolist():
                name = member.filename.replace("\\", "/")
                if not name.startswith("dinov2-main/"):
                    continue
                rel = name[len("dinov2-main/"):]
                if not rel or rel.endswith("/"):
                    continue
                if rel == "hubconf.py" or rel.startswith("dinov2/"):
                    dst = DINO_REPO_DIR / Path(rel)
                    dst.parent.mkdir(parents=True, exist_ok=True)
                    with zf.open(member, "r") as src, dst.open("wb") as out:
                        shutil.copyfileobj(src, out)
else:
    print("DINOv2 zdrojové soubory už existují.")

DINO_CKPT_DIR.mkdir(parents=True, exist_ok=True)
if DINO_WEIGHT.is_file() and DINO_WEIGHT.stat().st_size > 1_000_000_000:
    print("DINOv2 ViT-L/14 checkpoint už existuje.")
else:
    print("Stahuju oficiální DINOv2 ViT-L/14 checkpoint (~1.2 GB)…")
    tmp = DINO_WEIGHT.with_suffix(".pth.incomplete")
    if tmp.exists():
        tmp.unlink()
    urllib.request.urlretrieve(DINO_WEIGHT_URL, tmp)
    tmp.replace(DINO_WEIGHT)

required = [
    CKPT_DIR / "VOSR2" / "args.json",
    CKPT_DIR / "VOSR2" / "checkpoints" / "ema_model.safetensors",
    CKPT_DIR / "Qwen-Image-vae-2d" / "config.json",
    DINO_REPO_DIR / "hubconf.py",
    DINO_WEIGHT,
]
missing = [str(p) for p in required if not p.exists()]
if missing:
    raise SystemExit("Chybí povinné modelové soubory:\n" + "\n".join(missing))

print("Modely jsou připravené v:", CKPT_DIR)
