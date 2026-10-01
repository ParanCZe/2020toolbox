#!/usr/bin/env python3
"""Build Component Library v0.3.3 and RM TOOLS v2.0.5 (never place SKP file wrappers)."""
from pathlib import Path
import zipfile

P = Path(__file__).resolve().parent
SRC = P / "ComponentLibrarySourceV033"
SNAPSHOT = P / "RMToolsSuiteSourceV205"

def read(path):
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None, path
        return {n:z.read(n) for n in z.namelist() if not n.endswith("/")}

def write(path,files):
    with zipfile.ZipFile(path,"w",zipfile.ZIP_DEFLATED) as z:
        for n,v in sorted(files.items()):
            z.writestr(n,v)
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None,path

def swap(s,old,new):
    assert s.count(old)==1,(old,s.count(old))
    return s.replace(old,new,1)

def bundled_no_auto_ui(src):
    marker="    unless file_loaded?(__FILE__)\n      command = UI::Command.new("
    start=src.rfind(marker)
    end=src.rfind("\n  end\nend")
    assert start>=0 and end>start
    return src[:start]+"    file_loaded(__FILE__) unless file_loaded?(__FILE__)\n"+src[end:]

def main():
    old_solo=read(P/"20-20_Component_Library_v0.3.2.rbz")
    old_suite=read(P/"20-20_RM_TOOLS_v2.0.4.rbz")
    main_file=SRC/"dvacet20_component_library/main.rb"
    ui_file=SRC/"dvacet20_component_library/ui/library.html"
    loader_file=SRC/"dvacet20_component_library.rb"
    main_rb=main_file.read_text(encoding="utf-8")
    assert "VERSION = '0.3.3'" in main_rb
    assert "model.place_component(target_definition, false)" in main_rb
    assert "model.place_component(loaded_definition" not in main_rb
    assert "Další obalovou komponentu knihovna nikdy nevytvoří" in main_rb
    solo=dict(old_solo)
    solo["dvacet20_component_library/main.rb"]=main_rb.encode("utf-8")
    solo["dvacet20_component_library.rb"]=loader_file.read_bytes()
    solo["dvacet20_component_library/ui/library.html"]=ui_file.read_bytes()
    solo_out=P/"20-20_Component_Library_v0.3.3.rbz"
    write(solo_out,solo)

    suite=dict(old_suite)
    suite["dvacet20_component_library/main.rb"]=bundled_no_auto_ui(main_rb).encode("utf-8")
    suite["dvacet20_component_library/ui/library.html"]=ui_file.read_bytes()
    loader=suite["dvacet20_component_library.rb"].decode("utf-8")
    suite["dvacet20_component_library.rb"]=swap(loader,"EXTENSION_VERSION = '0.3.2'","EXTENSION_VERSION = '0.3.3'").encode("utf-8")
    for n in ("twentytwenty_rm_tools_suite.rb","twentytwenty_rm_tools_suite/main.rb"):
        code=suite[n].decode("utf-8")
        assert "2.0.4" in code
        suite[n]=code.replace("2.0.4","2.0.5").encode("utf-8")
    suite_out=P/"20-20_RM_TOOLS_v2.0.5.rbz"
    write(suite_out,suite)

    for name in ("twentytwenty_rm_checker/main.rb",
                 "twentytwenty_rm_checker.rb",
                 "twentytwenty_live_mirror/main_v0418.rb",
                 "twentytwenty_live_mirror/renderer_v0418.html"):
        assert old_suite[name]==suite[name],name
    for name in ("dvacet20_component_library/main.rb",
                 "dvacet20_component_library/ui/library.html",
                 "twentytwenty_rm_tools_suite.rb",
                 "twentytwenty_rm_tools_suite/main.rb"):
        destination=SNAPSHOT/name
        destination.parent.mkdir(parents=True,exist_ok=True)
        destination.write_bytes(suite[name])
    print("Built",solo_out.name,solo_out.stat().st_size)
    print("Built",suite_out.name,suite_out.stat().st_size)
    print("Unchanged Checker, RM tags, mirror, and only one suite toolbar")

if __name__=="__main__":
    main()
