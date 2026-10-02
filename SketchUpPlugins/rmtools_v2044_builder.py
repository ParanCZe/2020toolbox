#!/usr/bin/env python3
"""RM TOOLS 2.0.4.4: repair only the hidden VBS startup in 2.0.4.3."""
from pathlib import Path
import zipfile

P=Path(__file__).resolve().parent
SRC=P/"RMToolsSuiteSourceV2044"
PREVIOUS=P/"20-20_RM_TOOLS_v2.0.4.3.rbz"
OUTPUT=P/"20-20_RM_TOOLS_v2.0.4.4.rbz"
AGENT="twentytwenty_rm_tools_suite/agent_autostart.rb"
MAIN="twentytwenty_rm_tools_suite/main.rb"
LOADER="twentytwenty_rm_tools_suite.rb"

def files(path):
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None
        return {n:z.read(n) for n in z.namelist() if not n.endswith("/")}

def replace_one(s,a,b):
    assert s.count(a)==1,(a,s.count(a))
    return s.replace(a,b,1)

def main():
    base=files(PREVIOUS)
    output=dict(base)
    agent=(SRC/AGENT).read_text(encoding="utf-8")
    assert 'sh.Run #{vbs_literal(command)}, 0, False' in agent
    assert 'sh.Run WScript.Arguments(0)' not in agent
    assert "Process.spawn(wscript, '//B', '//Nologo'" in agent
    assert "data = \"\\xFF\\xFE\".b + contents.encode('UTF-16LE').b" in agent
    assert "def powershell_command(script, extra = '')" in agent
    output[AGENT]=agent.encode("utf-8")
    output[MAIN]=replace_one(base[MAIN].decode("utf-8"),"2.0.4.3","2.0.4.4").encode("utf-8")
    output[LOADER]=replace_one(base[LOADER].decode("utf-8"),"2.0.4.3","2.0.4.4").encode("utf-8")
    changed={n for n in base if base[n]!=output[n]}
    assert changed=={AGENT,MAIN,LOADER},changed
    assert set(base)==set(output)
    with zipfile.ZipFile(OUTPUT,"w",zipfile.ZIP_DEFLATED) as z:
        for name,data in sorted(output.items()): z.writestr(name,data)
    assert files(OUTPUT)==output
    for name in sorted(changed):
        path=SRC/name
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(output[name])
    print("BUILT:",OUTPUT.name,OUTPUT.stat().st_size,"bytes")
    print("PASS: only hidden agent launcher and suite versions changed")
    print("PASS: original SKP 0,0,0 placement, Checker, Mirror and embedded Bridge are unchanged")

if __name__=="__main__":
    main()
