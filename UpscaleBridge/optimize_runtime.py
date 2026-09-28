from __future__ import annotations

import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent
INFERENCE = ROOT / "runtime" / "VOSR" / "inference_vosr_onestep.py"
BACKUP = INFERENCE.with_suffix(".py.toolbox-original.bak")
PERF_V1 = "# 20-20 TOOLBOX PERF PATCH: shared DINO features v1"
PROGRESS_V2 = "# 20-20 TOOLBOX PROGRESS PATCH v2"

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
    # DINOv2 is computed once for the full image. Each DiT tile then crops the
    # corresponding token region instead of running ViT-L again.
    z_fea_full = None
    if venc is not None:
        print("TOOLBOX_PROGRESS|dino|0|1", flush=True)
        with torch.inference_mode():
            z_fea_full = get_venc_features(venc, lq_tensor, args)
        print("TOOLBOX_PROGRESS|dino|1|1", flush=True)
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

def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f"Patch point not found: {label}")
    return text.replace(old, new, 1)

def add_progress(text: str) -> str:
    if PROGRESS_V2 in text:
        return text

    # Full VAE encode.
    old = "    with torch.no_grad():\n        lq_latent, latents_mean, latents_std = encode_dispatch(vae, lq_tensor, args, device)"
    new = '    print("TOOLBOX_PROGRESS|vae_encode|0|1", flush=True)\n' + old + '\n    print("TOOLBOX_PROGRESS|vae_encode|1|1", flush=True)'
    text = replace_once(text, old, new, "VAE encode")

    # Tiled DiT progress.
    old = "    with torch.inference_mode():\n        for step_i in range(n_steps):"
    if old not in text:
        old = "    with torch.no_grad():\n        for step_i in range(n_steps):"
    new = (
        '    total_dit_tiles = max(1, n_steps * len(h_pos) * len(w_pos))\n'
        '    dit_done = 0\n'
        '    print(f"TOOLBOX_PROGRESS|dit|0|{total_dit_tiles}", flush=True)\n'
        '    with torch.inference_mode():\n'
        '        for step_i in range(n_steps):'
    )
    text = replace_once(text, old, new, "DiT loop")

    old = "                    w_acc[:, :, hi:he, wi:we] += g_weight\n"
    new = (
        old +
        '                    dit_done += 1\n'
        '                    print(f"TOOLBOX_PROGRESS|dit|{dit_done}|{total_dit_tiles}", flush=True)\n'
    )
    text = replace_once(text, old, new, "DiT tile counter")

    # Tiled VAE decode.
    old = "    with torch.no_grad():\n        return decode_dispatch(vae, z, args, latents_mean, latents_std, light_decoder)"
    new = (
        '    print("TOOLBOX_PROGRESS|vae_decode|0|1", flush=True)\n'
        '    with torch.inference_mode():\n'
        '        decoded = decode_dispatch(vae, z, args, latents_mean, latents_std, light_decoder)\n'
        '    print("TOOLBOX_PROGRESS|vae_decode|1|1", flush=True)\n'
        '    return decoded'
    )
    text = replace_once(text, old, new, "VAE decode")

    # Model loading / save phase markers.
    text = text.replace(
        '    print(f"Loading model from {args.checkpoint}...")',
        '    print("TOOLBOX_PROGRESS|model_load|0|1", flush=True)\n    print(f"Loading model from {args.checkpoint}...")',
        1,
    )
    text = text.replace(
        '    model.forward = model.forward_flexible',
        '    model.forward = model.forward_flexible\n    print("TOOLBOX_PROGRESS|model_load|1|1", flush=True)',
        1,
    )
    text = text.replace(
        "            sr_img.save(os.path.join(out_dir, os.path.splitext(img_name)[0] + '.png'))",
        '            print("TOOLBOX_PROGRESS|save|0|1", flush=True)\n'
        "            sr_img.save(os.path.join(out_dir, os.path.splitext(img_name)[0] + '.png'))\n"
        '            print("TOOLBOX_PROGRESS|save|1|1", flush=True)',
        1,
    )

    # Ensure a durable marker exists.
    text = text.replace("import os\n", "import os\n" + PROGRESS_V2 + "\n", 1)
    return text

def main() -> int:
    if not INFERENCE.is_file():
        print(f"[OPTIMIZE] Chybi {INFERENCE}")
        return 2

    text = INFERENCE.read_text(encoding="utf-8")
    if not BACKUP.exists():
        shutil.copy2(INFERENCE, BACKUP)

    try:
        if PERF_V1 not in text:
            text = replace_once(text, OLD_BLOCK, NEW_BLOCK, "per-tile DINO block")
            text = replace_once(text, OLD_TILE, NEW_TILE, "tile_venc usage")
        else:
            # Older v1 patch did not contain progress prints around DINO.
            if 'TOOLBOX_PROGRESS|dino|' not in text:
                text = text.replace(
                    "        with torch.inference_mode():\n            z_fea_full = get_venc_features(venc, lq_tensor, args)",
                    '        print("TOOLBOX_PROGRESS|dino|0|1", flush=True)\n'
                    "        with torch.inference_mode():\n"
                    "            z_fea_full = get_venc_features(venc, lq_tensor, args)\n"
                    '        print("TOOLBOX_PROGRESS|dino|1|1", flush=True)',
                    1,
                )

        text = add_progress(text)
        compile(text, str(INFERENCE), "exec")
        INFERENCE.write_text(text, encoding="utf-8")
    except Exception as exc:
        print(f"[OPTIMIZE] CHYBA: {exc}")
        return 3

    print("[OPTIMIZE] HOTOVO: shared DINO + real phase/tile progress.")
    print(f"[OPTIMIZE] Zaloha: {BACKUP}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
