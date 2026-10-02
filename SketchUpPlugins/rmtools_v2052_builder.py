#!/usr/bin/env python3
"""Safely release v2.0.5.2 from the existing v2.0.4.9 RBZ, preserving all other plugins."""
from pathlib import Path
from zipfile import ZipFile,ZIP_DEFLATED
P=Path(__file__).resolve().parent
source=P/"RMToolsSuiteSourceV2052"
base=P/"20-20_RM_TOOLS_v2.0.5.1.rbz"
output=P/"20-20_RM_TOOLS_v2.0.5.2.rbz"
paths={
"twentytwenty_rm_tools_suite/main.rb":source/"twentytwenty_rm_tools_suite/main.rb",
"twentytwenty_rm_tools_suite.rb":source/"twentytwenty_rm_tools_suite.rb",
"twentytwenty_rm_managers/main.rb":source/"twentytwenty_rm_managers/main.rb",
"twentytwenty_rm_tools_suite/camera_consistency.rb":source/"twentytwenty_rm_tools_suite/camera_consistency.rb"
}
assert base.is_file(),"Released base RBZ missing"
with ZipFile(base) as f:
    assert f.testzip() is None
    old={n:f.read(n) for n in f.namelist() if not n.endswith("/")}
new=dict(old)
for name,path in paths.items(): new[name]=path.read_bytes()
assert b"VERSION = '2.0.5.2'" in new["twentytwenty_rm_tools_suite/main.rb"]
assert b"EXTENSION_VERSION = '2.0.5.2'" in new["twentytwenty_rm_tools_suite.rb"]
assert b"VERSION = '0.1.2'" in new["twentytwenty_rm_managers/main.rb"]
assert set(old).issubset(set(new))
assert {x for x in old if old[x]!=new[x]}==set(paths) & set(old)
with ZipFile(output,"w",compression=ZIP_DEFLATED,compresslevel=6) as f:
    for name,data in sorted(new.items()): f.writestr(name,data)
with ZipFile(output) as f:
    assert f.testzip() is None
    assert {n:f.read(n) for n in f.namelist()}==new
print("PASS: rebuilt RBZ preserves Model Library, RM Checker, Meye, Mirror, Agent & Bridge")
print("PASS: new Tag Manager and Scene Manager bundled")
print("BUILT:",output.name,output.stat().st_size)
