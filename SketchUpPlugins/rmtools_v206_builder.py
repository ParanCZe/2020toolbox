#!/usr/bin/env python3
"""Build Model Library 0.3.4 / RM TOOLS 2.0.6: direct multi-root placement."""
from pathlib import Path
import zipfile

P=Path(__file__).resolve().parent
SRC=P/"ComponentLibrarySourceV034"
OUT=P/"RMToolsSuiteSourceV206"

def read(file):
    with zipfile.ZipFile(file) as z:
        assert z.testzip() is None
        return {x:z.read(x) for x in z.namelist() if not x.endswith("/")}

def write(file,items):
    with zipfile.ZipFile(file,"w",zipfile.ZIP_DEFLATED) as z:
        for key,val in sorted(items.items()):
            z.writestr(key,val)
    with zipfile.ZipFile(file) as z:assert z.testzip() is None

def replace_once(text,old,new):
    assert text.count(old)==1,(old,text.count(old))
    return text.replace(old,new,1)

def suppress_child_ui(text):
    start=text.rfind("    unless file_loaded?(__FILE__)\n      command = UI::Command.new(")
    end=text.rfind("\n  end\nend")
    assert start>=0 and end>start
    return text[:start]+"    file_loaded(__FILE__) unless file_loaded?(__FILE__)\n"+text[end:]

def main():
    root="dvacet20_component_library/"
    source_main=(SRC/root/"main.rb").read_text(encoding="utf-8")
    assert "VERSION = '0.3.4'" in source_main
    assert "class DirectMultiPlacementTool" in source_main
    assert "active_entities.add_instance" in source_main
    assert "model.place_component(loaded_definition" not in source_main
    solo=read(P/"20-20_Component_Library_v0.3.3.rbz")
    solo.update({
        root+"main.rb":source_main.encode(),
        root+"ui/library.html":(SRC/root/"ui/library.html").read_bytes(),
        "dvacet20_component_library.rb":(SRC/"dvacet20_component_library.rb").read_bytes()
    })
    solo_out=P/"20-20_Component_Library_v0.3.4.rbz"
    write(solo_out,solo)

    suite_old=read(P/"20-20_RM_TOOLS_v2.0.5.rbz")
    suite=dict(suite_old)
    suite[root+"main.rb"]=suppress_child_ui(source_main).encode()
    suite[root+"ui/library.html"]=solo[root+"ui/library.html"]
    suite["dvacet20_component_library.rb"]=replace_once(
        suite["dvacet20_component_library.rb"].decode(),
        "EXTENSION_VERSION = '0.3.3'","EXTENSION_VERSION = '0.3.4'").encode()
    for name in ("twentytwenty_rm_tools_suite.rb","twentytwenty_rm_tools_suite/main.rb"):
        code=suite[name].decode()
        assert "2.0.5" in code
        suite[name]=code.replace("2.0.5","2.0.6").encode()
    for name in ("twentytwenty_rm_checker/main.rb",
                 "twentytwenty_rm_checker.rb",
                 "twentytwenty_live_mirror/main_v0418.rb",
                 "twentytwenty_live_mirror/renderer_v0418.html"):
        assert suite[name]==suite_old[name],name
    assert "UI::Command.new('20-20 Knihovna komponent')" not in suite[root+"main.rb"].decode()
    suite_out=P/"20-20_RM_TOOLS_v2.0.6.rbz"
    write(suite_out,suite)
    for name in (root+"main.rb",root+"ui/library.html","twentytwenty_rm_tools_suite.rb","twentytwenty_rm_tools_suite/main.rb"):
        path=OUT/name
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(suite[name])
    print("Built",solo_out.name,solo_out.stat().st_size)
    print("Built",suite_out.name,suite_out.stat().st_size)
    print("Preserved existing tag migration and mirror modules")

if __name__=="__main__":main()
