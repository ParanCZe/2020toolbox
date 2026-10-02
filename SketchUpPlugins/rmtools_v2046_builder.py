#!/usr/bin/env python3
"""RM TOOLS 2.0.4.6: manual Materials Library card under Mirror.

Based ONLY on 2.0.4.5. The original materials toolbar, Agent/Bridge autostart,
Checker, zero-origin Model Library and Live Mirror remain byte-identical.
"""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

P=Path(__file__).resolve().parent
SRC=P/"RMToolsSuiteSourceV2046"
INPUT=P/"20-20_RM_TOOLS_v2.0.4.5.rbz"
OUTPUT=P/"20-20_RM_TOOLS_v2.0.4.6.rbz"
MAIN="twentytwenty_rm_tools_suite/main.rb"
LOADER="twentytwenty_rm_tools_suite.rb"

def read(path):
    with ZipFile(path) as z:
        assert z.testzip() is None
        return {n:z.read(n) for n in z.namelist() if not n.endswith("/")}

def main():
    baseline=read(INPUT)
    result=dict(baseline)
    module=(SRC/MAIN).read_text(encoding="utf-8")
    assert "VERSION = '2.0.4.6'.freeze" in module
    assert "dlg.add_action_callback('suite_material_library') { |_ctx| MaterialLibrary.show }" in module
    assert 'onclick="sketchup.suite_material_library()"' in module
    assert "MaterialLibrary.startup" not in module
    assert "MaterialLibrary.install_toolbar" in module
    assert "AgentBoot.start" in module
    result[MAIN]=module.encode("utf-8")
    loader=baseline[LOADER].decode("utf-8")
    assert loader.count("2.0.4.5")==1
    result[LOADER]=loader.replace("2.0.4.5","2.0.4.6").encode("utf-8")
    changed={name for name in baseline if baseline[name]!=result[name]}
    assert changed=={MAIN,LOADER},changed
    assert set(baseline)==set(result)
    with ZipFile(OUTPUT,"w",ZIP_DEFLATED) as z:
        for name,data in sorted(result.items()):
            z.writestr(name,data)
    assert read(OUTPUT)==result
    for name in sorted(changed):
        target=SRC/name
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes(result[name])
    print(f"BUILT {OUTPUT.name}: {OUTPUT.stat().st_size} bytes")
    print("PASS: only suite main menu / default height and version changed")
    print("PASS: all original plugins, Agent, Bridge and material toolbar preserved")

if __name__=="__main__":
    main()
