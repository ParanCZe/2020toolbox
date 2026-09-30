(() => {
  const KEY='2020toolbox.sketchupPluginDownloads.v1';
  const IS_MAC=/Macintosh|Mac OS X|MacIntel/i.test((navigator.userAgent||'')+' '+(navigator.platform||''));
  const MAC_CONNECTOR_URL='https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/SketchUpPluginInstaller/20-20_Toolbox_Mac_Connector_v1.1.0.rbz';
  const originalEnsureSuBridge=window.ensureSuBridge;
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

  window.downloadMacSketchUpConnector=function(){
    const a=document.createElement('a');
    a.href=MAC_CONNECTOR_URL;
    a.download='20-20_Toolbox_Mac_Connector_v1.1.0.rbz';
    a.rel='noopener';
    document.body.appendChild(a);a.click();a.remove();
    suPluginToast('Mac Connector v1.1.0 stažen. Podporuje SketchUp 2017–2026. Ve SketchUpu otevři Extension Manager → Install Extension, vyber RBZ a potom SketchUp restartuj.');
  };

  window.ensureSuBridge=async function(file=''){
    if(IS_MAC){
      let st=await suBridgeStatus();
      if(st&&st.ok)return st;
      for(let i=0;i<8;i++){await new Promise(r=>setTimeout(r,250));st=await suBridgeStatus();if(st&&st.ok)return st}
      return null;
    }
    return originalEnsureSuBridge?originalEnsureSuBridge(file):null;
  };

  function configureBridgePanel(){
    const box=document.querySelector('.suplugins-bridge');if(!box)return;
    if(IS_MAC){
      box.innerHTML='<div class="suplugins-bridge-row"><span class="suplugins-dot ok"></span><b>macOS Connector:</b><span>jednorázově jako RBZ do SketchUpu</span></div>'+
      '<div style="margin-top:5px;color:var(--muted)">Na Macu se nepoužívá BAT. Jednou nainstaluješ <b>20-20 Toolbox Mac Connector</b> přes SketchUp Extension Manager. Verze 1.1.0 podporuje SketchUp 2017–2026. Když je SketchUp otevřený, Toolbox potom umí číst verze, instalovat, aktualizovat i odinstalovat pluginy.</div>'+
      '<div class="suplugins-bridge-actions"><button class="suplugins-bridge-start" onclick="downloadMacSketchUpConnector()">Stáhnout Mac Connector (.rbz)</button></div>'+
      '<div class="suplugins-bridge-help show">Postup: SketchUp → Extensions → Extension Manager → Install Extension → vyber stažený RBZ → restartuj SketchUp. Connector komunikuje jen lokálně přes 127.0.0.1:8092.</div>';
    }
  }

  window.refreshSuPluginVersions=async function(){
    const s=await ensureSuBridge();
    if(!s){unknownStates();return false}
    applyInstalledVersions(s.installed||{});return true;
  };

  window.downloadSuPlugin=async function(id,version){
    try{const x=await suPluginBytes(id,version),blob=new Blob([x.bytes],{type:'application/zip'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=x.version.file;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),2500);markDownloaded(id,version);const s=await suBridgeStatus();if(s&&s.ok)applyInstalledVersions(s.installed||{});suPluginToast(x.plugin.name+' v'+version+' · RBZ staženo.')}
    catch(e){suPluginToast('Stažení selhalo: '+(e?.message||e),true)}
  };

  window.installSuPlugin=async function(id,version){
    let x;try{x=suPluginPayload(id,version)}catch(e){suPluginToast(e?.message||String(e),true);return}
    suPluginToast('Zapínám SketchUp Bridge…');
    const s=await ensureSuBridge();
    if(!s){suPluginToast(IS_MAC?'Mac Connector není aktivní. Nainstaluj ho jednou přes Extension Manager a měj při práci se správou pluginů otevřený SketchUp.':'Bridge se nespustil. Spusť jednorázový Helper V3 a zkus to znovu.',true);return}
    try{
      let r;
      if(x.version.repo_file){
        const url=SU_BRIDGE_URL+'/install?file='+encodeURIComponent(x.version.file)+'&repo='+encodeURIComponent(x.version.repo_file);
        r=await fetch(url,{method:'POST'});
      }else{
        const payload=await suPluginBytes(id,version);
        r=await fetch(SU_BRIDGE_URL+'/install?file='+encodeURIComponent(payload.version.file),{method:'POST',headers:{'Content-Type':'application/octet-stream'},body:payload.bytes});
      }
      const data=await r.json().catch(()=>({}));if(!r.ok||!data.ok)throw new Error(data.error||('HTTP '+r.status));
      applyInstalledVersions(data.installed||{});suPluginToast(x.plugin.name+' v'+version+' nainstalován / aktualizován do '+(data.sketchup||'SketchUp')+'. Restartuj SketchUp.');
    }catch(e){suPluginToast('Instalace selhala: '+(e?.message||e)+(IS_MAC?'. Otevři Window → Ruby Console ve SketchUpu pro detail.':'. Log: %APPDATA%\\2020toolbox\\SketchUpPluginInstaller\\bridge_v3.log'),true)}
  };

  window.uninstallSuPlugin=async function(id){
    const p=getSuPlugin(id);if(!p||!p.loader){suPluginToast('U tohoto pluginu není znám loader pro bezpečné odinstalování.',true);return}
    if(!confirm('Odinstalovat '+p.name+' ze SketchUpu?'))return;
    const s=await ensureSuBridge();if(!s){suPluginToast('Bridge se nespustil.',true);return}
    try{const r=await fetch(SU_BRIDGE_URL+'/uninstall?loader='+encodeURIComponent(p.loader),{method:'POST'});const data=await r.json().catch(()=>({}));if(!r.ok||!data.ok)throw new Error(data.error||('HTTP '+r.status));applyInstalledVersions(data.installed||{});suPluginToast(p.name+' odinstalován. Restartuj SketchUp.')}
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
