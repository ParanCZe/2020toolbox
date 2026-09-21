from pathlib import Path

from huggingface_hub import snapshot_download

ROOT = Path(__file__).resolve().parent
VOSR_DIR = ROOT / "runtime" / "VOSR"
CKPT_DIR = VOSR_DIR / "preset" / "ckpts"

if not VOSR_DIR.is_dir():
    raise SystemExit("Chybí runtime/VOSR. Nejdřív spusť setup.bat.")

CKPT_DIR.mkdir(parents=True, exist_ok=True)

print("Stahuju oficiální VOSR 2.0 modely z Hugging Face (CSWRY/VOSR)…")
snapshot_download(
    repo_id="CSWRY/VOSR",
    repo_type="model",
    local_dir=str(CKPT_DIR),
    allow_patterns=[
        "VOSR2/**",
        "Qwen-Image-vae-2d/**",
        "torch_cache/**",
    ],
    # DINOv2 is bundled as a torch.hub repository. Its GitHub Actions files
    # are irrelevant for inference and can exceed Windows path limits inside
    # Hugging Face's temporary ".cache/huggingface/download" tree.
    ignore_patterns=[
        "torch_cache/**/.github/**",
        "torch_cache/**/.git/**",
    ],
    max_workers=4,
)

print("Modely jsou připravené v:", CKPT_DIR)
