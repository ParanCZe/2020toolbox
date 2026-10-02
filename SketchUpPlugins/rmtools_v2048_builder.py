#!/usr/bin/env python3
"""RM TOOLS v2.0.4.8: faster Meye browsing, decoding and repeated placement.

Build ONLY from released 2.0.4.7; other plugins, auto-Bridge and RM tag system
must be byte-identical. No Meye PNG assets are redistributed in the RBZ.
"""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

P=Path(__file__).resolve().parent
SRC=P/"RMToolsSuiteSourceV2048"
MEYE=P/"MeyeCutoutsSourceV011"
BASE=P/"20-20_RM_TOOLS_v2.0.4.7.rbz"
OUTPUT=P/"20-20_RM_TOOLS_v2.0.4.8.rbz"
MAIN="twentytwenty_rm_tools_suite/main.rb"
LOADER="twentytwenty_rm_tools_suite.rb"
MEYE_RB="twentytwenty_meye_cutouts/main.rb"
MEYE_UI="twentytwenty_meye_cutouts/ui/library.html"

def read(path):
    with ZipFile(path) as z:
        assert z.testzip() is None
        return {n:z.read(n) for n in z.namelist() if not n.endswith("/")}

def main():
    previous=read(BASE)
    current=dict(previous)
    main_source=(SRC/MAIN).read_bytes()
    cutout_source=(MEYE/MEYE_RB).read_bytes()
    cutout_ui=(MEYE/MEYE_UI).read_bytes()
    assert b"VERSION = '2.0.4.8'" in main_source
    assert b"VERSION = '0.1.1'" in cutout_source
    assert b"PAGE_SIZE = 12" in cutout_source
    assert b"def metadata_cache_read" in cutout_source
    assert b"def cached_png_opaque_bounds" in cutout_source
    assert b"def official_download_url(item)" in cutout_source
    assert b"html = get_request(item['page']" not in cutout_source
    assert b"defn = model.definitions.add(definition_name)" in cutout_source
    assert b"let" in cutout_ui
    current[MAIN]=main_source
    previous_loader=previous[LOADER].decode("utf-8")
    assert previous_loader.count("2.0.4.7")==1
    current[LOADER]=previous_loader.replace("2.0.4.7","2.0.4.8").encode()
    current[MEYE_RB]=cutout_source
    current[MEYE_UI]=cutout_ui
    changed={n for n in previous if previous[n]!=current[n]}
    assert changed=={MAIN,LOADER,MEYE_RB,MEYE_UI},changed
    assert set(current)==set(previous)
    with ZipFile(OUTPUT,"w",ZIP_DEFLATED) as z:
        for name,data in sorted(current.items()):
            z.writestr(name,data)
    assert read(OUTPUT)==current
    for name in changed:
        dest=SRC/name
        dest.parent.mkdir(parents=True,exist_ok=True)
        dest.write_bytes(current[name])
    print("BUILT:",OUTPUT.name,OUTPUT.stat().st_size)
    print("CHANGED:",sorted(changed))
    print("PASS: original Model Library, RM Checker, Mirror, Materials, Agent/Bridge unchanged")
    print("PASS: still zero Meye PNGs bundled in RBZ")

if __name__=="__main__":
    main()
