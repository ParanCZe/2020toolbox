#!/usr/bin/env python3
import concurrent.futures
import gzip
import json
import re
import time
import xml.etree.ElementTree as ET
from html import unescape
from urllib.parse import urlparse, urlunparse, urlencode, parse_qsl

import requests
from bs4 import BeautifulSoup

BASE = "https://www.egger.com"
SITEMAP = BASE + "/sitemap/index.xml"
OUT = "SketchUpPlugins/TextureLibrarySource/twentytwenty_texture_library/egger_decors.json"

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/153 Safari/537.36",
    "Accept-Language": "cs-CZ,cs;q=0.9,en;q=0.7",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "Cache-Control": "no-cache",
}

DECOR_PATH = "/cs/vyroba-nabytku-a-interierovy-design/dekory/"

def clean(s):
    return re.sub(r"\s+", " ", unescape(str(s or ""))).strip()

def get_bytes(url, timeout=35):
    last = None
    for i in range(7):
        try:
            r = requests.get(url, headers=HEADERS, timeout=timeout)
            if r.status_code in (403, 429):
                last = RuntimeError(f"HTTP {r.status_code} for {url}")
                time.sleep(1.8 * (i + 1))
                continue
            r.raise_for_status()
            time.sleep(0.08)
            return r.content
        except Exception as e:
            last = e
            time.sleep(1.0 * (i + 1))
    raise last

def get_text(url, timeout=35):
    data = get_bytes(url, timeout)
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("utf-8", "replace")

def parse_xml_bytes(data, url=""):
    if url.endswith(".gz") or data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    return ET.fromstring(data)

def collect_decor_urls():
    seen_sitemaps = set()
    found = set()

    def walk(url, depth=0):
        if url in seen_sitemaps or depth > 3:
            return
        seen_sitemaps.add(url)
        try:
            data = get_bytes(url)
            root = parse_xml_bytes(data, url)
        except Exception as e:
            print(f"sitemap failed {url}: {e}", flush=True)
            return

        tag = root.tag.split("}")[-1].lower()
        locs = [clean(el.text) for el in root.iter() if el.tag.split("}")[-1].lower() == "loc" and el.text]
        if tag == "sitemapindex":
            # Walk all children. The index is modest and this is more robust than relying on names.
            for i, loc in enumerate(locs, 1):
                walk(loc, depth + 1)
                if i % 20 == 0:
                    print(f"sitemaps scanned {i}/{len(locs)}, decor urls={len(found)}", flush=True)
        else:
            for loc in locs:
                p = urlparse(loc)
                if DECOR_PATH in p.path:
                    # Strip query; country=CZ is applied during parsing.
                    found.add(urlunparse((p.scheme or "https", p.netloc or "www.egger.com", p.path, "", "", "")))

    walk(SITEMAP)
    urls = sorted(found)
    print(f"Found {len(urls)} Czech decor URLs in sitemap", flush=True)
    return urls

def with_country(url):
    p = urlparse(url)
    q = dict(parse_qsl(p.query, keep_blank_values=True))
    q["country"] = "CZ"
    return urlunparse((p.scheme, p.netloc, p.path, p.params, urlencode(q), ""))

def first_meta(soup, *, prop=None, name=None):
    attrs = {"property": prop} if prop else {"name": name}
    tag = soup.find("meta", attrs=attrs)
    return clean(tag.get("content")) if tag and tag.get("content") else ""

def parse_code_and_name(title, fallback_slug):
    title = clean(title)
    # Examples: "H1384 ST40 Dub Casella bílý", "U999 ST7 Černá", "F186 ST9 ..."
    m = re.match(r"^([A-Z]{1,2}\d{3,5})\s+([A-Z]{1,4}\d{0,3})\s+(.+)$", title, re.I)
    if m:
        return m.group(1).upper(), m.group(2).upper(), clean(m.group(3))
    # Some pages may expose only one code token in a title.
    m = re.match(r"^([A-Z]{1,2}\d{3,5})\s+(.+)$", title, re.I)
    if m:
        return m.group(1).upper(), "", clean(m.group(2))
    slug = fallback_slug.split("/")[-1]
    sm = re.match(r"([A-Z]{1,2}\d{3,5})[_-]?([A-Z]*\d*)", slug, re.I)
    if sm:
        base = sm.group(1).upper()
        texture = sm.group(2).upper()
        if texture.isdigit():
            texture = "ST" + texture
        return base, texture, title or base
    return slug.upper(), "", title or slug

