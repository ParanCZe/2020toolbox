#!/usr/bin/env python3
"""Build RM TOOLS v2.0.6.10 camera-safety and cache optimizations."""
from pathlib import Path
from zipfile import ZipFile,ZIP_DEFLATED
P=Path(__file__).resolve().parent
source=P/"RMToolsSuiteSourceV2061"
base=P/"20-20_RM_TOOLS_v2.0.6.9.rbz"
output=P/"20-20_RM_TOOLS_v2.0.6.10.rbz"
paths={
"twentytwenty_rm_tools_suite/main.rb":source/"twentytwenty_rm_tools_suite/main.rb",
"twentytwenty_rm_tools_suite.rb":source/"twentytwenty_rm_tools_suite.rb",
"twentytwenty_rm_managers/main.rb":source/"twentytwenty_rm_managers/main.rb",
"twentytwenty_rm_tools_suite/camera_consistency.rb":source/"twentytwenty_rm_tools_suite/camera_consistency.rb",
"twentytwenty_rm_managers/scene_experience.rb":source/"twentytwenty_rm_managers/scene_experience.rb",
"twentytwenty_rm_managers/scene_visuals.rb":source/"twentytwenty_rm_managers/scene_visuals.rb",
"twentytwenty_rm_managers/scene_ui.js":source/"twentytwenty_rm_managers/scene_ui.js",
"twentytwenty_rm_managers/scene_ui.css":source/"twentytwenty_rm_managers/scene_ui.css",
"twentytwenty_rm_managers/floorplan.rb":source/"twentytwenty_rm_managers/floorplan.rb",
"dvacet20_component_library/main.rb":P/"RMToolsSuiteSourceV206/dvacet20_component_library/main.rb",
"twentytwenty_rm_checker/main.rb":P/"RMToolsSuiteSourceV2042/twentytwenty_rm_checker/main.rb",
"twentytwenty_meye_cutouts/main.rb":P/"RMToolsSuiteSourceV2048/twentytwenty_meye_cutouts/main.rb",
"twentytwenty_live_mirror/main_v0418.rb":P/"LiveMirrorSource/twentytwenty_live_mirror/main_v0418.rb"
}
assert base.is_file(),"Released base RBZ missing"
with ZipFile(base) as f:
    assert f.testzip() is None
    old={n:f.read(n) for n in f.namelist() if not n.endswith("/")}
new=dict(old)
new.pop("twentytwenty_rm_managers/street_view.rb",None)
for name,path in paths.items(): new[name]=path.read_bytes()
new["twentytwenty_rm_tools_suite/main.rb"]=new["twentytwenty_rm_tools_suite/main.rb"].replace(b"VERSION = '2.0.6.1'",b"VERSION = '2.0.6.10'")
new["twentytwenty_rm_tools_suite.rb"]=new["twentytwenty_rm_tools_suite.rb"].replace(b"EXTENSION_VERSION = '2.0.6.1'",b"EXTENSION_VERSION = '2.0.6.10'")
assert b"VERSION = '2.0.6.10'" in new["twentytwenty_rm_tools_suite/main.rb"]
assert b"EXTENSION_VERSION = '2.0.6.10'" in new["twentytwenty_rm_tools_suite.rb"]
assert b"VERSION = '0.2.1'" in new["twentytwenty_rm_managers/main.rb"]
assert set(old)-{"twentytwenty_rm_managers/street_view.rb"} <= set(new)
allowed = set(paths)
changed = {x for x in old if x in new and old[x]!=new[x]}
assert changed <= allowed
assert {"twentytwenty_rm_tools_suite/main.rb", "twentytwenty_rm_tools_suite.rb"} <= changed
assert b"view.camera = page.camera" not in new["twentytwenty_rm_managers/scene_experience.rb"]
assert b"active.set(eye, target, active.up)" in new["twentytwenty_rm_managers/scene_experience.rb"]
assert b"PREVIEW_CACHE_LIMIT = 80" in new["twentytwenty_rm_managers/scene_visuals.rb"]
assert b"CACHE_LIMIT = 4" in new["twentytwenty_rm_managers/floorplan.rb"]
assert b"assigning it back can" in new["twentytwenty_rm_checker/main.rb"]
assert "twentytwenty_live_mirror/main_v0418.rb" in new
assert b"count_cache = {}" in new["twentytwenty_live_mirror/main_v0418.rb"]
assert b"working_record[:edge_color] = reflection_edge_color" in new["twentytwenty_live_mirror/main_v0418.rb"]
assert "twentytwenty_rm_managers/street_view.rb" not in new
with ZipFile(output,"w",compression=ZIP_DEFLATED,compresslevel=6) as f:
    for name,data in sorted(new.items()): f.writestr(name,data)
with ZipFile(output) as f:
    assert f.testzip() is None
    assert {n:f.read(n) for n in f.namelist()}==new
print("PASS: rebuilt RBZ preserves Model Library, RM Checker, Meye, Mirror, Agent & Bridge")
print("PASS: new Tag Manager and Scene Manager bundled")
print("BUILT:",output.name,output.stat().st_size)
