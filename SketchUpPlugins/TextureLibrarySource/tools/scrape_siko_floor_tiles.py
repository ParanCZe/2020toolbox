#!/usr/bin/env python3
import concurrent.futures
import html
import json
import re
import time
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup

BASE = "https://www.siko.cz"
CATEGORY = BASE + "/dlazby/c/C002"
OUT = "SketchUpPlugins/TextureLibrarySource/twentytwenty_texture_library/siko_floor_tiles.json"

SESSION = requests.Session()
SESSION.headers.update({
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/153 Safari/537.36",
    "Accept-Language": "cs-CZ,cs;q=0.9,en;q=0.7",
})

def clean(s):
    return re.sub(r"\s+", " ", html.unescape(s or "")).strip()

def get(url, timeout=30):
    last = None
    for i in range(4):
        try:
            r = SESSION.get(url, timeout=timeout)
            r.raise_for_status()
            return r.text
        except Exception as e:
            last = e
            time.sleep(0.7 * (i + 1))
    raise last

def parse_number_pair(s):
    s = clean(s).replace("×", "x").replace(",", ".")
    m = re.search(r"(\d+(?:\.\d+)?)\s*x\s*(\d+(?:\.\d+)?)", s, re.I)
    if not m:
        return None
    return float(m.group(1)), float(m.group(2))

def best_card(a):
    node = a
    for _ in range(8):
        if node is None:
            break
        txt = clean(node.get_text(" ", strip=True))
        links = [x.get("href") or "" for x in node.find_all("a", href=True)]
        product_links = [x for x in links if "/p/" in x]
        imgs = node.find_all("img")
        if len(txt) >= 30 and len(product_links) >= 1 and imgs:
            return node
        node = node.parent
    return a.parent or a

def image_from_card(card, code):
    candidates = []
    for im in card.find_all("img"):
        for attr in ("src", "data-src", "data-original", "data-lazy-src"):
            src = im.get(attr)
            if src:
                candidates.append((src, clean(im.get("alt"))))
        srcset = im.get("srcset") or im.get("data-srcset")
        if srcset:
            for part in srcset.split(","):
                src = part.strip().split(" ")[0]
                if src:
                    candidates.append((src, clean(im.get("alt"))))
    if not candidates:
        return ""
    # Prefer images that mention the product code, then SIKO media URLs.
    ranked = sorted(candidates, key=lambda t: (
        code.lower() not in (t[0] + " " + t[1]).lower(),
        "siko" not in t[0].lower(),
        "media" not in t[0].lower(),
        len(t[0]),
    ))
    return urljoin(BASE, ranked[0][0])

def product_name(a, card, code):
    # Prefer the richest product-link label inside the card.
    labels = []
    for link in card.find_all("a", href=True):
        href = link.get("href") or ""
        if "/p/" not in href:
            continue
        label = clean(link.get_text(" ", strip=True))
        if label:
            labels.append(label)
    if labels:
        name = max(labels, key=len)
    else:
        name = clean(a.get_text(" ", strip=True))
    # Listing labels sometimes append price/stock text; cut at the first obvious commerce suffix.
    name = re.split(r"\s+(?:\d[\d\s]*\s*Kč|Skladem\b|Super cena\b|Rektifikovan|Mrazuvzdorn)", name, maxsplit=1, flags=re.I)[0]
    return clean(name) or code

def item_from_listing(a, full, code):
    card = best_card(a)
    card_text = clean(card.get_text(" ", strip=True))
    name = product_name(a, card, code)
    img = image_from_card(card, code)

    dims = None
    patterns = [
        r"o\s+rozměru\s+([0-9.,]+\s*[x×]\s*[0-9.,]+)\s*cm",
        r"rozměr(?:u)?\s*[:]?\s*([0-9.,]+\s*[x×]\s*[0-9.,]+)\s*cm",
    ]
    for pat in patterns:
        m = re.search(pat, card_text, re.I)
        if m:
            dims = parse_number_pair(m.group(1))
            if dims:
                break
    nominal = parse_number_pair(name)
    if not dims:
        dims = nominal

    brand = ""
    m = re.match(r"(?:Dlažba(?:\s+II\.jakost)?|Schodovka|Sokl)\s+([^\s]+)", name, re.I)
    if m:
        brand = clean(m.group(1))

    w_cm = dims[0] if dims else None
    h_cm = dims[1] if dims else None
    nominal_text = f"{nominal[0]:g}x{nominal[1]:g}" if nominal else ""
    return {
        "code": code,
        "name": name,
        "brand": brand,
        "series": "",
        "width_cm": w_cm,
        "height_cm": h_cm,
        "size_cm": (f"{w_cm:g} × {h_cm:g}" if dims else ""),
        "nominal_size_cm": nominal_text,
        "image_url": img,
        "product_url": full,
        "source": "SIKO",
    }

