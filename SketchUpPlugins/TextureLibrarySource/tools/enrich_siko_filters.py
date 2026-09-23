#!/usr/bin/env python3
import concurrent.futures
import io
import json
import math
import re
import colorsys
from pathlib import Path

import requests
from PIL import Image, ImageStat

FILES = [
    Path("SketchUpPlugins/TextureLibrarySource/twentytwenty_texture_library/siko_concrete_tiles.json"),
    Path("SketchUpPlugins/TextureLibrarySource/twentytwenty_texture_library/siko_floor_tiles.json"),
]

COLOR_WORDS = [
    ("Černá", ["čern", "black", "nero", "noir", "negro"]),
    ("Bílá", ["bíl", "white", "bianco", "blanco", "blanc", "snow"]),
    ("Šedá", ["šed", "grey", "gray", "grigio", "gris", "grau", "silver", "stříbr", "cement", "beton", "graphite", "grafit", "antracit", "anthracite", "ash", "cenere"]),
    ("Béžová", ["béž", "beige", "ivory", "avorio", "nude", "cream", "crema", "sand", "sabbia", "taupe", "greige"]),
    ("Hnědá", ["hněd", "brown", "marron", "marrone", "bruno", "noce", "walnut", "chocolate", "coffee", "cacao", "cotto"]),
    ("Modrá", ["modr", "blue", "blu", "azzur", "ocean", "navy"]),
    ("Zelená", ["zelen", "green", "verde", "sage", "mint", "oliv"]),
    ("Červená", ["červen", "red", "rosso", "rouge", "rubin", "ruby"]),
    ("Oranžová", ["oranž", "orange", "arancio", "terracotta", "terra cotta", "coral"]),
    ("Žlutá", ["žlut", "yellow", "giallo", "gold", "zlat"]),
    ("Růžová", ["růž", "pink", "rosa", "rose"]),
    ("Fialová", ["fial", "violet", "purple", "lila", "lilac"]),
]

PREFIX_WORDS = {
    "dlažba","dlazba","obklad","obklady","dlaždice","dlazdice","schodovka","sokl",
    "mozaika","dekor","listela","roh","rohovka","reliéf","relief","venkovní","venkovni",
    "mrazuvzdorná","mrazuvzdorna","rektifikovaná","rektifikovana"
}

session = requests.Session()
session.headers.update({
    "User-Agent": "20-20 Texture Library color classifier/1.0",
    "Accept": "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
})

def clean(s):
    return re.sub(r"\s+", " ", str(s or "")).strip()

def norm(s):
    return clean(s).lower()

def infer_brand(item):
    brand = clean(item.get("brand"))
    if brand:
        return brand
    name = clean(item.get("name"))
    tokens = re.findall(r"[A-Za-zÀ-ž0-9.-]+", name)
    for i, tok in enumerate(tokens):
        if norm(tok) in PREFIX_WORDS:
            continue
        # First non-prefix token is commonly the brand on SIKO names.
        return tok
    return ""

def infer_product(item, brand):
    series = clean(item.get("series"))
    if series:
        # SIKO often stores e.g. "Rako Betonico" / "Argenta Kenzo".
        s = re.sub(r"^" + re.escape(brand) + r"\s+", "", series, flags=re.I).strip() if brand else series
        # Multiple series can occasionally be comma-separated; use the primary one for filtering.
        s = s.split(",")[0].strip()
        if s:
            return s

    name = clean(item.get("name"))
    # Remove dimensions, code suffix and common type/finish words.
    text = re.sub(r"\b\d+(?:[.,]\d+)?\s*[x×]\s*\d+(?:[.,]\d+)?\s*cm\b", " ", name, flags=re.I)
    text = re.sub(r"\b(mat|lesk|lapato|pololesk|reliéf|relief|protiskluz|rektifikovaná|rektifikovana)\b", " ", text, flags=re.I)
    if brand:
        text = re.sub(r"\b" + re.escape(brand) + r"\b", " ", text, count=1, flags=re.I)
    tokens = [t for t in re.findall(r"[A-Za-zÀ-ž0-9.-]+", text) if norm(t) not in PREFIX_WORDS]
    # Remove obvious color words so "Kenzo ivory" resolves to "Kenzo".
    color_fragments = {w for _, words in COLOR_WORDS for w in words}
    filtered = []
    for t in tokens:
        lt = norm(t)
        if any(w in lt for w in color_fragments):
            continue
        if re.fullmatch(r"[A-Z0-9._-]{5,}", t) and any(ch.isdigit() for ch in t):
            continue
        filtered.append(t)
    return filtered[0] if filtered else (tokens[0] if tokens else "")

def normalized_size(item):
    try:
        w = float(item.get("width_cm") or 0)
        h = float(item.get("height_cm") or 0)
    except Exception:
        return clean(item.get("size_cm"))
    if w <= 0 or h <= 0:
        return clean(item.get("size_cm"))
    a, b = sorted((w, h))
    return f"{a:g} × {b:g}"

