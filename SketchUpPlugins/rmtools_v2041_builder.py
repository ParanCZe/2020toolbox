#!/usr/bin/env python3
"""Build a narrow zero-origin preview hotfix from EXACTLY released RM TOOLS 2.0.4.

No source from versions 2.0.5/2.0.6 may be used. Other modules remain byte-identical.
"""
from pathlib import Path
import zipfile

P=Path(__file__).resolve().parent
SOURCE=P/"RMToolsSuiteSourceV2041"
BASE=P/"20-20_RM_TOOLS_v2.0.4.rbz"
OUT=P/"20-20_RM_TOOLS_v2.0.4.1.rbz"
LIB="dvacet20_component_library/main.rb"
UI="dvacet20_component_library/ui/library.html"
LOADER="dvacet20_component_library.rb"
SUITE_LOADER="twentytwenty_rm_tools_suite.rb"
SUITE_MAIN="twentytwenty_rm_tools_suite/main.rb"

def read(path):
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None
        return {name:z.read(name) for name in z.namelist() if not name.endswith("/")}

def write(path,entries):
    with zipfile.ZipFile(path,"w",zipfile.ZIP_DEFLATED) as z:
        for name,body in sorted(entries.items()):
            z.writestr(name,body)
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None

def exactly_once(source,old,new):
    assert source.count(old)==1,(old[:80],source.count(old))
    return source.replace(old,new,1)

def main():
    old=read(BASE)
    output=dict(old)
    source=(SOURCE/LIB).read_text(encoding="utf-8")
    assert "VERSION = '0.3.2.1'" in source
    assert "class PlacementOriginPreviewObserver" in source
    assert "entity.definition = @target_definition" in source
    assert "entity.transformation = final_transform" in source
    assert "model.place_component(loaded_definition, false)" in source
    assert "model.place_component(target_definition, false)" not in source
    assert "class DirectMultiPlacementTool" not in source
    output[LIB]=source.encode("utf-8")
    html=old[UI].decode("utf-8")
    html=exactly_once(
      html,
      "Vkládáš přímo původní komponentu, bez dalšího obalu.",
      "Bod vložení je nula (0,0,0) zdrojového SKP. Model už při tažení drží správnou pozici."
    )
    output[UI]=html.encode("utf-8")
    loaded=old[LOADER].decode("utf-8")
    output[LOADER]=exactly_once(loaded,"EXTENSION_VERSION = '0.3.2'",
                               "EXTENSION_VERSION = '0.3.2.1'").encode("utf-8")
    for name in (SUITE_LOADER,SUITE_MAIN):
        data=old[name].decode("utf-8")
        assert "2.0.4" in data,name
        output[name]=data.replace("2.0.4","2.0.4.1").encode("utf-8")
    # Absolutely no tag/tree/UI/feature changes outside insertion preview.
    changed={name for name in old if old[name]!=output[name]}
    allowed={LIB,UI,LOADER,SUITE_LOADER,SUITE_MAIN}
    assert changed==allowed,(changed,allowed)
    assert "file_loaded(__FILE__) unless file_loaded?(__FILE__)" in source
    write(OUT,output)
    for name in sorted(allowed):
        target=SOURCE/name
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes(output[name])
    print("BUILT",OUT.name,OUT.stat().st_size)
    print("CHANGED ONLY",", ".join(sorted(changed)))
    print("PASS: original 2.0.4 module set otherwise byte-identical")

if __name__=="__main__":
    main()
