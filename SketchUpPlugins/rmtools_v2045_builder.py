#!/usr/bin/env python3
"""RM TOOLS 2.0.4.5: original Materials Library icon + startup panel.

Based only on the verified 2.0.4.4 release. Original zero-origin component
placement, RM tag checker, Live Mirror and both Bridges stay byte-identical.
"""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

P=Path(__file__).resolve().parent
SRC=P/"RMToolsSuiteSourceV2045"
PREVIOUS=P/"20-20_RM_TOOLS_v2.0.4.4.rbz"
OUTPUT=P/"20-20_RM_TOOLS_v2.0.4.5.rbz"
AI_TOOLS=P/"20-20_AI-TOOLS_v0.4.2.rbz"
SUITE="twentytwenty_rm_tools_suite/"
MODULE=SUITE+"material_library.rb"
MAIN=SUITE+"main.rb"
LOADER="twentytwenty_rm_tools_suite.rb"
ICON24=SUITE+"icons/material_library_24.png"
ICON32=SUITE+"icons/material_library_32.png"

def read(path):
    with ZipFile(path) as z:
        assert z.testzip() is None,path
        return {n:z.read(n) for n in z.namelist() if not n.endswith("/")}

def once(s,a,b,name):
    assert s.count(a)==1,(name,s.count(a))
    return s.replace(a,b,1)

def main():
    original=read(PREVIOUS)
    ai=read(AI_TOOLS)
    output=dict(original)
    material=(SRC/MODULE).read_text(encoding="utf-8")
    assert "URL = 'http://127.0.0.1:8787/knihovna?cad=sketchup'" in material
    assert "UI::Toolbar.new(TOOLBAR_TITLE)" in material
    assert "Dvacet20::Most.zobraz_listu" in material
    assert "Dvacet20::Most.panel_knihovny" in material
    assert "MAX_STARTUP_ATTEMPTS = 20" in material
    output[MODULE]=material.encode("utf-8")

    icon_mapping={
      ICON24:"dvacet20-ai-tools/ikony/knihovna-24.png",
      ICON32:"dvacet20-ai-tools/ikony/knihovna-32.png"
    }
    for target,source in icon_mapping.items():
        icon=ai[source]
        assert icon[:8]==b"\x89PNG\r\n\x1a\n",source
        output[target]=icon

    main=original[MAIN].decode("utf-8")
    main=once(main,"VERSION = '2.0.4.4'.freeze",
              "VERSION = '2.0.4.5'.freeze","suite version")
    main=once(main,"require File.join(__dir__, 'agent_autostart')",
              "require File.join(__dir__, 'agent_autostart')\n" \
              "require File.join(__dir__, 'material_library')",
              "library require")
    main=once(main,
              "        AgentBoot.start\n        show\n",
              """        AgentBoot.start
        show
        # Start the identical material-library page after the local Agent is up.
        MaterialLibrary.startup
        # Give any existing AI-TOOLS/most.rb toolbar time to initialize first:
        # if already present, reuse its original left icon. Otherwise expose
        # our own one-icon native SketchUp toolbar (manually dockable left).
        UI.start_timer(2.0, false) { MaterialLibrary.install_toolbar }
""","SketchUp startup callback")
    output[MAIN]=main.encode("utf-8")
    output[LOADER]=once(original[LOADER].decode("utf-8"),
                        "2.0.4.4","2.0.4.5","loader version").encode("utf-8")
    assert set(output)-set(original)=={MODULE,ICON24,ICON32}
    changed={x for x in original if original[x]!=output[x]}
    assert changed=={MAIN,LOADER},changed
    with ZipFile(OUTPUT,"w",ZIP_DEFLATED) as z:
        for path,data in sorted(output.items()):
            z.writestr(path,data)
    assert read(OUTPUT)==output

    for name in changed | {MODULE,ICON24,ICON32}:
        dest=SRC/name
        dest.parent.mkdir(parents=True,exist_ok=True)
        dest.write_bytes(output[name])
    print("BUILT",OUTPUT.name,OUTPUT.stat().st_size,"bytes")
    print("UNCHANGED:",len(set(original)-changed),"previous components and original local agent")
    print("ADDED: original AI-TOOLS material icons and left-dockable startup library")

if __name__=="__main__":
    main()
