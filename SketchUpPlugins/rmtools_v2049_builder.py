#!/usr/bin/env python3
"""Build RM TOOLS 2.0.4.9 from 2.0.4.8, modifying only Meye module and suite version."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
P=Path(__file__).resolve().parent
BASE=P/"20-20_RM_TOOLS_v2.0.4.8.rbz"
OUTPUT=P/"20-20_RM_TOOLS_v2.0.4.9.rbz"
SOURCE=P/"MeyeCutoutsSourceV012/twentytwenty_meye_cutouts/main.rb"
MEYE="twentytwenty_meye_cutouts/main.rb"
MAIN="twentytwenty_rm_tools_suite/main.rb"
LOADER="twentytwenty_rm_tools_suite.rb"
with ZipFile(BASE) as z:
    assert z.testzip() is None
    files={n:z.read(n) for n in z.namelist() if not n.endswith("/")}
original=dict(files)
files[MEYE]=SOURCE.read_bytes()
assert b"VERSION = '0.1.2'" in files[MEYE]
assert b"PAGE_SIZE = 8" in files[MEYE]
assert b"install_green_placement_observer(model)" in files[MEYE]
for name in (MAIN,LOADER):
    assert files[name].count(b"2.0.4.8")==1,(name,files[name].count(b"2.0.4.8"))
    files[name]=files[name].replace(b"2.0.4.8",b"2.0.4.9")
changed={name for name in original if files[name]!=original[name]}
assert changed=={MEYE,MAIN,LOADER},changed
with ZipFile(OUTPUT,"w",ZIP_DEFLATED) as z:
    for name,data in sorted(files.items()):
        z.writestr(name,data)
with ZipFile(OUTPUT) as z:
    assert z.testzip() is None
    assert z.read(MEYE)==files[MEYE]
    assert not any(n.startswith("twentytwenty_meye_cutouts/") and n.lower().endswith(".png") for n in z.namelist())
print("PASS: preserved Model Library, Checker, Bridge, UI, and all other assets")
print("PASS: RM ZELEN placement hook and smaller initial Meye batch; no bundled PNG")
print("BUILT:",OUTPUT.name,OUTPUT.stat().st_size)

# Release build trigger: generate the installable RBZ in the repository.