def image_candidate(soup, code):
    # The first media-stage lightbox is EGGER's full decor image ("Deska"),
    # while later page images are often room/lifestyle photos. This is the asset
    # we want both for the library thumbnail and for the SketchUp material.
    stage = soup.find("egger-mediastage")
    if stage:
        links = stage.find_all("a", attrs={"data-egger-lightbox": "true"}, href=True)
        if links:
            href = clean(links[0].get("href"))
            if href:
                return href if href.startswith("http") else BASE + href

    # Download overlay fallback: prefer CAD/Raport thumbnails or direct PIM images.
    for node in soup.find_all("script", attrs={"type": "application/json"}):
        raw = node.string or ""
        if "imageDownloadItems" not in raw and "thumbUrl" not in raw:
            continue
        urls = re.findall(r'https://cdn\.egger\.com/[^"\\]+', raw)
        if urls:
            urls.sort(key=lambda u: ("pim/" not in u, "original" not in u.lower(), len(u)))
            return urls[0].replace("\\u0026", "&")

    # Last fallback: an image whose alt explicitly names this decor.
    for img in soup.find_all("img"):
        src = img.get("data-src") or img.get("src") or ""
        alt = clean(img.get("alt"))
        if src and code.lower() in alt.lower():
            return src if src.startswith("http") else BASE + src
    return ""

def parse_size_mm(text):
    # The page commonly says: "přibližně 2.311 x 1.300 mm"
    pats = [
        r"přibližně\s+([0-9.\s]+)\s*[x×]\s*([0-9.\s]+)\s*mm",
        r"approximately\s+([0-9,.\s]+)\s*[x×]\s*([0-9,.\s]+)\s*mm",
    ]
    vals = []
    for pat in pats:
        for m in re.finditer(pat, text, re.I):
            def num(s):
                s = re.sub(r"[^0-9]", "", s)
                return int(s) if s else 0
            a, b = num(m.group(1)), num(m.group(2))
            if a > 300 and b > 300:
                vals.append((a, b))
    if vals:
        # Use the largest area size: full decor image instead of small preview.
        return max(vals, key=lambda ab: ab[0] * ab[1])
    return (2311, 1300)

def parse_decor(url):
    detail_url = with_country(url)
    html = get_text(detail_url)
    soup = BeautifulSoup(html, "html.parser")

    h1 = soup.find("h1")
    title = clean(h1.get_text(" ", strip=True)) if h1 else ""
    if not title:
        title = first_meta(soup, prop="og:title") or clean(soup.title.get_text(" ", strip=True) if soup.title else "")
        title = re.sub(r"\s*\|\s*EGGER.*$", "", title, flags=re.I)

    base_code, texture, name = parse_code_and_name(title, urlparse(url).path)
    full_code = clean((base_code + " " + texture).strip())

    image_url = image_candidate(soup, base_code)
    page_text = clean(soup.get_text(" ", strip=True))
    width_mm, height_mm = parse_size_mm(page_text)

    # Directionality is useful metadata for future mapping controls.
    directional = bool(re.search(r"Směrově\s+orientovaný\s+dekor\s+Ano", page_text, re.I))

    return {
        "manufacturer": "EGGER",
        "code": full_code or base_code,
        "base_code": base_code,
        "texture": texture,
        "name": name,
        "full_name": clean((full_code + " " + name).strip()),
        "image_url": image_url,
        "product_url": detail_url,
        "width_mm": width_mm,
        "height_mm": height_mm,
        "directional": directional,
        "source": "EGGER",
    }

def main():
    urls = collect_decor_urls()
    items = []
    failures = []

    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:
        futs = {ex.submit(parse_decor, url): url for url in urls}
        for i, fut in enumerate(concurrent.futures.as_completed(futs), 1):
            url = futs[fut]
            try:
                item = fut.result()
                # Exclude malformed pages and duplicate routes.
                if item.get("base_code") and item.get("name") and item.get("image_url"):
                    items.append(item)
                else:
                    failures.append({"url": url, "error": "missing code/name/image"})
            except Exception as e:
                failures.append({"url": url, "error": str(e)})
            if i % 50 == 0 or i == len(futs):
                print(f"decor pages {i}/{len(futs)}; valid={len(items)} failures={len(failures)}", flush=True)

    # Same decor may occur in multiple sitemap variants; dedupe by code.
    dedup = {}
    for item in items:
        key = item["code"].upper()
        old = dedup.get(key)
        if old is None or len(item.get("name", "")) > len(old.get("name", "")):
            dedup[key] = item
    items = sorted(dedup.values(), key=lambda x: (x.get("base_code", ""), x.get("texture", ""), x.get("name", "").lower()))

    payload = {
        "category": "Dekor",
        "manufacturer": "EGGER",
        "source_url": "https://www.egger.com/cs/vyroba-nabytku-a-interierovy-design/?country=CZ",
        "scraped_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "count": len(items),
        "items": items,
        "failures": failures,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"Wrote {OUT}: {len(items)} EGGER decors, failures={len(failures)}", flush=True)
    if items:
        print("SAMPLES", json.dumps(items[:5], ensure_ascii=False), flush=True)

if __name__ == "__main__":
    main()
