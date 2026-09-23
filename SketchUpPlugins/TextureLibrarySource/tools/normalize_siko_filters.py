#!/usr/bin/env python3
import json
import re
from pathlib import Path

FILES = [
    Path("SketchUpPlugins/TextureLibrarySource/twentytwenty_texture_library/siko_concrete_tiles.json"),
    Path("SketchUpPlugins/TextureLibrarySource/twentytwenty_texture_library/siko_floor_tiles.json"),
]

TYPE_PREFIXES = [
    r"dlažba(?:\s+II\.jakost)?",
    r"dlazba(?:\s+II\.jakost)?",
    r"obklad",
    r"dekor",
    r"schodovka",
    r"sokl",
    r"mozaika",
    r"listela",
    r"rohovka",
    r"obkladový\s+prvek",
    r"vzorek",
]

SKIP_AFTER_TYPE = {
    "venkovní","venkovni","interiérová","interierova","keramická","keramicka",
    "slinutá","slinuta","mrazuvzdorná","mrazuvzdorna","rektifikovaná","rektifikovana",
    "velkoformátová","velkoformatova","bazénová","bazenova","bazénový","bazenovy",
    "protiskluzná","protiskluzna","technická","technicka","2cm","2","cm",
}

COLOR_WORDS = {
    "bílá","bily","bílý","bila","bílošedá","biloseda","white","bianco","blanco","snow",
    "šedá","seda","šedý","sedy","grey","gray","grigio","gris","graphite","grafit","antracit","anthracite",
    "béžová","bezova","béžový","bezovy","beige","ivory","nude","cream","crema","sand","sabbia","taupe","greige","bone",
    "hnědá","hneda","hnědý","hnedy","brown","marron","marrone","bruno","noce","walnut","chocolate","coffee","cacao",
    "černá","cerna","černý","cerny","black","nero","negro",
    "modrá","modra","modrý","modry","blue","blu","azzur","navy",
    "zelená","zelena","zelený","zeleny","green","verde","sage","mint","olive","olivová","olivova",
    "červená","cervena","červený","cerveny","red","rosso","rouge",
    "oranžová","oranzova","orange","arancio","terracotta","coral",
    "žlutá","zluta","yellow","giallo","gold","zlatá","zlata",
    "růžová","ruzova","pink","rosa","rose",
    "fialová","fialova","violet","purple","lila","lilac",
    "přírodní","prirodni","natural","naturale","nature","roble","dune","paper","cenere","ash",
    "mix","barev","barevná","barevny","barevný","světle","svetle","tmavě","tmave",
}

FINISH_WORDS = {
    "mat","lesk","pololesk","lapato","lappato","reliéf","relief","satin","satinato",
    "protiskluz","rektifikovaná","rektifikovana",
}

def clean(s):
    return re.sub(r"\s+", " ", str(s or "")).strip()

def n(s):
    return clean(s).lower()

def display_num(x):
    x = float(str(x).replace(",", "."))
    return f"{x:g}"

def nominal_size_from_name(name):
    m = re.search(r"(?<!\d)(\d+(?:[.,]\d+)?)\s*[x×]\s*(\d+(?:[.,]\d+)?)\s*cm\b", name, re.I)
    if not m:
        return ""
    return f"{display_num(m.group(1))} × {display_num(m.group(2))}"

def strip_prefix(name):
    s = re.sub(r"^\s*\(\d+\)\s*", "", clean(name))
    for pat in TYPE_PREFIXES:
        m = re.match(r"^" + pat + r"\b\s*", s, re.I)
        if m:
            s = s[m.end():].strip()
            break
    # Product cards occasionally add "II.jakost" after the generic type.
    s = re.sub(r"^II\.jakost\s+", "", s, flags=re.I)
    return s

def tokens_before_dimension(name):
    s = strip_prefix(name)
    m = re.search(r"\b\d+(?:[.,]\d+)?\s*[x×]\s*\d+(?:[.,]\d+)?\s*cm\b", s, re.I)
    if m:
        s = s[:m.start()]
    return re.findall(r"[A-Za-zÀ-ž0-9.&+\-]+", s)

def infer_brand(name):
    toks = tokens_before_dimension(name)
    while toks and (n(toks[0]) in SKIP_AFTER_TYPE or re.fullmatch(r"\d+(?:[.,]\d+)?(?:cm)?", toks[0], re.I)):
        toks.pop(0)
    return toks[0] if toks else ""

