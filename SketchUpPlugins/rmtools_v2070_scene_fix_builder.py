#!/usr/bin/env python3
"""RM TOOLS v2.0.7.0 TEST: one surgical fix for duplicate scene creation."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

P=Path(__file__).resolve().parent
SRC=P/"RMToolsSuiteSourceV2061"
BASE=P/"20-20_RM_TOOLS_v2.0.6.9.rbz"
OUT=P/"20-20_RM_TOOLS_v2.0.7.0.rbz"
assert BASE.is_file() and BASE.stat().st_size == 145657, "v2.0.6.9 STABLE base changed unexpectedly"

PATHS={
    "twentytwenty_rm_tools_suite/main.rb": SRC/"twentytwenty_rm_tools_suite/main.rb",
    "twentytwenty_rm_tools_suite.rb": SRC/"twentytwenty_rm_tools_suite.rb",
    "twentytwenty_rm_managers/main.rb": SRC/"twentytwenty_rm_managers/main.rb",
    "twentytwenty_rm_managers/scene_experience.rb": SRC/"twentytwenty_rm_managers/scene_experience.rb",
    "twentytwenty_rm_managers/scene_ui.js": SRC/"twentytwenty_rm_managers/scene_ui.js",
}

def read(path):
    with ZipFile(path) as z:
        assert z.testzip() is None
        return {n:z.read(n) for n in z.namelist() if not n.endswith("/")}

old=read(BASE)
new=dict(old)
for name,path in PATHS.items():
    new[name]=path.read_bytes()

assert b"VERSION = '2.0.7.0'" in new["twentytwenty_rm_tools_suite/main.rb"]
assert b"EXTENSION_VERSION = '2.0.7.0'" in new["twentytwenty_rm_tools_suite.rb"]
manager=new["twentytwenty_rm_managers/main.rb"]
experience=new["twentytwenty_rm_managers/scene_experience.rb"]
ui=new["twentytwenty_rm_managers/scene_ui.js"]
assert b"select_page_without_transition(model, page)" in manager
assert b"apply_camera_values(view.camera, snapshot)" in manager
assert b"ok = page.update(scene_options)" in manager
assert b"js(:scenes, 'created'" in experience
assert b"Manager.created=function(info)" in ui

changed={n for n in old if old[n] != new[n]}
assert changed == set(PATHS), changed
assert set(old) == set(new)

with ZipFile(OUT,"w",compression=ZIP_DEFLATED,compresslevel=6) as z:
    for name,data in sorted(new.items()):
        z.writestr(name,data)

assert read(OUT)==new
print("PASS: v2.0.7.0 changes only Scene Manager create flow/UI selection + suite version")
print("PASS: v2.0.6.9 is the only base; all other bundled modules stay byte-identical")
print("BUILT:",OUT.name,OUT.stat().st_size)
