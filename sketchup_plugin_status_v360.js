(() => {
  const KEY='2020toolbox.sketchupPluginDownloads.v1';
  const UA=(navigator.userAgent||'')+' '+(navigator.platform||'');
  const IS_MAC=/Macintosh|Mac OS X|MacIntel/i.test(UA);
  const IS_WIN=/Windows|Win32|Win64/i.test(UA);
  const CONNECTOR_URL='https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/SketchUpPluginInstaller/20-20_Toolbox_Connector_v2.0.3.rbz';
  const WINDOWS_HELPER_URL='https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/SketchUpPluginInstaller/INSTALL_20-20_SKETCHUP_HELPER_V3.bat';
  const WINDOWS_BRIDGE_SCHEME='twentytwentytoolboxv3://bridge';
  const loaderFixes={
    'ai-exporter':'twentytwenty_nano_banana_exporter.rb'
  };
  try{SU_PLUGIN_CATALOG.forEach(p=>{if(!p.loader&&loaderFixes[p.id])p.loader=loaderFixes[p.id]})}catch(_){ }

  function readDownloads(){try{return JSON.parse(localStorage.getItem(KEY)||'{}')||{}}catch(_){return {}}}
  function markDownloaded(id,version){const s=readDownloads();s[id]={version:String(version||''),at:Date.now()};try{localStorage.setItem(KEY,JSON.stringify(s))}catch(_){}}
  function downloadedVersion(id){const x=readDownloads()[id];return x&&x.version?String(x.version):null}
  function stateEl(id){return document.getElementById('suplugin-state-'+id)}
  function unknownStates(){try{SU_PLUGIN_CATALOG.forEach(p=>{const el=stateEl(p.id);if(el){el.className='suplugin-state none';el.textContent='stav nezjištěn'}})}catch(_){}}

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

  function downloadFile(url,name){
    const a=document.createElement('a');
    a.href=url;a.download=name;a.rel='noopener';
    document.body.appendChild(a);a.click();a.remove();
  }

  window.downloadWindowsSketchUpHelper=async function(){
    try{
      const resp=await fetch(WINDOWS_HELPER_URL,{cache:'no-store'});
      if(!resp.ok)throw new Error('HTTP '+resp.status);
      const text=await resp.text();
      if(!text||text.indexOf('@echo off')<0)throw new Error('Stažený obsah není platný BAT helper.');
      const blob=new Blob([text],{type:'application/octet-stream'});
      const url=URL.createObjectURL(blob);
      const a=document.createElement('a');
      a.href=url;
      a.download='INSTALL_20-20_SKETCHUP_HELPER_V3.bat';
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(()=>URL.revokeObjectURL(url),3000);
      suPluginToast('Windows Helper stažen jako skutečný .bat soubor. Spusť ho jednou; potom se Bridge zapíná automaticky a skrytě.');
    }catch(e){
      suPluginToast('Stažení Windows Helperu selhalo: '+(e?.message||e),true);
    }
  };

  window.downloadSketchUpConnector=function(){
    if(IS_WIN){window.downloadWindowsSketchUpHelper();return}
    downloadFile(CONNECTOR_URL,'20-20_Toolbox_Connector_v2.0.3.rbz');
    suPluginToast('20-20 Toolbox Connector v2.0.3 stažen. Nainstaluj ho jednou přes SketchUp Extension Manager a SketchUp restartuj.');
  };
  window.downloadMacSketchUpConnector=function(){
    downloadFile(CONNECTOR_URL,'20-20_Toolbox_Connector_v2.0.3.rbz');
  };

  function launchWindowsBridge(){
    if(!IS_WIN)return false;
    const a=document.createElement('a');
    a.href=WINDOWS_BRIDGE_SCHEME;
    a.style.display='none';
    document.body.appendChild(a);
    a.click();
    a.remove();
    return true;
  }

  const BRIDGE_ENDPOINTS=['http://127.0.0.1:8092','http://localhost:8092'];
  let activeBridgeEndpoint=BRIDGE_ENDPOINTS[0];

  async function bridgeRequest(path,options){
    const ordered=[activeBridgeEndpoint].concat(BRIDGE_ENDPOINTS.filter(x=>x!==activeBridgeEndpoint));
    let lastError=null;
    for(const base of ordered){
      try{
        const r=await fetch(base+path,options||{});
        activeBridgeEndpoint=base;
        return r;
      }catch(e){lastError=e}
    }
    throw lastError||new Error('Connector nedostupný');
  }

  window.suBridgeStatus=async function(){
    const ordered=[activeBridgeEndpoint].concat(BRIDGE_ENDPOINTS.filter(x=>x!==activeBridgeEndpoint));
    for(const base of ordered){
      const c=new AbortController(),t=setTimeout(()=>c.abort(),1500);
      try{
        const r=await fetch(base+'/status',{cache:'no-store',signal:c.signal});
        clearTimeout(t);
        if(!r.ok)continue;
        const data=await r.json();
        if(data&&data.ok){activeBridgeEndpoint=base;return data}
      }catch(e){clearTimeout(t)}
    }
    return null;
  };

  window.ensureSuBridge=async function(file='',waitForStart=false){
    let st=await window.suBridgeStatus();
    if(st&&st.ok)return st;
    if(!waitForStart)return null;

    for(let i=0;i<(IS_WIN?48:10);i++){
      await new Promise(r=>setTimeout(r,250));
      st=await window.suBridgeStatus();
      if(st&&st.ok)return st;
    }
    return null;
  };

  window.startWindowsBridgeAndRefresh=async function(){
    if(!IS_WIN)return refreshSuPluginVersions();
    launchWindowsBridge();
    suPluginToast('Spouštím skrytý Windows Bridge a načítám verze…');
    const st=await ensureSuBridge('',true);
    if(!st){
      unknownStates();
      suPluginToast('Windows Bridge se nespustil. Pokud se prohlížeč zeptal na otevření 20-20 Toolbox Helperu, povol ho. Jinak spusť jednou INSTALL_20-20_SKETCHUP_HELPER_V3.bat.',true);
      return false;
    }
    applyInstalledVersions(st.installed||{});
    suPluginToast('Verze pluginů načteny z '+(st.sketchup||'SketchUp')+'.');
    return true;
  };

  function configureBridgePanel(){
    const box=document.querySelector('.suplugins-bridge');if(!box)return;

    if(IS_WIN){
      box.innerHTML='<div class="suplugins-bridge-row"><span class="suplugins-dot ok"></span><b>Windows SketchUp Bridge:</b><span>skrytý BAT / PowerShell helper</span></div>'+
        '<div style="margin-top:5px;color:var(--muted)">Na Windows používá Toolbox původní lokální Bridge. Helper nainstaluješ jen jednou. Při instalaci / aktualizaci pluginu se pak <b>automaticky a neviditelně</b> spustí a přibližně <b>10 sekund po posledním požadavku se sám vypne</b>.</div>'+
        '<div class="suplugins-bridge-actions"><button class="suplugins-bridge-start" onclick="startWindowsBridgeAndRefresh()">Načíst verze pluginů</button><button class="suplugins-bridge-start" onclick="downloadWindowsSketchUpHelper()">Stáhnout Windows Helper (.bat)</button></div>'+
        '<div class="suplugins-bridge-help show">Jednorázově spusť <b>INSTALL_20-20_SKETCHUP_HELPER_V3.bat</b>. Potom už při běžném používání Toolboxu žádné BAT ani PowerShell okno neuvidíš.</div>';
      return;
    }

    box.innerHTML='<div class="suplugins-bridge-row"><span class="suplugins-dot ok"></span><b>20-20 Toolbox Connector:</b><span>macOS · jednorázově jako RBZ do SketchUpu</span></div>'+
      '<div style="margin-top:5px;color:var(--muted)">Na macOS zůstává Connector přímo uvnitř SketchUpu. Jednou ho nainstaluješ přes Extension Manager a při správě pluginů necháš SketchUp otevřený.</div>'+
      '<div class="suplugins-bridge-actions"><button class="suplugins-bridge-start" onclick="downloadMacSketchUpConnector()">Stáhnout Mac Connector (.rbz)</button></div>'+
      '<div class="suplugins-bridge-help show">SketchUp → Extensions → Extension Manager → Install Extension → vyber <b>20-20_Toolbox_Connector_v2.0.3.rbz</b> → restartuj SketchUp.</div>';
  }

  window.refreshSuPluginVersions=async function(){
    const st=await ensureSuBridge();
    if(!st){
      unknownStates();
      return false;
    }
    applyInstalledVersions(st.installed||{});
    return true;
  };

  window.downloadSuPlugin=async function(id,version){
    try{const x=await suPluginBytes(id,version),blob=new Blob([x.bytes],{type:'application/zip'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=x.version.file;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),2500);markDownloaded(id,version);const s=await suBridgeStatus();if(s&&s.ok)applyInstalledVersions(s.installed||{});suPluginToast(x.plugin.name+' v'+version+' · RBZ staženo.')}
    catch(e){suPluginToast('Stažení selhalo: '+(e?.message||e),true)}
  };

  window.installSuPlugin=async function(id,version){
    if(IS_WIN)launchWindowsBridge();
    let x;try{x=suPluginPayload(id,version)}catch(e){suPluginToast(e?.message||String(e),true);return}
    suPluginToast(IS_WIN?'Skrytě spouštím Windows SketchUp Bridge…':'Připojuji se k 20-20 Toolbox Connectoru…');
    const s=await ensureSuBridge('',IS_WIN);
    if(!s){suPluginToast(IS_WIN?'Windows Bridge se nepodařilo spustit. Jednou spusť INSTALL_20-20_SKETCHUP_HELPER_V3.bat a pak akci zopakuj.':'Mac Connector nereaguje. Zkontroluj, že je v SketchUp Extension Manageru zapnutý a SketchUp běží.',true);return}
    try{
      let r;
      if(x.version.repo_file){
        const url='/install?file='+encodeURIComponent(x.version.file)+'&repo='+encodeURIComponent(x.version.repo_file);
        r=await bridgeRequest(url,{method:'POST'});
      }else{
        const payload=await suPluginBytes(id,version);
        r=await bridgeRequest('/install?file='+encodeURIComponent(payload.version.file),{method:'POST',headers:{'Content-Type':'application/octet-stream'},body:payload.bytes});
      }
      const data=await r.json().catch(()=>({}));if(!r.ok||!data.ok)throw new Error(data.error||('HTTP '+r.status));
      applyInstalledVersions(data.installed||{});suPluginToast(x.plugin.name+' v'+version+' nainstalován / aktualizován do '+(data.sketchup||'SketchUp')+'. Restartuj SketchUp.');
    }catch(e){suPluginToast('Instalace selhala: '+(e?.message||e)+(IS_MAC?'. Otevři Window → Ruby Console ve SketchUpu pro detail.':'. Log: %APPDATA%\\2020toolbox\\SketchUpPluginInstaller\\bridge_v3.log'),true)}
  };

  window.uninstallSuPlugin=async function(id){
    const p=getSuPlugin(id);if(!p||!p.loader){suPluginToast('U tohoto pluginu není znám loader pro bezpečné odinstalování.',true);return}
    if(!confirm('Odinstalovat '+p.name+' ze SketchUpu?'))return;
    if(IS_WIN)launchWindowsBridge();
    const s=await ensureSuBridge('',IS_WIN);if(!s){suPluginToast(IS_WIN?'Windows Bridge se nepodařilo spustit. Pokud prohlížeč nabízí otevření 20-20 Toolbox Helperu, povol ho; jinak spusť znovu jednorázový Windows Helper.':'Mac Connector nereaguje. Zkontroluj jeho stav v SketchUpu.',true);return}
    try{const r=await bridgeRequest('/uninstall?loader='+encodeURIComponent(p.loader),{method:'POST'});const data=await r.json().catch(()=>({}));if(!r.ok||!data.ok)throw new Error(data.error||('HTTP '+r.status));applyInstalledVersions(data.installed||{});suPluginToast(p.name+' odinstalován. Restartuj SketchUp.')}
    catch(e){suPluginToast('Odinstalace selhala: '+(e?.message||e),true)}
  };

  window.renderSketchUpPlugins=function(){
    configureBridgePanel();
    const grid=document.getElementById('suplugins-grid');if(!grid)return;
    grid.innerHTML=SU_PLUGIN_CATALOG.map(p=>{
      const latest=getSuPluginVersion(p,p.current)||p.versions[p.versions.length-1],older=[...p.versions].filter(v=>v.version!==p.current).reverse();
      return `<article class="suplugin-card" id="suplugin-${p.id}"><div class="suplugin-card-main"><div class="suplugin-icon">${suPluginIcon(p.icon)}</div><div class="suplugin-copy"><div class="suplugin-title-row"><div class="suplugin-title">${escapeHtml(p.name)}</div><span class="suplugin-version">v${escapeHtml(p.current)}</span><span id="suplugin-state-${p.id}" class="suplugin-state">zjišťuji…</span></div><div class="suplugin-desc">${escapeHtml(p.description)}</div><div class="suplugin-meta">${escapeHtml(p.meta)} · ${latest?suFmtBytes(latest.size):''}</div></div></div><div class="suplugin-actions"><button class="suplugin-install" onclick="installSuPlugin('${p.id}','${p.current}')">Nainstalovat / aktualizovat</button><button class="suplugin-download" onclick="downloadSuPlugin('${p.id}','${p.current}')">Stáhnout RBZ</button><button class="suplugin-uninstall" onclick="uninstallSuPlugin('${p.id}')">Odinstalovat</button><button class="suplugin-old-btn" onclick="toggleSuPluginHistory('${p.id}')">Starší verze ▾</button></div><div class="suplugin-history" id="suplugin-history-${p.id}"><div class="suplugin-history-title">STARŠÍ VERZE</div>${older.length?older.map(v=>`<div class="suplugin-version-row"><span>v${escapeHtml(v.version)} · ${suFmtBytes(v.size)}</span><button onclick="downloadSuPlugin('${p.id}','${v.version}')">Stáhnout</button><button class="install-old" onclick="installSuPlugin('${p.id}','${v.version}')">Nainstalovat</button></div>`).join(''):'<div class="muted" style="font-size:11px">Žádné starší verze.</div>'}</div></article>`;
    }).join('');
    refreshSuPluginVersions();
  };
})();
