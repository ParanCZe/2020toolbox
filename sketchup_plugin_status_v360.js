(() => {
  const KEY = '2020toolbox.sketchupPluginDownloads.v1';

  function readDownloads(){
    try { return JSON.parse(localStorage.getItem(KEY) || '{}') || {}; }
    catch (_) { return {}; }
  }

  function markDownloaded(id, version){
    const state = readDownloads();
    state[id] = { version: String(version || ''), at: Date.now() };
    try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (_) {}
  }

  function downloadedVersion(id){
    const item = readDownloads()[id];
    return item && item.version ? String(item.version) : null;
  }

  const style = document.createElement('style');
  style.textContent = '.suplugin-state.downloaded{background:#eef2ff!important;border-color:#c7d2fe!important;color:#3730a3!important}';
  document.head.appendChild(style);

  applyInstalledVersions = function(installed){
    SU_PLUGIN_CATALOG.forEach(p => {
      const el = document.getElementById('suplugin-state-' + p.id);
      if (!el) return;

      const installedVersion = p.loader && installed ? installed[p.loader] : null;
      const downloaded = downloadedVersion(p.id);

      if (installedVersion) {
        if (cmpVer(installedVersion, p.current) < 0) {
          el.className = 'suplugin-state update';
          el.textContent = 'v' + installedVersion + ' · nová verze';
        } else {
          el.className = 'suplugin-state ok';
          el.textContent = 'v' + installedVersion + ' · nainstalováno';
        }
        return;
      }

      if (downloaded) {
        el.className = 'suplugin-state downloaded';
        el.textContent = 'v' + downloaded + ' · staženo';
        return;
      }

      el.className = 'suplugin-state none';
      el.textContent = 'nenainstalováno';
    });
  };

  downloadSuPlugin = async function(id, version){
    try {
      const x = await suPluginBytes(id, version);
      const blob = new Blob([x.bytes], { type: 'application/zip' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = x.version.file;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 2500);
      markDownloaded(id, version);
      const installed = await suBridgeStatus();
      applyInstalledVersions(installed && installed.ok ? (installed.installed || {}) : {});
      suPluginToast(x.plugin.name + ' v' + version + ' · RBZ staženo.');
    } catch (e) {
      suPluginToast('Stažení selhalo: ' + (e?.message || e), true);
    }
  };
})();