def parse_detail(rec):
    text = get(rec["product_url"])
    soup = BeautifulSoup(text, "html.parser")
    page_text = clean(soup.get_text(" ", strip=True))
    h1 = soup.find("h1")
    if h1:
        rec["name"] = clean(h1.get_text(" ", strip=True)) or rec["name"]

    if not rec.get("image_url"):
        for key, attr in [("og:image", "property"), ("twitter:image", "name")]:
            tag = soup.find("meta", attrs={attr: key})
            if tag and tag.get("content"):
                rec["image_url"] = urljoin(BASE, tag["content"].strip())
                break

    if not (rec.get("width_cm") and rec.get("height_cm")):
        for pat in [
            r"Deklarovan[ýy]\s+rozměr\s*\(cm\)\s*([0-9.,]+\s*[x×]\s*[0-9.,]+)",
            r"o\s+rozměru\s+([0-9.,]+\s*[x×]\s*[0-9.,]+)\s*cm",
        ]:
            m = re.search(pat, page_text, re.I)
            if m:
                dims = parse_number_pair(m.group(1))
                if dims:
                    rec["width_cm"], rec["height_cm"] = dims
                    rec["size_cm"] = f"{dims[0]:g} × {dims[1]:g}"
                    break

    m = re.search(r"Značka\s*:\s*([^:]{1,60}?)(?=\s+Kategorie\s*:|\s+Série\s*:|\s+EAN\s*:)", page_text, re.I)
    if m:
        rec["brand"] = clean(m.group(1))
    m = re.search(r"Série\s*:\s*([^:]{1,80}?)(?=\s+EAN\s*:|\s+Popis|\s+Technické)", page_text, re.I)
    if m:
        rec["series"] = clean(m.group(1))
    return rec

def main():
    found = {}
    total_hint = None
    stale = 0
    for page in range(0, 280):
        url = f"{CATEGORY}?__bot=1&currentPage={page}"
        text = get(url)
        soup = BeautifulSoup(text, "html.parser")
        page_text = clean(soup.get_text(" ", strip=True))
        m = re.search(r"(\d+)\s+produkt(?:ů|u|y)", page_text, re.I)
        if m:
            total_hint = int(m.group(1))

        before = len(found)
        for a in soup.find_all("a", href=True):
            href = a.get("href") or ""
            if "/p/" not in href:
                continue
            full = urljoin(BASE, href.split("#")[0])
            if urlparse(full).netloc not in ("www.siko.cz", "siko.cz"):
                continue
            code = full.rstrip("/").split("/p/")[-1]
            if not code or len(code) > 80 or full in found:
                continue
            found[full] = item_from_listing(a, full, code)

        added = len(found) - before
        print(f"page {page}: +{added}, unique={len(found)}, total_hint={total_hint}", flush=True)
        stale = stale + 1 if added == 0 else 0
        if total_hint and len(found) >= total_hint:
            break
        if page >= 3 and stale >= 3:
            break
        time.sleep(0.12)

    items = list(found.values())
    missing = [x for x in items if not x.get("image_url") or not (x.get("width_cm") and x.get("height_cm"))]
    print(f"Listing scrape: {len(items)} products; detail fallback for {len(missing)}", flush=True)

    failures = []
    if missing:
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
            futs = {ex.submit(parse_detail, rec): rec for rec in missing}
            for i, fut in enumerate(concurrent.futures.as_completed(futs), 1):
                rec = futs[fut]
                try:
                    fut.result()
                except Exception as e:
                    failures.append({"url": rec["product_url"], "error": str(e)})
                if i % 50 == 0 or i == len(futs):
                    print(f"detail fallback {i}/{len(futs)}", flush=True)

    items.sort(key=lambda x: tuple(str(v or "").lower() for v in (x.get("brand"), x.get("series"), x.get("name"))))
    payload = {
        "category": "Dlažby",
        "source_url": CATEGORY,
        "source": "SIKO",
        "scraped_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "total_hint": total_hint,
        "count": len(items),
        "items": items,
        "failures": failures,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"Wrote {OUT}: {len(items)} items, {len(failures)} failures; "
          f"missing_image={sum(1 for x in items if not x.get('image_url'))}, "
          f"missing_dims={sum(1 for x in items if not (x.get('width_cm') and x.get('height_cm')))}", flush=True)

if __name__ == "__main__":
    main()
