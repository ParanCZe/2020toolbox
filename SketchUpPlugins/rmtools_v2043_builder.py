#!/usr/bin/env python3
"""RM TOOLS 2.0.4.3: integrate Agent Launcher 0.1.2 invisibly at SketchUp startup.

Builds exclusively on the 2.0.4.2 RBZ. Does not change Checker, Model Library,
the native 0,0,0 insertion preview, Live Mirror or existing toolbar styling.
Includes a fully offline copy of the web Bridge and a session-persistent variant.
"""
from pathlib import Path
import zipfile

P=Path(__file__).resolve().parent
ROOT=P.parent
INPUT=P/"20-20_RM_TOOLS_v2.0.4.2.rbz"
OUTPUT=P/"20-20_RM_TOOLS_v2.0.4.3.rbz"
SOURCE=P/"RMToolsSuiteSourceV2043"
SUITE="twentytwenty_rm_tools_suite/"
MAIN=SUITE+"main.rb"
LOADER="twentytwenty_rm_tools_suite.rb"
AUTOSTART=SUITE+"agent_autostart.rb"
BRIDGE=SUITE+"windows_bridge/"

def one(source,old,new,label):
    assert source.count(old)==1,f"{label}: count={source.count(old)}"
    return source.replace(old,new,1)

def zipfiles(path):
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None,path
        return {name:z.read(name) for name in z.namelist() if not name.endswith("/")}

def build_persistent_ps(source):
    source=one(source,
        "param([string]$ProtocolUrl='')",
        "param([string]$ProtocolUrl='', [switch]$SketchUpSession)",
        "PowerShell startup parameters")
    source=one(source,
        "$expires=[DateTime]::UtcNow.AddMinutes(2);Log ('BRIDGE START '+$ProtocolUrl)",
        "$expires=[DateTime]::UtcNow.AddMinutes(2);$nextProcessCheck=[DateTime]::UtcNow;"\
        "Log ('BRIDGE START '+$ProtocolUrl+' Session='+$SketchUpSession)",
        "Bridge startup")
    source=one(source,
        "while([DateTime]::UtcNow -lt $expires){",
        """while($SketchUpSession -or [DateTime]::UtcNow -lt $expires){
 if($SketchUpSession -and [DateTime]::UtcNow -ge $nextProcessCheck){
  if(-not (Get-Process -Name 'SketchUp' -ErrorAction SilentlyContinue)){break}
  $nextProcessCheck=[DateTime]::UtcNow.AddSeconds(10)
 }""",
        "Persistent Bridge loop")
    source=one(source,
        "$left=[Math]::Max(0,[int][Math]::Ceiling(($expires-[DateTime]::UtcNow).TotalSeconds));",
        "$left=if($SketchUpSession){86400}else{[Math]::Max(0,[int][Math]::Ceiling(($expires-[DateTime]::UtcNow).TotalSeconds))};",
        "Session status response")
    assert source.count("Register-HiddenProtocol")>=2
    assert "$port=8093" in source
    return source

def main():
    baseline=zipfiles(INPUT)
    out=dict(baseline)

    agent=(SOURCE/AUTOSTART).read_text(encoding="utf-8")
    assert "PREF_SECTION = '20-20 Agent Launcher'" in agent
    assert "DEFAULT_ADAPTER = 'C:/2020agent/dist/adapter-agent.exe'" in agent
    assert "DEFAULT_SCRIPT = 'C:/2020agent/dist/sketchup/most.rb'" in agent
    assert "WScript.Shell" in agent and "sh.Run WScript.Arguments(0), 0, False" in agent
    assert "def web_bridge_online?" in agent
    assert "UI.start_timer(CHECK_INTERVAL, true)" in agent
    assert not agent.endswith("AgentLauncher.init")
    out[AUTOSTART]=agent.encode("utf-8")

    entry=baseline[MAIN].decode("utf-8")
    entry=one(entry,"VERSION = '2.0.4.2'.freeze","VERSION = '2.0.4.3'.freeze","main suite version")
    entry=one(entry,"require 'json'","require 'json'\nrequire File.join(__dir__, 'agent_autostart')","load integrated agent")
    entry=one(entry,
        "    unless file_loaded?(__FILE__)\n      install_ui\n      file_loaded(__FILE__)\n    end",
        """    unless file_loaded?(__FILE__)
      install_ui
      AgentBoot.install_settings_menu if AgentBoot.windows?
      # The main RM TOOLS window opens normally; ONLY Agent + Bridges run
      # invisibly in the background, with no extra toolbar or chooser popup.
      UI.start_timer(1.5, false) do
        AgentBoot.start
        show
      end
      file_loaded(__FILE__)
    end""",
        "SketchUp startup hook")
    out[MAIN]=entry.encode("utf-8")

    loader=baseline[LOADER].decode("utf-8")
    out[LOADER]=one(loader,"2.0.4.2","2.0.4.3","extension version").encode("utf-8")
    windows=ROOT/"SketchUpPluginInstaller"
    for name in ("bridge_v3.ps1","20-20_BRIDGE_V3.bat","register_protocol_v3.ps1"):
        raw=(windows/name).read_bytes()
        out[BRIDGE+name]=raw
    ps=(windows/"bridge_v3.ps1").read_text(encoding="utf-8")
    out[BRIDGE+"bridge_session.ps1"]=build_persistent_ps(ps).encode("utf-8")

    # Ensure all other v2.0.4.2 members remain exactly unchanged.
    changed={name for name in baseline if out[name]!=baseline[name]}
    assert changed=={MAIN,LOADER},changed
    added=set(out)-set(baseline)
    assert added=={
        AUTOSTART,
        BRIDGE+"bridge_v3.ps1",
        BRIDGE+"20-20_BRIDGE_V3.bat",
        BRIDGE+"register_protocol_v3.ps1",
        BRIDGE+"bridge_session.ps1"
    },added
    assert all(out[n]==baseline[n] for n in baseline if n not in changed)
    with zipfile.ZipFile(OUTPUT,"w",compression=zipfile.ZIP_DEFLATED) as z:
        for name,data in sorted(out.items()):
            z.writestr(name,data)
    assert zipfiles(OUTPUT)==out
    for name in sorted(changed|added):
        target=SOURCE/name
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes(out[name])
    print("BUILT:",OUTPUT.name,"bytes:",OUTPUT.stat().st_size)
    print("CHANGED:",sorted(changed))
    print("NEW:",sorted(added))
    print("PASS: Model Library, zero-origin preview, Checker and Live Mirror remain byte-identical")

if __name__=="__main__":
    main()
