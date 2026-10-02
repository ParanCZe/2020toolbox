#!/usr/bin/env python3
"""RM TOOLS 2.0.4.7: Meye online 2D foliage on demand, original RM core.

Uses the exact released 2.0.4.6 as its sole base. Adds only the original
Meye metadata/thumbnail browser and a runtime PNG importer. No Meye artwork
or PNG assets are redistributed in the RBZ.
"""
from pathlib import Path
from zipfile import ZipFile,ZIP_DEFLATED

P=Path(__file__).resolve().parent
SRC=P/"RMToolsSuiteSourceV2047"
MEYE=P/"MeyeCutoutsSourceV010"
BASE=P/"20-20_RM_TOOLS_v2.0.4.6.rbz"
OUT=P/"20-20_RM_TOOLS_v2.0.4.7.rbz"
SUITE_MAIN="twentytwenty_rm_tools_suite/main.rb"
SUITE_LOADER="twentytwenty_rm_tools_suite.rb"
TREE_MAIN="twentytwenty_meye_cutouts/main.rb"
TREE_UI="twentytwenty_meye_cutouts/ui/library.html"

def read(path):
    with ZipFile(path) as z:
        assert z.testzip() is None,path
        return {n:z.read(n) for n in z.namelist() if not n.endswith("/")}

def replace_once(s,old,new,label):
    assert s.count(old)==1,(label,s.count(old))
    return s.replace(old,new,1)

def main():
    old=read(BASE)
    result=dict(old)
    main=(SRC/SUITE_MAIN).read_text(encoding="utf-8")
    assert "VERSION = '2.0.4.7'.freeze" in main
    assert "suite_meye_cutouts" in main
    assert "open_meye_cutouts" in main
    assert "sketchup.suite_model_library()" in main
    assert 'onclick="sketchup.suite_meye_cutouts()"' in main
    assert main.index('<b>MODEL LIBRARY</b>')<main.index('<b>2D STROMY A KEŘE</b>')<main.index('<b>NASTAVENÍ SKP')
    assert main.index("dlg.add_action_callback('suite_meye_cutouts')")>=0
    result[SUITE_MAIN]=main.encode("utf-8")
    result[SUITE_LOADER]=replace_once(old[SUITE_LOADER].decode("utf-8"),
                                     "2.0.4.6","2.0.4.7",
                                     "RM TOOLS root loader version").encode("utf-8")
    result[TREE_MAIN]=(MEYE/TREE_MAIN).read_bytes()
    result[TREE_UI]=(MEYE/TREE_UI).read_bytes()
    assert b"PNG se st\xc3\xa1hne" in result[TREE_UI]
    assert b"download_full_png" in result[TREE_MAIN]
    # All other members are byte-identical (including origin preview,
    # live mirror, materials, agent, cached Bridge).
    assert set(result)-set(old)=={TREE_MAIN,TREE_UI}
    modified={n for n in old if old[n]!=result[n]}
    assert modified=={SUITE_MAIN,SUITE_LOADER},modified
    assert not any(n.endswith('.png') and n.startswith('twentytwenty_meye_cutouts/') for n in result)
    with ZipFile(OUT,"w",ZIP_DEFLATED) as z:
        for name,raw in sorted(result.items()):
            z.writestr(name,raw)
    assert read(OUT)==result
    for name in sorted(modified|{TREE_MAIN,TREE_UI}):
        dest=SRC/name
        dest.parent.mkdir(parents=True,exist_ok=True)
        dest.write_bytes(result[name])
    print("BUILT:",OUT.name,OUT.stat().st_size,"bytes")
    print("PASS: old RM Tools unchanged except one extra Meye menu and module")
    print("PASS: ZERO bundled Meye PNGs; original assets fetched ONLY on +")

if __name__=="__main__":
    main()
