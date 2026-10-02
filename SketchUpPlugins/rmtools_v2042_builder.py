#!/usr/bin/env python3
"""Narrow ARCH/OKNA tag migration hotfix from the exact released 2.0.4.1.

No import, preview, bridge, mirror, or component library changes.
"""
from pathlib import Path
import zipfile

P=Path(__file__).resolve().parent
SRC=P/"RMToolsSuiteSourceV2042"
OLD=P/"20-20_RM_TOOLS_v2.0.4.1.rbz"
NEW=P/"20-20_RM_TOOLS_v2.0.4.2.rbz"
CHECKER="twentytwenty_rm_checker/main.rb"
CHECKER_LOADER="twentytwenty_rm_checker.rb"
SUITE_LOADER="twentytwenty_rm_tools_suite.rb"
SUITE_MAIN="twentytwenty_rm_tools_suite/main.rb"

def read(path):
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None
        return {n:z.read(n) for n in z.namelist() if not n.endswith("/")}

def write(path, files):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for name,content in sorted(files.items()):
            z.writestr(name,content)
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None

def once(s,a,b):
    assert s.count(a)==1,(a,s.count(a))
    return s.replace(a,b,1)

def main():
    baseline=read(OLD)
    updated=dict(baseline)
    code=(SRC/CHECKER).read_text(encoding="utf-8")
    assert "VERSION = '1.2.4'" in code
    assert "'OKNA' => []" in code
    assert "'OKNA' => %w[RAM SKLO]" not in code
    assert "def migrate_legacy_window_tags" in code
    assert "layers.remove(old_tag, false)" in code
    assert "Průhledný povrch není na tagu OKNA/ZRCADLO" in code
    updated[CHECKER]=code.encode("utf-8")
    updated[CHECKER_LOADER]=once(
        baseline[CHECKER_LOADER].decode("utf-8"),
        "EXTENSION_VERSION = '1.2.3'","EXTENSION_VERSION = '1.2.4'"
    ).encode("utf-8")
    for name in (SUITE_LOADER,SUITE_MAIN):
        source=baseline[name].decode("utf-8")
        assert "2.0.4.1" in source
        updated[name]=source.replace("2.0.4.1","2.0.4.2").encode("utf-8")
    changed={key for key in baseline if baseline[key]!=updated[key]}
    assert changed=={CHECKER,CHECKER_LOADER,SUITE_LOADER,SUITE_MAIN},changed
    for name in changed:
        f=SRC/name
        f.parent.mkdir(parents=True,exist_ok=True)
        f.write_bytes(updated[name])
    write(NEW,updated)
    print(f"BUILT {NEW.name}: {NEW.stat().st_size} bytes")
    print("PASS: no changes to Model Library 0,0,0 preview or any other child module")
    print("CHANGED:",", ".join(sorted(changed)))

if __name__=="__main__":
    main()
