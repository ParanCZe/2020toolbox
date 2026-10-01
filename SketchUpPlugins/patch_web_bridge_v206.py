#!/usr/bin/env python3
"""Fix web plugin installation: invoke cached local Bridge FIRST, then download selected RBZ."""
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
INDEX=ROOT/"index.html"
s=INDEX.read_text(encoding="utf-8")
start=s.index("function launchSuBridge(file='')")
end=s.index("function cmpVer(",start)
new_runtime="""let suBridgeActiveUrl=null;
const SU_BRIDGE_PORTS=[SU_BRIDGE_URL,'http://127.0.0.1:8092'];

// This action opens the OS-registered local BAT. It never downloads or builds
// the bridge. It must be called synchronously in a real button click.
function launchSuBridge(){
  const a=document.createElement('a');
  a.href=SU_BRIDGE_SCHEME;
  a.style.display='none';
  document.body.appendChild(a);
  a.click();
  a.remove();
}

async function suBridgeStatus(){
  const endpoints=suBridgeActiveUrl
    ? [suBridgeActiveUrl,...SU_BRIDGE_PORTS.filter(x=>x!==suBridgeActiveUrl)]
    : SU_BRIDGE_PORTS;
  const results=await Promise.all(endpoints.map(async base=>{
    const controller=new AbortController();
    const timeout=setTimeout(()=>controller.abort(),1050);
    try{
      const r=await fetch(base+'/status',{cache:'no-store',signal:controller.signal});
      if(!r.ok)return null;
      const state=await r.json();
      if(!state?.ok||!state.sketchup||!state.installed)return null;
      // Avoid mistaking an unrelated localhost service for SketchUp Bridge.
      if(state.bridge_version && !String(state.bridge_version).startsWith('3.'))return null;
      return {base,state};
    }catch(e){return null}
    finally{clearTimeout(timeout)}
  }));
  const result=results.find(Boolean);
  suBridgeActiveUrl=result?.base||null;
  return result?.state||null;
}

async function ensureSuBridge(alreadyLaunched=false){
  let status=await suBridgeStatus();
  if(status?.ok)return status;
  // In normal web installation launchSuBridge is already called synchronously
  // from the user's click. This fallback is used for explicit refreshes.
  if(!alreadyLaunched)launchSuBridge();
  for(let i=0;i<28;i++){
    await new Promise(resolve=>setTimeout(resolve,350));
    status=await suBridgeStatus();
    if(status?.ok)return status;
  }
  return null;
}
"""
s=s[:start]+new_runtime+s[end:]
begin=s.index("async function refreshSuPluginVersions(){")
finish=s.index("let suToastTimer=null",begin)
new_install="""async function refreshSuPluginVersions(){
  // Status discovery on page load must be passive, not re-launch the BAT.
  const status=await suBridgeStatus();
  if(!status){
    SU_PLUGIN_CATALOG.forEach(plugin=>{
      const el=document.getElementById('suplugin-state-'+plugin.id);
      if(!el)return;
      el.className='suplugin-state none';
      el.textContent='Bridge připraven ke spuštění';
    });
    return false;
  }
  applyInstalledVersions(status.installed||{});
  return true;
}

async function installSuPlugin(id,version){
  // Native-protocol invocation happens directly in the user's click. Starting
  // the BAT from AppData is NOT the same as downloading/installing it again.
  if(!suBridgeActiveUrl)launchSuBridge();
  suPluginToast('Spouštím již nainstalovaný SketchUp Bridge z počítače…');
  const status=await ensureSuBridge(true);
  if(!status){
    suPluginToast('Lokální Bridge neodpovídá na portu 8093 ani 8092. Pokud je nainstalovaná stará verze, jednou aktualizuj pomocník přes tlačítko Instalovat Bridge.',true);
    return;
  }
  const requested=suPluginPayload(id,version);
  if(requested.plugin.loader && status.installed?.[requested.plugin.loader]===version){
    applyInstalledVersions(status.installed);
    suPluginToast(requested.plugin.name+' v'+version+' je už nainstalovaný. Případně restartuj SketchUp.');
    return;
  }
  try{
    // Download ONLY the requested plugin .rbz, never the Bridge installer.
    suPluginToast('Bridge je spuštěný. Stahuji pouze vybraný plugin RBZ…');
    const payload=await suPluginBytes(id,version);
    const endpoint=suBridgeActiveUrl||SU_BRIDGE_URL;
    const response=await fetch(endpoint+'/install?file='+encodeURIComponent(payload.version.file),{
      method:'POST',headers:{'Content-Type':'application/octet-stream'},body:payload.bytes
    });
    const result=await response.json().catch(()=>({}));
    if(!response.ok||!result.ok)throw new Error(result.error||('HTTP '+response.status));
    applyInstalledVersions(result.installed||{});
    suPluginToast(payload.plugin.name+' v'+version+' nainstalován do '+(result.sketchup||'SketchUp')+'. Restartuj SketchUp.');
  }catch(error){
    suPluginToast('Instalace selhala: '+(error?.message||error)+'. Diagnostika: %APPDATA%\\\\2020toolbox\\\\SketchUpPluginInstaller\\\\bridge_v3.log',true);
  }
}

"""
s=s[:begin]+new_install+s[finish:]
assert s.count("function launchSuBridge()")==1
assert s.count("async function installSuPlugin(id,version)")==1
assert "ensureSuBridge(payload.version.file)" not in s
assert "const SU_BRIDGE_URL='http://127.0.0.1:8093';" in s
assert "suPluginToast('Bridge je spuštěný. Stahuji pouze vybraný plugin RBZ…');" in s
assert "const SU_HELPER_INSTALLER_TEXT=" in s
INDEX.write_text(s,encoding="utf-8")
print("PASS: web uses local Bridge first, supports 8093 and legacy 8092, no auto-helper download")