def sane_brand(v):
    v = clean(v)
    if not v or len(v) > 40:
        return False
    if re.fullmatch(r"[\d.\- ]+", v):
        return False
    if re.fullmatch(r"\d+(?:cm)?", v, re.I):
        return False
    return bool(re.search(r"[A-Za-zÀ-ž]", v))

def infer_series(name, brand):
    toks = tokens_before_dimension(name)
    # Drop everything through the exact SIKO brand. What follows is normally
    # "Series [colour/variant]"; SIKO writes the series in title case while
    # colour/variant tokens are usually lower-case.
    idx = None
    for i,t in enumerate(toks):
        if n(t) == n(brand):
            idx = i
            break
    rest = toks[idx+1:] if idx is not None else toks[1:]
    out = []
    connectors = {"and","&","di","de","del","of"}
    for t in rest:
        lt = n(t)
        if lt in COLOR_WORDS or lt in FINISH_WORDS:
            break
        if re.fullmatch(r"\d+(?:[.,]\d+)?", t):
            break
        if len(t) >= 6 and any(ch.isdigit() for ch in t) and any(ch.isalpha() for ch in t) and t.upper() == t:
            break
        # Once the series has started, a lower-case word is almost always the
        # colour/variant (Kenzo ivory, Miami light, Extra slonová...). Preserve
        # connector words used inside genuine multi-word series.
        if out and t[:1].islower() and lt not in connectors:
            break
        out.append(t)
    return " ".join(out).strip()

def normalize_existing_series(series, brand):
    s = clean(series)
    if not s:
        return ""
    s = re.sub(r"^" + re.escape(clean(brand)) + r"\s+", "", s, flags=re.I).strip() if brand else s
    if not s or re.fullmatch(r"[\d.\- x×]+", s):
        return ""
    if re.fullmatch(r"\d+x\d+(?:x\d+)?", s, re.I):
        return ""
    return s

def normalize_item(item):
    name = clean(item.get("name"))
    inferred_brand = infer_brand(name)
    existing_brand = clean(item.get("brand"))
    # Prefer SIKO's own brand metadata whenever it is present. The product title
    # contains many descriptors (corner piece, 2 cm, outdoor, etc.) that are not brands.
    brand = existing_brand if sane_brand(existing_brand) else inferred_brand
    if not sane_brand(brand):
        brand = "Ostatní"

    # Derive the series from the SIKO product title instead of trusting stale/combined
    # detail-page breadcrumbs. This maps Rako Rave -> Rave, Argenta Kenzo -> Kenzo, etc.
    series = infer_series(name, brand)
    if not series or n(series) in COLOR_WORDS or re.fullmatch(r"[\d.\- x×]+", series):
        series = "Ostatní"

    nominal = nominal_size_from_name(name)
    if not nominal:
        # Fall back to SIKO nominal_size_cm only when it is clean.
        nm = clean(item.get("nominal_size_cm"))
        pair = re.search(r"(\d+(?:[.,]\d+)?)\s*[x×]\s*(\d+(?:[.,]\d+)?)", nm)
        if pair:
            nominal = f"{display_num(pair.group(1))} × {display_num(pair.group(2))}"
    if not nominal:
        nominal = "Neuvedeno"

    item["filter_brand"] = brand
    item["filter_product"] = series
    item["filter_size"] = nominal
    # keep filter_color from the color classifier
    return item

def main():
    for path in FILES:
        if not path.exists():
            print("missing", path)
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        raw_items = list(data.get("items") or [])
        # The broad SIKO "Dlažby" category also contains tools/accessories. Keep only
        # actual surface products that make sense in a texture library.
        allowed = re.compile(r"^\s*(?:\(\d+\)\s*)?(?:Dlažba|Obklad|Dekor|Mozaika|Sokl|Schodovka)\b", re.I)
        items = [normalize_item(x) for x in raw_items if allowed.search(clean(x.get("name")))]
        data["items"] = items
        data["filters"] = {
            "brand": sorted({x["filter_brand"] for x in items}, key=str.casefold),
            "product": sorted({x["filter_product"] for x in items}, key=str.casefold),
            "size": sorted({x["filter_size"] for x in items}, key=str.casefold),
            "color": sorted({clean(x.get("filter_color")) for x in items if clean(x.get("filter_color"))}, key=str.casefold),
        }
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(path.name, "items", len(items))
        print(" brands sample:", data["filters"]["brand"][:40])
        print(" series sample:", data["filters"]["product"][:60])
        print(" sizes sample:", data["filters"]["size"][:60])

if __name__ == "__main__":
    main()
