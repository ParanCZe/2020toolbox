from __future__ import annotations

import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent
INFERENCE = ROOT / "runtime" / "VOSR" / "inference_vosr_onestep.py"
BACKUP = INFERENCE.with_suffix(".py.toolbox-original.bak")
MARKER = "# 20-20 TOOLBOX PERF PATCH: shared DINO features v1"

OLD_BLOCK = """    # --- Per-tile DINOv2 features (pre-computed once) ---
    # Each tile's pixel crop is independently resized to dinov2_size and fed
    # through DINOv2, producing features with constant shape that exactly match
    # the tile's spatial content (same as training-time behaviour).
    tile_venc = {}
    if venc is not None:
        with torch.no_grad():
            for hi in h_pos:
                for wi in w_pos:
                    ph_s, pw_s = hi * AE_FACTOR, wi * AE_FACTOR
                    ph_e = min((hi + lt_size) * AE_FACTOR, lq_tensor.shape[2])
                    pw_e = min((wi + lt_size) * AE_FACTOR, lq_tensor.shape[3])
                    lq_crop = lq_tensor[:, :, ph_s:ph_e, pw_s:pw_e]
                    tile_venc[(hi, wi)] = get_venc_features(venc, lq_crop, args)
"""

NEW_BLOCK = """    # 20-20 TOOLBOX PERF PATCH: shared DINO features v1
    # DINOv2 is image-global context and preprocess_raw_image() already resizes
    # to the fixed DINO input size. Running ViT-L once per DiT tile made a
    # 2K/4K image invoke DINO dozens of times. Compute it once and crop its
    # token grid for each latent tile instead.
    z_fea_full = None
    if venc is not None:
        with torch.inference_mode():
            z_fea_full = get_venc_features(venc, lq_tensor, args)
"""

OLD_TILE = """                    z_fea_tile = tile_venc.get((hi, wi))
                    u_tile = model(inp, t_cur.expand(b), t_nxt.expand(b), z_fea_tile)
"""

NEW_TILE = """                    z_fea_tile = (
                        _crop_venc_features(z_fea_full, hi, wi, he, we, lh, lw)
                        if z_fea_full is not None else None
                    )
                    u_tile = model(inp, t_cur.expand(b), t_nxt.expand(b), z_fea_tile)
"""

def main() -> int:
    if not INFERENCE.is_file():
        print(f"[OPTIMIZE] Chybi {INFERENCE}")
        return 2

    text = INFERENCE.read_text(encoding="utf-8")

    if MARKER in text:
        print("[OPTIMIZE] VOSR performance patch uz je aplikovany.")
        return 0

    if OLD_BLOCK not in text:
        print("[OPTIMIZE] Neznamy VOSR source: blok per-tile DINO nebyl nalezen.")
        print("[OPTIMIZE] Soubor nebyl zmenen.")
        return 3

    if OLD_TILE not in text:
        print("[OPTIMIZE] Neznamy VOSR source: pouziti tile_venc nebylo nalezeno.")
        print("[OPTIMIZE] Soubor nebyl zmenen.")
        return 4

    if not BACKUP.exists():
        shutil.copy2(INFERENCE, BACKUP)

    patched = text.replace(OLD_BLOCK, NEW_BLOCK, 1).replace(OLD_TILE, NEW_TILE, 1)

    # Small safe runtime optimizations. These do not change model weights or
    # sampling steps; they only reduce autograd overhead on inference.
    patched = patched.replace(
        "    with torch.no_grad():\n        for step_i in range(n_steps):",
        "    with torch.inference_mode():\n        for step_i in range(n_steps):",
        1,
    )

    INFERENCE.write_text(patched, encoding="utf-8")

    # Syntax check without importing the heavy runtime.
    compile(patched, str(INFERENCE), "exec")
    print("[OPTIMIZE] HOTOVO: DINOv2 se v tiled rezimu pocita 1x misto 1x pro kazdou dlazdici.")
    print(f"[OPTIMIZE] Zaloha: {BACKUP}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
