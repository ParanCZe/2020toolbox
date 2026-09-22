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
CATEGORY = BASE + "/obklady-imitace-betonu/c/C001-virt137"
OUT = "SketchUpPlugins/TextureLibrarySource/twentytwenty_texture_library/siko_concrete_tiles.json"

SESSION = requests.Session()
SESSION.headers.update({
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/153 Safari/537.36",
    "Accept-Language": "cs-CZ,cs;q=0.9,en;q=0.7",
})

def clean(s):
    return re.sub(r"\s+", " ", html.unescape(s or "")).strip()

def get(url, timeout=25):
    last = None
    for i in range(4):
        try:
            r = SESSION.get(url, timeout=timeout)
            r.raise_for_status()
            return r.text
        except Exception as e:
            last = e
            time.sleep(0.6 * (i + 1))
    raise last

def product_links_from_category():
    found = {}
    total_hint = None
    stale = 0
    for page in range(0, 16):
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
            # SIKO product URL ends in /p/<product-code>
            if "/p/" not in href:
                continue
            full = urljoin(BASE, href.split("#")[0])
            if urlparse(full).netloc not in ("www.siko.cz", "siko.cz"):
                continue
            label = clean(a.get_text(" ", strip=True))
            code = full.rstrip("/").split("/p/")[-1]
            # Avoid non-product helper links and keep the best visible label.
            if not code or len(code) > 80:
                continue
            old = found.get(full)
            if old is None or len(label) > len(old.get("listing_name", "")):
                found[full] = {"url": full, "listing_name": label, "code": code}

        added = len(found) - before
        print(f"page {page}: +{added}, unique={len(found)}, total_hint={total_hint}", flush=True)
        if added == 0:
            stale += 1
        else:
            stale = 0
        if total_hint and len(found) >= total_hint:
            break
        if page >= 3 and stale >= 2:
            break
        time.sleep(0.15)
    return list(found.values()), total_hint

def parse_number_pair(s):
    s = clean(s).replace("×", "x").replace(",", ".")
    m = re.search(r"(\d+(?:\.\d+)?)\s*x\s*(\d+(?:\.\d+)?)", s, re.I)
    if not m:
        return None
    return float(m.group(1)), float(m.group(2))

def parse_product(rec):
    text = get(rec["url"])
    soup = BeautifulSoup(text, "html.parser")

    h1 = soup.find("h1")
    name = clean(h1.get_text(" ", strip=True)) if h1 else clean(rec.get("listing_name"))
    if not name:
        name = rec["code"]

    img = ""
    for key, attr in [("og:image", "property"), ("twitter:image", "name")]:
        tag = soup.find("meta", attrs={attr: key})
        if tag and tag.get("content"):
            img = urljoin(BASE, tag["content"].strip())
            break
    if not img:
        # fallback to largest-looking product image
        for im in soup.find_all("img"):
            src = im.get("src") or im.get("data-src") or im.get("data-original")
            alt = clean(im.get("alt"))
            if src and (rec["code"].lower() in (src + " " + alt).lower() or "product" in (src + " " + (im.get("class") and " ".join(im.get("class")) or "")).lower()):
                img = urljoin(BASE, src)
                break

    page_text = clean(soup.get_text(" ", strip=True))
    dims = None
    patterns = [
        r"Deklarovan[ýy]\s+rozměr\s*\(cm\)\s*([0-9.,]+\s*[x×]\s*[0-9.,]+)",
        r"o\s+rozměru\s+([0-9.,]+\s*[x×]\s*[0-9.,]+)\s*cm",
        r"rozměr(?:u)?\s*[:]?\s*([0-9.,]+\s*[x×]\s*[0-9.,]+)\s*cm",
    ]
    dim_text = ""
    for pat in patterns:
        m = re.search(pat, page_text, re.I)
        if m:
            dim_text = clean(m.group(1))
            dims = parse_number_pair(dim_text)
            if dims:
                break
    if not dims:
        dims = parse_number_pair(name)
        if dims:
            dim_text = f"{dims[0]:g}x{dims[1]:g}"

    nominal = None
    m = re.search(r"Jmenovit[ýy]\s+rozměr\s*\(cm\)\s*([0-9.,]+\s*[x×]\s*[0-9.,]+)", page_text, re.I)
    if m:
        nominal = clean(m.group(1))

    brand = ""
    m = re.search(r"Značka\s*:\s*([^:]{1,60}?)(?=\s+Kategorie\s*:|\s+Série\s*:|\s+EAN\s*:)", page_text, re.I)
    if m:
        brand = clean(m.group(1))

    series = ""
    m = re.search(r"Série\s*:\s*([^:]{1,80}?)(?=\s+EAN\s*:|\s+Popis|\s+Technické)", page_text, re.I)
    if m:
        series = clean(m.group(1))

    w_cm = dims[0] if dims else None
    h_cm = dims[1] if dims else None
    return {
        "code": rec["code"],
        "name": name,
        "brand": brand,
        "series": series,
        "width_cm": w_cm,
        "height_cm": h_cm,
        "size_cm": (f"{w_cm:g} × {h_cm:g}" if dims else ""),
        "nominal_size_cm": nominal or "",
        "image_url": img,
        "product_url": rec["url"],
        "source": "SIKO",
    }

def main():
    links, total_hint = product_links_from_category()
    print(f"Scraping {len(links)} product pages...", flush=True)
    items = []
    failures = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as ex:
        futs = {ex.submit(parse_product, rec): rec for rec in links}
        for i, fut in enumerate(concurrent.futures.as_completed(futs), 1):
            rec = futs[fut]
            try:
                item = fut.result()
                items.append(item)
            except Exception as e:
                failures.append({"url": rec["url"], "error": str(e)})
            if i % 20 == 0 or i == len(futs):
                print(f"done {i}/{len(futs)}", flush=True)

    items.sort(key=lambda x: (x.get("brand") or "", x.get("series") or "", x.get("name") or "").lower())
    payload = {
        "category": "Betonové obklady",
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
    print(f"Wrote {OUT}: {len(items)} items, {len(failures)} failures", flush=True)

if __name__ == "__main__":
    main()
