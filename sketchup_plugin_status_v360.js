(() => {
  const KEY='2020toolbox.sketchupPluginDownloads.v1';
  const UA=(navigator.userAgent||'')+' '+(navigator.platform||'');
  const IS_MAC=/Macintosh|Mac OS X|MacIntel/i.test(UA);
  const IS_WIN=/Windows|Win32|Win64/i.test(UA);
  const MAC_CONNECTOR_URL='https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/SketchUpPluginInstaller/20-20_Toolbox_Mac_Connector_v1.1.0.rbz';
  const WINDOWS_BRIDGE_BAT_URL='https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/SketchUpPluginInstaller/20-20_BRIDGE_V3.bat';
  const BRIDGE_URL=IS_WIN?'http://127.0.0.1:8093':'http://127.0.0.1:8092';
  const loaderFixes={'ai-exporter':'twentytwenty_nano_banana_exporter.rb'};
  try{SU_PLUGIN_CATALOG.forEach(p=>{if(!p.loader&&loaderFixes[p.id])p.loader=loaderFixes[p.id]})}catch(_){}

  function readDownloads(){try{return JSON.parse(localStorage.getItem(KEY)||'{}')||{}}catch(_){return {}}}
  function markDownloaded(id,version){const x=readDownloads();x[id]={version:String(version||''),at:Date.now()};try{localStorage.setItem(KEY,JSON.stringify(x))}catch(_){}}
  function downloadedVersion(id){const x=readDownloads()[id];return x&&x.version?String(x.version):null}
  function stateEl(id){return document.getElementById('suplugin-state-'+id)}
  function setUnknown(){try{SU_PLUGIN_CATALOG.forEach(p=>{const el=stateEl(p.id);if(el){el.className='suplugin-state none';el.textContent=IS_WIN?'Bridge vypnutý':'stav nezjištěn'}})}catch(_){}}

  const style=document.createElement('style');
  style.textContent='.suplugin-state.downloaded{background:#eef2ff!important;border-color:#c7d2fe!important;color:#3730a3!important}.suplugin-uninstall{background:#fff!important;color:#991b1b!important;border:1px solid #fecaca!important}.suplugin-uninstall:hover{background:#fef2f2!important}';
  document.head.appendChild(style);

  window.applyInstalledVersions=function(installed){
    try{SU_PLUGIN_CATALOG.forEach(p=>{
      const el=stateEl(p.id);if(!el)return;
      const v=p.loader&&installed?installed[p.loader]:null;
      const downloaded=downloadedVersion(p.id);
      if(v){
        if(v==='?'){el.className='suplugin-state ok';el.textContent='nainstalováno · verze ?';return}
        if(cmpVer(v,p.current)<0){el.className='suplugin-state update';el.textContent='v'+v+' · nová verze'}
        else{el.className='suplugin-state ok';el.textContent='v'+v+' · nainstalováno'}
        return;
      }
      if(downloaded){el.className='suplugin-state downloaded';el.textContent='v'+downloaded+' · staženo';return}
      el.className='suplugin-state none';el.textContent='nenainstalováno';
    })}catch(e){console.error(e)}
  };

  async function bridgeStatus(){
    try{
      const c=new AbortController(),t=setTimeout(()=>c.abort(),1000);
      const r=await fetch(BRIDGE_URL+'/status',{cache:'no-store',signal:c.signal});
      clearTimeout(t);
      if(!r.ok)return null;
      const data=await r.json();
      return data&&data.ok?data:null;
    }catch(_){return null}
  }
  window.suBridgeStatus=bridgeStatus;

  async function downloadWindowsBridgeFile(startPolling=true){
    try{
      const r=await fetch(WINDOWS_BRIDGE_BAT_URL,{cache:'no-store'});
      if(!r.ok)throw new Error('HTTP '+r.status);
      const text=await r.text();
      if(!text||text.toLowerCase().indexOf('@echo off')<0)throw new Error('Neplatný BAT soubor');
      const blob=new Blob([text],{type:'application/octet-stream'});
      const url=URL.createObjectURL(blob),a=document.createElement('a');
      a.href=url;a.download='20-20_BRIDGE_V3.bat';
      document.body.appendChild(a);a.click();a.remove();
      setTimeout(()=>URL.revokeObjectURL(url),3000);
      if(startPolling){
        suPluginToast('SketchUpBridge BAT stažen. Spusť ho; Toolbox pak verze načte automaticky.');
        pollWindowsBridge();
      }
      return true;
    }catch(e){
      suPluginToast('Stažení Bridge selhalo: '+(e?.message||e),true);
      return false;
    }
  }
  window.downloadWindowsBridge=function(){return downloadWindowsBridgeFile(true)};

  async function waitForWindowsBridge(maxMs=45000){
    const started=Date.now();
    while(Date.now()-started<maxMs){
      const st=await bridgeStatus();
      if(st&&st.ok)return st;
      await new Promise(r=>setTimeout(r,700));
    }
    return null;
  }

  async function pollWindowsBridge(){
    for(let i=0;i<40;i++){
      const st=await bridgeStatus();
      if(st&&st.ok){
        applyInstalledVersions(st.installed||{});
        suPluginToast('SketchUpBridge běží · '+(st.sketchup||'SketchUp')+'. Verze pluginů načteny.');
        updateWindowsPanel(true,st.remaining_seconds);
        return true;
      }
      await new Promise(r=>setTimeout(r,750));
    }
    setUnknown();
    updateWindowsPanel(false);
    return false;
  }
  window.pollWindowsBridge=pollWindowsBridge;

  function updateWindowsPanel(online,seconds){
    const state=document.getElementById('su-win-bridge-state');
    if(state)state.textContent=online?'online · '+(Number(seconds)||0)+' s':'vypnutý';
  }

  window.downloadMacSketchUpConnector=function(){
    const a=document.createElement('a');
    a.href=MAC_CONNECTOR_URL;a.download='20-20_Toolbox_Mac_Connector_v1.1.0.rbz';a.rel='noopener';
    document.body.appendChild(a);a.click();a.remove();
    suPluginToast('Mac Connector v1.1.0 stažen. Nainstaluj ho přes SketchUp Extension Manager a restartuj SketchUp.');
  };

  function configureBridgePanel(){
    const box=document.querySelector('.suplugins-bridge');if(!box)return;
    if(IS_WIN){
      box.innerHTML='<div class="suplugins-bridge-row"><span class="suplugins-dot ok"></span><b>SketchUpBridge:</b><span id="su-win-bridge-state">kontroluji…</span></div>'+
        '<div style="margin-top:5px;color:var(--muted)">Starý Windows režim bez Connectoru a bez registrace protokolu. Klikni na <b>Zapnout SketchUpBridge</b>, spusť stažený BAT a Bridge poběží 2 minuty na <code>127.0.0.1:8093</code>.</div>'+
        '<div class="suplugins-bridge-actions"><button class="suplugins-bridge-start" onclick="downloadWindowsBridge()">Zapnout SketchUpBridge (.bat)</button><button class="back-btn" style="margin:0;padding:6px 8px;font-size:10px" onclick="pollWindowsBridge()">Zkontrolovat / načíst verze</button></div>'+
        '<div class="suplugins-bridge-help show">Po spuštění BATu ho Toolbox automaticky pozná. Během 2 minut můžeš kontrolovat verze, instalovat, aktualizovat a odinstalovat pluginy.</div>';
      return;
    }
    box.innerHTML='<div class="suplugins-bridge-row"><span class="suplugins-dot ok"></span><b>macOS Connector:</b><span>RBZ uvnitř SketchUpu</span></div>'+
      '<div style="margin-top:5px;color:var(--muted)">Na Macu zůstává samostatný Connector přes Extension Manager.</div>'+
      '<div class="suplugins-bridge-actions"><button class="suplugins-bridge-start" onclick="downloadMacSketchUpConnector()">Stáhnout Mac Connector (.rbz)</button></div>';
  }

  window.refreshSuPluginVersions=async function(){
    const st=await bridgeStatus();
    if(!st){setUnknown();updateWindowsPanel(false);return false}
    applyInstalledVersions(st.installed||{});updateWindowsPanel(true,st.remaining_seconds);return true;
  };

  window.downloadSuPlugin=async function(id,version){
    try{
      const x=await suPluginBytes(id,version),blob=new Blob([x.bytes],{type:'application/zip'}),url=URL.createObjectURL(blob),a=document.createElement('a');
      a.href=url;a.download=x.version.file;document.body.appendChild(a);a.click();a.remove();
      setTimeout(()=>URL.revokeObjectURL(url),2500);markDownloaded(id,version);
      const st=await bridgeStatus();if(st)applyInstalledVersions(st.installed||{});
      suPluginToast(x.plugin.name+' v'+version+' · RBZ staženo.');
    }catch(e){suPluginToast('Stažení selhalo: '+(e?.message||e),true)}
  };

  async function performSuPluginInstall(id,version,x){
    try{
      let r;
      if(x.version.repo_file){
        r=await fetch(BRIDGE_URL+'/install?file='+encodeURIComponent(x.version.file)+'&repo='+encodeURIComponent(x.version.repo_file),{method:'POST'});
      }else{
        const payload=await suPluginBytes(id,version);
        r=await fetch(BRIDGE_URL+'/install?file='+encodeURIComponent(payload.version.file),{method:'POST',headers:{'Content-Type':'application/octet-stream'},body:payload.bytes});
      }
      const data=await r.json().catch(()=>({}));
      if(!r.ok||!data.ok)throw new Error(data.error||('HTTP '+r.status));
      applyInstalledVersions(data.installed||{});
      updateWindowsPanel(true,data.remaining_seconds);
      suPluginToast(x.plugin.name+' v'+version+' nainstalován / aktualizován do '+(data.sketchup||'SketchUp')+'. Restartuj SketchUp.');
      return true;
    }catch(e){
      suPluginToast('Instalace selhala: '+(e?.message||e),true);
      return false;
    }
  }

  window.installSuPlugin=async function(id,version){
    let x;try{x=suPluginPayload(id,version)}catch(e){suPluginToast(e?.message||String(e),true);return}
    let st=await bridgeStatus();

    if(!st&&IS_WIN){
      setUnknown();
      const downloaded=await downloadWindowsBridgeFile(false);
      if(!downloaded)return;
      suPluginToast('Bridge je stažený. Spusť 20-20_BRIDGE_V3.bat — Toolbox čeká a instalaci pak dokončí sám.');
      st=await waitForWindowsBridge(45000);
      if(!st){
        setUnknown();
        updateWindowsPanel(false);
        suPluginToast('Bridge se do 45 sekund nespustil. Prohlížeč neumí BAT spustit sám — otevři stažený 20-20_BRIDGE_V3.bat a klikni Nainstalovat znovu.',true);
        return;
      }
      applyInstalledVersions(st.installed||{});
      updateWindowsPanel(true,st.remaining_seconds);
    }

    if(!st){
      setUnknown();
      suPluginToast('Mac Connector není aktivní.',true);
      return;
    }

    await performSuPluginInstall(id,version,x);
  };

  window.uninstallSuPlugin=async function(id){
    const p=getSuPlugin(id);if(!p||!p.loader){suPluginToast('U tohoto pluginu není znám loader pro bezpečné odinstalování.',true);return}
    if(!confirm('Odinstalovat '+p.name+' ze SketchUpu?'))return;
    const st=await bridgeStatus();if(!st){suPluginToast('SketchUpBridge neběží. Spusť nejdřív BAT.',true);return}
    try{
      const r=await fetch(BRIDGE_URL+'/uninstall?loader='+encodeURIComponent(p.loader),{method:'POST'});
      const data=await r.json().catch(()=>({}));
      if(!r.ok||!data.ok)throw new Error(data.error||('HTTP '+r.status));
      applyInstalledVersions(data.installed||{});
      suPluginToast(p.name+' odinstalován. Restartuj SketchUp.');
    }catch(e){suPluginToast('Odinstalace selhala: '+(e?.message||e),true)}
  };

  // Preserve index.html's native two-area renderer. The previous override
  // repainted every plugin into #suplugins-grid, defeating Legacy plugins.
  // This wrapper only adds the extra Uninstall controls and Bridge panel.
  const renderSketchUpPluginsNative = window.renderSketchUpPlugins;
  window.renderSketchUpPlugins = function(){
    configureBridgePanel();
    if(typeof renderSketchUpPluginsNative !== 'function')return;
    renderSketchUpPluginsNative();
    for(const plugin of SU_PLUGIN_CATALOG){
      const card=document.getElementById('suplugin-'+plugin.id);
      if(!card)continue;
      const actions=card.querySelector('.suplugin-actions');
      if(!actions||actions.querySelector('.suplugin-uninstall'))continue;
      const button=document.createElement('button');
      button.type='button';
      button.className='suplugin-uninstall';
      button.textContent='Odinstalovat';
      button.addEventListener('click',()=>uninstallSuPlugin(plugin.id));
      const older=actions.querySelector('.suplugin-old-btn');
      if(older)actions.insertBefore(button,older);
      else actions.appendChild(button);
    }
  };
})();