def color_from_text(item):
    hay = norm(" ".join([
        clean(item.get("name")),
        clean(item.get("series")),
        clean(item.get("brand")),
    ]))
    for label, words in COLOR_WORDS:
        if any(w in hay for w in words):
            return label
    return ""

def color_from_image(url):
    if not url:
        return ""
    try:
        r = session.get(url, timeout=18)
        r.raise_for_status()
        im = Image.open(io.BytesIO(r.content)).convert("RGB")
        im.thumbnail((72, 72))
        pixels = list(im.getdata())
        if not pixels:
            return ""

        # Ignore near-white website/background pixels and tiny near-black borders.
        chosen = []
        for rr, gg, bb in pixels:
            mx, mn = max(rr, gg, bb), min(rr, gg, bb)
            if mx > 245 and mx - mn < 10:
                continue
            if mx < 8:
                continue
            chosen.append((rr, gg, bb))
        if len(chosen) < max(20, len(pixels)//12):
            chosen = pixels

        # Robust average: trim very bright and very dark outliers by luminance.
        enriched = []
        for rr, gg, bb in chosen:
            lum = 0.2126*rr + 0.7152*gg + 0.0722*bb
            enriched.append((lum, rr, gg, bb))
        enriched.sort(key=lambda x: x[0])
        lo = len(enriched)//10
        hi = max(lo+1, len(enriched)-lo)
        core = enriched[lo:hi]
        rr = sum(x[1] for x in core)/len(core)/255.0
        gg = sum(x[2] for x in core)/len(core)/255.0
        bb = sum(x[3] for x in core)/len(core)/255.0
        h, s, v = colorsys.rgb_to_hsv(rr, gg, bb)
        deg = h*360.0

        if s < 0.11:
            if v > 0.84:
                return "Bílá"
            if v < 0.27:
                return "Černá"
            return "Šedá"
        if s < 0.24 and v > 0.62 and (deg < 75 or deg > 335):
            return "Béžová"
        if 15 <= deg < 50:
            if v < 0.58:
                return "Hnědá"
            if s < 0.42:
                return "Béžová"
            return "Oranžová"
        if 50 <= deg < 72:
            return "Žlutá" if s > 0.34 else "Béžová"
        if 72 <= deg < 170:
            return "Zelená"
        if 170 <= deg < 255:
            return "Modrá"
        if 255 <= deg < 315:
            return "Fialová"
        if 315 <= deg < 345:
            return "Růžová"
        return "Červená"
    except Exception:
        return ""

def enrich_item(item, use_image=True):
    brand = infer_brand(item)
    product = infer_product(item, brand)
    color = color_from_text(item)
    existing_color = clean(item.get("filter_color"))
    if not color and existing_color and existing_color != "Ostatní":
        color = existing_color
    if not color and use_image:
        color = color_from_image(clean(item.get("image_url")))
    item["filter_brand"] = brand or "Ostatní"
    item["filter_product"] = product or "Ostatní"
    item["filter_size"] = normalized_size(item) or "Neuvedeno"
    item["filter_color"] = color or "Ostatní"
    return item

def main():
    for path in FILES:
        if not path.exists():
            print(f"skip missing {path}")
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        items = list(data.get("items") or [])
        # Text classification first; only ambiguous items pay the network cost.
        unknown = []
        for item in items:
            enrich_item(item, use_image=False)
            if item.get("filter_color") == "Ostatní":
                unknown.append(item)
        print(f"{path.name}: {len(items)} items, image classification needed for {len(unknown)}", flush=True)

        with concurrent.futures.ThreadPoolExecutor(max_workers=12) as ex:
            futures = {ex.submit(color_from_image, clean(item.get("image_url"))): item for item in unknown}
            for i, fut in enumerate(concurrent.futures.as_completed(futures), 1):
                item = futures[fut]
                try:
                    color = fut.result()
                    if color:
                        item["filter_color"] = color
                except Exception:
                    pass
                if i % 250 == 0 or i == len(futures):
                    print(f"  color images {i}/{len(futures)}", flush=True)

        data["items"] = items
        data["filters"] = {
            "brand": sorted({x.get("filter_brand") for x in items if x.get("filter_brand")}, key=str.casefold),
            "product": sorted({x.get("filter_product") for x in items if x.get("filter_product")}, key=str.casefold),
            "size": sorted({x.get("filter_size") for x in items if x.get("filter_size")}, key=str.casefold),
            "color": sorted({x.get("filter_color") for x in items if x.get("filter_color")}, key=str.casefold),
        }
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        counts = {}
        for item in items:
            counts[item["filter_color"]] = counts.get(item["filter_color"], 0) + 1
        print(f"  colors: {counts}", flush=True)

if __name__ == "__main__":
    main()
