// 20-20 TOOLBOX · AUTORIZACE PDF · V3.36
// Hromadné PAdES podepisování PDF přes lokální AuthorizationBridge.
// Podpis používá certifikát přímo z Windows Certificate Store; privátní klíč neopouští Windows.

(() => {
  'use strict';

  const BRIDGE_URL = 'http://127.0.0.1:8094';
  const BRIDGE_SCHEME = 'twentytwentyauth://start';
  const INSTALLER_URL = 'https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/AuthorizationBridge/INSTALL_AND_START.bat';

  const state = {
    files: [],
    current: -1,
    pdfCache: new Map(),
    renderTask: null,
    viewport: null,
    certFile: null,
    windowsCerts: [],
    selectedCertThumbprint: '',
    stampFile: null,
    certInfo: null,
    bridge: null,
    bridgeToken: null,
    zoom: 1,
    stampSourceName: '',
    placementPreviewUrl: null,
    previousProfile: 'bt',
    settingsRestored: false,
    initialized: false,
  };
  window.authorizationState = state;

  function esc(s) {
    return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
  }
  function fmtSize(n) {
    n = Number(n) || 0;
    if (n < 1024) return n + ' B';
    if (n < 1024*1024) return (n/1024).toFixed(1).replace('.', ',') + ' kB';
    return (n/1024/1024).toFixed(1).replace('.', ',') + ' MB';
  }
  function uid() {
    return (crypto?.randomUUID?.() || Math.random().toString(36).slice(2) + Date.now().toString(36)).replace(/-/g,'');
  }
  function authAppendEarEnabled() {
    return document.getElementById('auth-append-ear')?.checked !== false;
  }

  function authorizationOutputName(name) {
    let base = String(name || 'document.pdf').replace(/\.pdf$/i, '');
    try {
      if (typeof window.removeDiacritics === 'function') base = window.removeDiacritics(base);
    } catch (_) {}
    base = base.replace(/_EAR$/i, '');
    return base + (authAppendEarEnabled() ? '_EAR' : '') + '.pdf';
  }
  function toast(msg, bad=false) {
    const el = document.getElementById('auth-toast');
    if (!el) return;
    el.textContent = msg;
    el.classList.toggle('bad', !!bad);
    el.classList.add('show');
    clearTimeout(toast._t);
    toast._t = setTimeout(() => el.classList.remove('show'), 5200);
  }

  const AUTH_SETTINGS_KEY = '2020toolbox.authorization.settings.v2';
  const AUTH_DB_NAME = '20-20-toolbox-authorization';
  const AUTH_DB_STORE = 'file-handles';

  function authRememberEnabled() {
    return document.getElementById('auth-remember-settings')?.checked !== false;
  }

  function authOpenDb() {
    return new Promise((resolve, reject) => {
      if (!window.indexedDB) return reject(new Error('IndexedDB není dostupné.'));
      const req = indexedDB.open(AUTH_DB_NAME, 1);
      req.onupgradeneeded = () => {
        const db = req.result;
        if (!db.objectStoreNames.contains(AUTH_DB_STORE)) db.createObjectStore(AUTH_DB_STORE);
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error || new Error('Lokální databázi nelze otevřít.'));
    });
  }

  async function authDbSet(key, value) {
    const db = await authOpenDb();
    try {
      await new Promise((resolve, reject) => {
        const tx = db.transaction(AUTH_DB_STORE, 'readwrite');
        tx.objectStore(AUTH_DB_STORE).put(value, key);
        tx.oncomplete = resolve;
        tx.onerror = () => reject(tx.error);
        tx.onabort = () => reject(tx.error);
      });
    } finally { db.close(); }
  }

  async function authDbGet(key) {
    const db = await authOpenDb();
    try {
      return await new Promise((resolve, reject) => {
        const tx = db.transaction(AUTH_DB_STORE, 'readonly');
        const req = tx.objectStore(AUTH_DB_STORE).get(key);
        req.onsuccess = () => resolve(req.result || null);
        req.onerror = () => reject(req.error);
      });
    } finally { db.close(); }
  }

  async function authDbDelete(key) {
    const db = await authOpenDb();
    try {
      await new Promise((resolve, reject) => {
        const tx = db.transaction(AUTH_DB_STORE, 'readwrite');
        tx.objectStore(AUTH_DB_STORE).delete(key);
        tx.oncomplete = resolve;
        tx.onerror = () => reject(tx.error);
      });
    } finally { db.close(); }
  }

  function authCollectSettings() {
    return {
      remember: authRememberEnabled(),
      visible: !!document.getElementById('auth-visible')?.checked,
      addArchitect: !!document.getElementById('auth-add-architect')?.checked,
      architectName: document.getElementById('auth-architect-name')?.value || '',
      addDateTime: !!document.getElementById('auth-add-datetime')?.checked,
      profile: document.getElementById('auth-profile')?.value || 'bt',
      tsa: document.getElementById('auth-tsa')?.value || '',
      tsaUser: document.getElementById('auth-tsa-user')?.value || '',
      localTestTsa: !!document.getElementById('auth-local-test-tsa')?.checked,
      certificateThumbprint: state.selectedCertThumbprint || '',
      reason: document.getElementById('auth-reason')?.value || '',
      location: document.getElementById('auth-location')?.value || '',
      contact: document.getElementById('auth-contact')?.value || '',
      appendEar: authAppendEarEnabled(),
      stampName: state.stampSourceName || ''
    };
  }

  function authUpdateLocalStatus(extra='') {
    const el = document.getElementById('auth-local-status');
    if (!el) return;
    const bits = [];
    if (state.stampSourceName) bits.push('Razítko: '+state.stampSourceName);
    if (state.certInfo?.display_name) bits.push('Certifikát Windows: '+state.certInfo.display_name);
    bits.push('Privátní klíč zůstává ve Windows Certificate Store.');
    if (extra) bits.push(extra);
    el.textContent = bits.join(' · ');
  }

  window.authSaveSettings = async function(showToast=false) {
    if (!authRememberEnabled()) {
      if (showToast) toast('Zapni „zapamatovat nastavení na tomto PC“.', true);
      return;
    }
    try {
      localStorage.setItem(AUTH_SETTINGS_KEY, JSON.stringify(authCollectSettings()));
      let fileNote = '';
      try {
        const sh = await authDbGet('stampHandle');
        if (state.stampSourceName && !sh) fileNote += ' Grafiku razítka vyber přes „Vybrat + zapamatovat soubor“.';
      } catch (_) {}
      authUpdateLocalStatus('Nastavení uloženo lokálně.' + fileNote);
      if (showToast) toast('Nastavení Autorizace bylo uloženo na tomto PC.' + fileNote);
    } catch (e) {
      if (showToast) toast('Nastavení se nepodařilo uložit: '+(e.message||e), true);
    }
  };

  async function authSetStampSource(source) {
    state.stampFile = null;
    state.stampSourceName = source?.name || '';
    const info = document.getElementById('auth-stamp-info');
    if (!source) {
      if (info) info.textContent = 'U PDF se jako grafika razítka použije první strana.';
      await renderStampPreview();
      return;
    }
    try {
      if (info) info.textContent = /\.pdf$/i.test(source.name) || source.type==='application/pdf' ? 'Převádím 1. stranu PDF razítka…' : 'Načítám grafiku razítka…';
      state.stampFile = (/\.pdf$/i.test(source.name) || source.type==='application/pdf') ? await pdfStampToPng(source) : source;
      if (info) info.textContent = 'Použije se: '+source.name + ((/\.pdf$/i.test(source.name) || source.type==='application/pdf') ? ' · 1. strana PDF' : '');
      await renderStampPreview();
      authUpdateLocalStatus();
      if (authRememberEnabled()) authSaveSettings(false);
    } catch (err) {
      state.stampFile = null;
      if (info) info.textContent = 'Chyba: '+(err.message || err);
      toast('Razítko se nepodařilo načíst.', true);
    }
  }

  function authSetCertSource(source) {
    state.certFile = source || null;
    state.certInfo = null;
    const box = document.getElementById('auth-cert-info');
    if (box && !authIsTestMode()) {
      box.className = 'auth-cert-card';
      box.textContent = state.certFile ? 'Vybráno: '+state.certFile.name+'. Klikni na Ověřit certifikát.' : 'Certifikát zatím nebyl načten.';
    }
    authUpdateLocalStatus();
    if (authRememberEnabled()) authSaveSettings(false);
  }

  async function authPermissionForHandle(handle, requestPermission=false) {
    if (!handle) return false;
    try {
      let perm = await handle.queryPermission({mode:'read'});
      if (perm === 'granted') return true;
      if (perm === 'prompt' && requestPermission) perm = await handle.requestPermission({mode:'read'});
      return perm === 'granted';
    } catch { return false; }
  }

  async function authLoadHandle(kind, requestPermission=false) {
    if (kind === 'cert') return false;
    const key = 'stampHandle';
    let handle = null;
    try { handle = await authDbGet(key); } catch {}
    if (!handle) return false;
    const allowed = await authPermissionForHandle(handle, requestPermission);
    if (!allowed) {
      authUpdateLocalStatus('Soubor '+handle.name+' je zapamatovaný; klikni „Načíst uložené“ pro povolení přístupu.');
      return false;
    }
    try {
      const file = await handle.getFile();
      if (kind === 'stamp') await authSetStampSource(file);
      else authSetCertSource(file);
      return true;
    } catch {
      authUpdateLocalStatus('Uložený soubor už není dostupný v původním umístění.');
      return false;
    }
  }

  window.authPickRememberedFile = async function(kind) {
    if (!window.showOpenFilePicker) {
      const input = document.getElementById(kind === 'stamp' ? 'auth-stamp-file' : 'auth-cert-file');
      input?.click();
      toast('Tento prohlížeč neumí trvale pamatovat umístění souboru; vyber ho běžným dialogem.', true);
      return;
    }
    try {
      const opts = kind === 'stamp'
        ? {multiple:false, types:[{description:'Razítko / podpis', accept:{'application/pdf':['.pdf'],'image/png':['.png'],'image/jpeg':['.jpg','.jpeg']}}]}
        : {multiple:false, types:[{description:'PKCS#12 certifikát', accept:{'application/x-pkcs12':['.pfx','.p12']}}]};
      const handles = await window.showOpenFilePicker(opts);
      const handle = handles?.[0];
      if (!handle) return;
      if (kind === 'stamp' && authRememberEnabled()) await authDbSet('stampHandle', handle);
      const file = await handle.getFile();
      if (kind === 'stamp') {
        await authSetStampSource(file);
        if (authRememberEnabled()) await authSaveSettings(false);
        toast('Grafika razítka byla vybrána a její umístění zapamatováno.');
      } else {
        authSetCertSource(file);
        // PFX/P12 je citlivý soubor: jeho FileSystemFileHandle záměrně neukládáme.
        try { await authDbDelete('certHandle'); } catch {}
        toast('Certifikát byl vybrán jen pro tuto relaci. Jeho umístění se z bezpečnostních důvodů neukládá.');
      }
    } catch (e) {
      if (e?.name !== 'AbortError') toast('Soubor se nepodařilo vybrat: '+(e.message||e), true);
    }
  };

  window.authLoadSavedSettings = async function(requestFilePermission=false) {
    // Od V3.27 se PFX/P12 handle nikdy nepamatuje. Smaž i případný legacy
    // handle uložený starší verzí, aby po upgradu nezůstal trvalý přístup.
    try { await authDbDelete('certHandle'); } catch {}
    let saved = null;
    try { saved = JSON.parse(localStorage.getItem(AUTH_SETTINGS_KEY) || 'null'); } catch {}
    if (saved) {
      const setChecked=(id,v)=>{const el=document.getElementById(id);if(el)el.checked=!!v};
      const setValue=(id,v)=>{const el=document.getElementById(id);if(el && v!=null)el.value=String(v)};
      setChecked('auth-remember-settings', saved.remember !== false);
      setChecked('auth-visible', saved.visible !== false);
      setChecked('auth-add-architect', saved.addArchitect);
      setValue('auth-architect-name', saved.architectName || '');
      setChecked('auth-add-datetime', saved.addDateTime);
      setValue('auth-profile', saved.profile || 'bt');
      setValue('auth-tsa', saved.tsa || 'https://www3.postsignum.cz/TSS/TSS_user/');
      setValue('auth-tsa-user', saved.tsaUser || '');
      setChecked('auth-local-test-tsa', !!saved.localTestTsa);
      state.selectedCertThumbprint = saved.certificateThumbprint || state.selectedCertThumbprint || '';
      setValue('auth-reason', saved.reason || 'Autorizace dokumentace');
      setValue('auth-location', saved.location || '');
      setValue('auth-contact', saved.contact || '');
      setChecked('auth-append-ear', saved.appendEar !== false);
      state.stampSourceName = saved.stampName || state.stampSourceName || '';
      authProfileChanged();
      authLocalTestTsaChanged();
      authStampOptionsChanged();
      authToggleVisible();
      authOutputNamingChanged();
    }
    await authLoadHandle('stamp', !!requestFilePermission);
    // Certifikát se z bezpečnostních důvodů mezi relacemi automaticky nenačítá.
    state.settingsRestored = true;
    authUpdateLocalStatus(saved ? 'Uložené nastavení načteno.' : 'Žádné uložené nastavení.');
    if (requestFilePermission) toast(saved ? 'Uložené nastavení bylo načteno.' : 'Žádné uložené nastavení nebylo nalezeno.');
  };

  window.authClearSavedSettings = async function() {
    try { localStorage.removeItem(AUTH_SETTINGS_KEY); } catch {}
    try { await authDbDelete('stampHandle'); } catch {}
    try { await authDbDelete('certHandle'); } catch {}
    authUpdateLocalStatus('Uložené nastavení bylo smazáno.');
    toast('Lokálně uložené nastavení Autorizace bylo smazáno.');
  };

  window.authRememberSettingsChanged = function() {
    if (authRememberEnabled()) authSaveSettings(false);
  };

  function injectStyles() {
    if (document.getElementById('auth-pdf-styles')) return;
    const s = document.createElement('style');
    s.id = 'auth-pdf-styles';
    s.textContent = `
      #tool-authorization{width:calc(100vw - 32px);max-width:none;margin-left:50%;transform:translateX(-50%);background:var(--card);padding:18px 20px;border-radius:12px}
      .auth-titlebar{display:flex;align-items:center;justify-content:space-between;gap:16px;margin:2px 0 6px}
      .auth-titlebar h1{margin:0}
      .auth-test-control{display:flex;align-items:center;gap:9px;padding:7px 10px;border:1px solid var(--border);border-radius:999px;background:#fff;white-space:nowrap}
      .auth-test-control b{font:normal 11px 'Antarctican Mono',monospace}
      .auth-test-switch{position:relative;width:42px;height:22px;display:inline-block}
      .auth-test-switch input{position:absolute;opacity:0;pointer-events:none}
      .auth-test-slider{position:absolute;inset:0;border-radius:999px;background:#d4d4d8;cursor:pointer;transition:.16s}
      .auth-test-slider:before{content:'';position:absolute;width:16px;height:16px;left:3px;top:3px;border-radius:50%;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.25);transition:.16s}
      .auth-test-switch input:checked+.auth-test-slider{background:#eab308}
      .auth-test-switch input:checked+.auth-test-slider:before{transform:translateX(20px)}
      .auth-test-state{min-width:26px;font-size:10px;font-weight:700}
      .auth-test-banner{display:none;margin:0 0 10px;padding:8px 10px;border:1px solid #facc15;border-radius:8px;background:#fffbea;color:#854d0e;font-size:10px;line-height:1.45}
      .auth-test-banner.active{display:block}
      .auth-disabled{opacity:.48;filter:grayscale(.15)}
      .auth-disabled *{pointer-events:none}
      .auth-health{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:10px 12px;border:1px solid var(--border);border-radius:9px;background:#fafafa;margin:10px 0 12px;flex-wrap:wrap}
      .auth-health.ok{background:#f0fdf4;border-color:#bbf7d0}.auth-health.warn{background:#fffbeb;border-color:#fde68a}
      .auth-health.bad{background:#fef2f2;border-color:#fecaca}
      .auth-health-copy{font-size:11px;line-height:1.45}.auth-health-copy b{display:block;font-size:12px;margin-bottom:2px}
      .auth-actions{display:flex;gap:6px;flex-wrap:wrap}.auth-actions button,.auth-actions .back-btn{margin:0}
      .auth-drop{border:1px dashed #a1a1aa;border-radius:9px;background:#fafafa;padding:16px;text-align:center;cursor:pointer;margin-bottom:10px}
      .auth-drop.over{border-color:#8a7d00;background:#fffdec}.auth-drop b{font-weight:600}
      .auth-shell{display:grid;grid-template-columns:240px minmax(0,1fr) 320px;gap:12px;align-items:start}
      .auth-pane{border:1px solid var(--border);border-radius:10px;background:#fafafa;overflow:hidden;min-width:0}
      .auth-pane-head{padding:9px 11px;border-bottom:1px solid var(--border);background:#fff;display:flex;align-items:center;justify-content:space-between;gap:8px}
      .auth-pane-head b{font:normal 12px 'Antarctican Mono',monospace}.auth-small{font-size:10px;color:var(--muted)}
      .auth-file-list{max-height:calc(100vh - 250px);min-height:620px;overflow:auto;padding:7px;display:grid;gap:6px}
      .auth-file{width:100%;border:1px solid var(--border);border-radius:7px;background:#fff;padding:8px;text-align:left;cursor:pointer;color:var(--text)}
      .auth-file:hover{border-color:#d4cc5d;background:#fffef3}.auth-file.active{border-color:#18181b;box-shadow:0 0 0 1px #18181b inset}
      .auth-file-top{display:flex;align-items:flex-start;justify-content:space-between;gap:8px}.auth-file-name{font-size:11px;font-weight:600;line-height:1.25;white-space:normal;overflow:visible;text-overflow:clip;overflow-wrap:anywhere;word-break:break-word;max-width:none;flex:1;min-width:0}
      .auth-file-meta{font-size:9px;color:var(--muted);margin-top:4px;line-height:1.3}.auth-dot{width:8px;height:8px;border-radius:50%;background:#a1a1aa;flex:0 0 auto;margin-top:3px}
      .auth-dot.ready{background:#eab308}.auth-dot.converting{background:#2563eb}.auth-dot.signed{background:#16a34a}.auth-dot.error{background:#dc2626}
      .auth-viewer{height:calc(100vh - 205px);min-height:720px;display:flex;flex-direction:column;background:#e4e4e7}
      .auth-toolbar{padding:7px 8px;background:#fafafa;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:6px;flex-wrap:wrap}
      .auth-toolbar button{border:1px solid var(--border);background:#fff;border-radius:6px;padding:5px 8px;cursor:pointer;font-size:10px;color:var(--text)}
      .auth-toolbar button:hover{background:#fffdec}.auth-toolbar button:disabled{opacity:.4;cursor:not-allowed}
      .auth-toolbar select{font-size:10px;padding:4px 6px;border:1px solid var(--border);border-radius:5px;background:#fff}
      .auth-stage{flex:1;overflow:auto;padding:12px;position:relative}
      .auth-page-wrap{position:relative;margin:0 auto;background:#fff;box-shadow:0 4px 22px rgba(0,0,0,.13);user-select:none}
      #auth-canvas{display:block}
      .auth-sig-box{position:absolute;border:2px solid #d4c700;background:transparent;cursor:move;min-width:48px;min-height:26px;box-shadow:none}
      .auth-sig-box.hidden{display:none}
      .auth-sig-preview-img{position:absolute;inset:3px;width:calc(100% - 6px);height:calc(100% - 6px);object-fit:contain;pointer-events:none;user-select:none}
      .auth-resize{position:absolute;width:12px;height:12px;right:-7px;bottom:-7px;border-radius:50%;background:#f7f197;border:2px solid #d4c700;cursor:nwse-resize}
      .auth-side{padding:10px;display:grid;gap:9px;max-height:calc(100vh - 250px);min-height:620px;overflow:auto}
      .auth-box{border:1px solid var(--border);border-radius:8px;background:#fff;padding:10px}.auth-box h3{font:normal 12px 'Antarctican Mono',monospace;margin:0 0 8px}
      .auth-field{display:grid;gap:4px;margin-bottom:7px}.auth-field:last-child{margin-bottom:0}.auth-field label{font-size:10px;color:var(--muted)}
      .auth-field input,.auth-field select,.auth-field textarea{width:100%;border:1px solid var(--border);border-radius:6px;background:#fff;color:var(--text);padding:7px 8px;font:11px system-ui,Segoe UI,sans-serif}
      .auth-field textarea{min-height:52px;resize:vertical}.auth-check{display:flex;align-items:center;gap:7px;font-size:11px;margin:6px 0}.auth-check input{width:auto}
      .auth-cert-card{font-size:10px;line-height:1.5;padding:8px;border-radius:7px;background:#fafafa;border:1px solid var(--border);overflow-wrap:anywhere}
      .auth-cert-card.ok{background:#f0fdf4;border-color:#bbf7d0}.auth-cert-card.bad{background:#fef2f2;border-color:#fecaca;color:#991b1b}
      .auth-primary{width:100%;border:1px solid #18181b;background:#18181b;color:#fff;border-radius:7px;padding:9px 10px;cursor:pointer;font-size:11px}
      .auth-primary:hover{background:#27272a}.auth-primary:disabled{opacity:.45;cursor:not-allowed}
      .auth-secondary{width:100%;border:1px solid var(--border);background:#fff;color:var(--text);border-radius:7px;padding:8px 10px;cursor:pointer;font-size:11px}
      .auth-note{font-size:9.5px;line-height:1.45;color:var(--muted);margin-top:6px}
      .auth-warn{font-size:9.5px;line-height:1.45;color:#92400e;background:#fffbeb;border:1px solid #fde68a;border-radius:7px;padding:7px}
      #auth-toast{position:fixed;right:18px;bottom:18px;z-index:10050;background:#18181b;color:#fff;padding:10px 12px;border-radius:8px;font-size:11px;box-shadow:0 8px 30px rgba(0,0,0,.24);opacity:0;transform:translateY(8px);pointer-events:none;transition:.18s}
      #auth-toast.show{opacity:1;transform:none}#auth-toast.bad{background:#7f1d1d}
      .auth-zoom-readout{min-width:46px;text-align:center;font-size:10px;color:var(--muted)}
      .auth-stamp-layout-options{display:grid;gap:7px;margin-top:8px;padding-top:8px;border-top:1px solid var(--border)}
      .auth-stamp-preview{display:flex;align-items:center;gap:10px;padding:8px;border:1px dashed var(--border);border-radius:7px;background:#fafafa;min-height:54px}
      .auth-stamp-preview img{max-width:90px;max-height:54px;object-fit:contain}
      .auth-stamp-preview-text{font-size:10px;line-height:1.35;min-width:0;flex:1;overflow-wrap:anywhere}
      .auth-stamp-preview-text b{display:block;max-width:100%;font-size:clamp(7px,1.15vw,10px);line-height:1.25}
      .auth-local-actions{display:grid;grid-template-columns:1fr 1fr;gap:6px;margin-top:7px}
      .auth-local-actions .auth-secondary{margin:0}
      .auth-local-status{margin-top:7px;padding:7px 8px;border:1px solid var(--border);border-radius:7px;background:#fafafa;font-size:9.5px;line-height:1.45;color:var(--muted)}
      .auth-file-memory-btn{margin-top:6px}
      @media(max-width:1050px){#tool-authorization{width:calc(100vw - 16px);padding:12px}.auth-shell{grid-template-columns:210px minmax(0,1fr)}.auth-pane.auth-settings{grid-column:1/-1}.auth-side{max-height:none;min-height:0;grid-template-columns:repeat(2,minmax(0,1fr))}.auth-file-list{min-height:0}.auth-viewer{min-height:620px}}
      @media(max-width:760px){#tool-authorization{width:100vw;border-radius:0}.auth-shell{grid-template-columns:1fr}.auth-viewer{height:620px;min-height:620px}.auth-side{grid-template-columns:1fr}.auth-file-list{max-height:240px;min-height:0}}
    `;
    document.head.appendChild(s);
  }

  function injectMenuTile() {
    if (document.getElementById('auth-menu-tile')) return;
    const row = document.querySelector('.menu-app-row.beta') || document.querySelector('.menu-app-row');
    if (!row) return;
    const tile = document.createElement('div');
    tile.id = 'auth-menu-tile';
    tile.className = 'tile';
    tile.setAttribute('onclick', "openTool('authorization')");
    tile.innerHTML = '<b>Autorizace PDF <small class="menu-status">BETA</small></b><span>Hromadné razítkování a PAdES podpis certifikátem</span>';
    row.appendChild(tile);
  }

  function injectView() {
    if (document.getElementById('tool-authorization')) return;
    const host = document.getElementById('tool-3dprint')?.parentElement || document.querySelector('.card') || document.body;
    const view = document.createElement('div');
    view.id = 'tool-authorization';
    view.className = 'tool-view';
    view.innerHTML = `
      <button class="back-btn" onclick="closeTool()">← Zpět do menu</button>
      <div class="auth-titlebar">
        <h1>Autorizace PDF <small class="menu-status">BETA</small></h1>
        <div class="auth-test-control" title="Testovací režim použije dočasný lokální self-signed certifikát.">
          <b>TEST</b>
          <label class="auth-test-switch">
            <input id="auth-test-mode" type="checkbox" onchange="authTestModeChanged()">
            <span class="auth-test-slider"></span>
          </label>
          <span id="auth-test-state" class="auth-test-state">OFF</span>
        </div>
      </div>
      <div id="auth-test-banner" class="auth-test-banner"><b>TEST MODE:</b> certifikát ani TSA nejsou potřeba. PDF bude skutečně digitálně podepsané dočasným lokálním testovacím certifikátem, který nebude důvěryhodný. V PDF prohlížeči se proto zobrazí informace o podpisu, ale ne jako platná autorizace.</div>
      <div class="muted">Hromadné rozmístění podpisového razítka a skutečný elektronický podpis PDF. Před podpisem se každý dokument lokálně převede stejným Ghostscript enginem jako modul PDF/A na <b>PDF/A-3b</b>; teprve potom se kryptograficky podepíše. Výstup má vždy příponu <b>_EAR.pdf</b>. PFX/P12 a heslo se neposílají na webový server.</div>

      <div id="auth-health" class="auth-health warn">
        <div class="auth-health-copy"><b>AuthorizationBridge se kontroluje…</b><span>Lokální služba na 127.0.0.1:8094.</span></div>
        <div class="auth-actions">
          <button class="back-btn" onclick="launchAuthorizationBridge()">▶ Spustit bridge</button>
          <button class="back-btn" onclick="checkAuthorizationBridge(false)">↻ Zkontrolovat</button>
          <button class="back-btn" onclick="downloadAuthorizationBridgeInstaller()">↓ Instalátor</button>
        </div>
      </div>

      <div id="auth-drop" class="auth-drop">
        <b>Přetáhni sem PDF nebo klikni pro výběr</b><br>
        <span class="auth-small">Lze vložit více PDF najednou — kliknutím nebo drag & drop kamkoli do této aplikace. U vícestránkového PDF se zobrazuje jen 1. strana; export zůstává kompletní vícestránkový dokument.</span>
        <input id="auth-files" type="file" accept=".pdf,application/pdf" multiple hidden>
      </div>

      <div class="auth-shell">
        <section class="auth-pane">
          <div class="auth-pane-head"><b>DOKUMENTY</b><span id="auth-file-count" class="auth-small">0 PDF</span></div>
          <div id="auth-file-list" class="auth-file-list"><div class="auth-small" style="padding:8px">Zatím žádné PDF.</div></div>
        </section>

        <section class="auth-pane auth-viewer">
          <div class="auth-toolbar">
            <span id="auth-page-info" class="auth-small">Náhled 1. strany</span>
            <button onclick="authZoomOut()" title="Oddálit">−</button>
            <span id="auth-zoom-readout" class="auth-zoom-readout">100 %</span>
            <button onclick="authZoomIn()" title="Přiblížit">+</button>
            <button onclick="authZoomFit()" title="Přizpůsobit šířce">Přizpůsobit</button>
            <button style="margin-left:auto" onclick="authApplyPlacementToAll()">Nastavit tuto pozici všem</button>
          </div>
          <div id="auth-stage" class="auth-stage">
            <div id="auth-page-wrap" class="auth-page-wrap" style="display:none">
              <canvas id="auth-canvas"></canvas>
              <div id="auth-sig-box" class="auth-sig-box">
                <img id="auth-sig-preview-img" class="auth-sig-preview-img" alt="" hidden>
                <span id="auth-resize" class="auth-resize"></span>
              </div>
            </div>
            <div id="auth-empty" class="auth-small" style="padding:26px;text-align:center">Nahraj PDF a vyber dokument vlevo.</div>
          </div>
        </section>

        <section class="auth-pane auth-settings">
          <div class="auth-pane-head"><b>PODPIS A CERTIFIKÁT</b><span class="auth-small">PAdES</span></div>
          <div class="auth-side">
            <div class="auth-box">
              <h3>LOKÁLNÍ NASTAVENÍ</h3>
              <label class="auth-check"><input id="auth-remember-settings" type="checkbox" checked onchange="authRememberSettingsChanged()"> zapamatovat nastavení na tomto PC</label>
              <div class="auth-local-actions">
                <button class="auth-secondary" type="button" onclick="authSaveSettings(true)">Uložit teď</button>
                <button class="auth-secondary" type="button" onclick="authLoadSavedSettings(true)">Načíst uložené</button>
              </div>
              <button class="auth-secondary" style="margin-top:6px" type="button" onclick="authClearSavedSettings()">Smazat uložené nastavení</button>
              <div id="auth-local-status" class="auth-local-status">Nastavení se ukládá jen v tomto prohlížeči. Heslo certifikátu se nikdy neukládá.</div>
            </div>

            <div class="auth-box">
              <h3>VIDITELNÉ RAZÍTKO</h3>
              <label class="auth-check"><input id="auth-visible" type="checkbox" checked onchange="authToggleVisible()"> zobrazit podpis na stránce</label>
              <div class="auth-field"><label>Grafika razítka / podpisu (PNG, JPG nebo PDF)</label><input id="auth-stamp-file" type="file" accept=".png,.jpg,.jpeg,.pdf,image/png,image/jpeg,application/pdf"></div>
              <button class="auth-secondary auth-file-memory-btn" type="button" onclick="authPickRememberedFile('stamp')">Vybrat + zapamatovat soubor</button>
              <div id="auth-stamp-info" class="auth-small">U PDF se jako grafika razítka použije první strana.</div>
              <div class="auth-stamp-layout-options">
                <label class="auth-check"><input id="auth-add-architect" type="checkbox" onchange="authStampOptionsChanged()"> přidat jméno architekta vedle razítka</label>
                <div id="auth-architect-wrap" class="auth-field" style="display:none"><label>Jméno architekta</label><input id="auth-architect-name" placeholder="Jméno a příjmení" oninput="authStampOptionsChanged()"></div>
                <label class="auth-check"><input id="auth-add-datetime" type="checkbox" onchange="authStampOptionsChanged()"> přidat datum a čas podpisu</label>
                <div id="auth-stamp-preview" class="auth-stamp-preview"><span class="auth-small">Náhled vzhledu podpisu</span></div>
              </div>
            </div>

            <div id="auth-cert-box" class="auth-box">
              <h3>CERTIFIKÁT Z WINDOWS</h3>
              <div class="auth-field">
                <label>Podpisový certifikát</label>
                <select id="auth-win-cert" onchange="authWindowsCertificateChanged()">
                  <option value="">Načítám certifikáty z Windows…</option>
                </select>
              </div>
              <button class="auth-secondary" type="button" onclick="authLoadWindowsCertificates(true)">↻ Načíst certifikáty z Windows</button>
              <div id="auth-cert-info" class="auth-cert-card" style="margin-top:7px">Toolbox načte certifikáty s privátním klíčem z úložiště Windows CurrentUser\\My.</div>
              <div class="auth-note">Privátní klíč se neexportuje do PFX a neopouští Windows. Toolbox přes lokální bridge pouze požádá Windows o provedení kryptografického podpisu.</div>
            </div>

            <div id="auth-sign-level-box" class="auth-box">
              <h3>ÚROVEŇ PODPISU</h3>
              <div class="auth-field"><label>Profil</label>
                <select id="auth-profile" onchange="authProfileChanged()">
                  <option value="bt" selected>PAdES B-T · podpis + časové razítko</option>
                  <option value="bb">PAdES B-B · podpis bez TSA</option>
                </select>
              </div>
              <div id="auth-tsa-wrap">
                <div class="auth-field"><label>RFC 3161 TSA server</label><input id="auth-tsa" type="url" value="https://www3.postsignum.cz/TSS/TSS_user/" placeholder="https://www3.postsignum.cz/TSS/TSS_user/"></div>
                <div class="auth-field"><label>PostSignum login</label><input id="auth-tsa-user" type="text" autocomplete="username" placeholder="uživatelské jméno"></div>
                <div class="auth-field"><label>PostSignum heslo</label><input id="auth-tsa-pass" type="password" autocomplete="off" placeholder="Heslo k TSA se neukládá"></div>
                <label class="auth-check"><input id="auth-local-test-tsa" type="checkbox" onchange="authLocalTestTsaChanged()"> použít <b>TEST TEST TEST</b> lokální časové razítko</label>
                <div id="auth-test-tsa-note" class="auth-note" style="display:none">TEST TSA běží pouze lokálně na 127.0.0.1. Není kvalifikovaná ani důvěryhodná mimo tento testovací počítač.</div>
                <div class="auth-note">Údaje slouží pouze pro přihlášení k serveru časových razítek. Login lze uložit lokálně s nastavením, heslo k TSA se neukládá.</div>
              </div>
            </div>

            <div class="auth-box">
              <h3>METADATA</h3>
              <div class="auth-field"><label>Důvod podpisu</label><input id="auth-reason" value="Autorizace dokumentace"></div>
              <div class="auth-field"><label>Místo</label><input id="auth-location" placeholder="Praha"></div>
              <div class="auth-field"><label>Kontakt</label><input id="auth-contact" placeholder="volitelné"></div>
            </div>

            <div class="auth-box">
              <h3>VÝSTUP</h3>
              <label class="auth-check"><input id="auth-append-ear" type="checkbox" checked onchange="authOutputNamingChanged()"> přidat <b>_EAR</b> za název exportovaného PDF</label>
              <div id="auth-output-name-info" class="auth-cert-card ok"><b>PDF/A-3b + PAdES</b><br>Každý soubor bude exportovaný jako <b>název_EAR.pdf</b>. Pořadí je záměrně PDF/A-3b → podpis, aby se podpis následnou konverzí nezneplatnil.</div>
            </div>

            <div class="auth-warn">Podpisový certifikát se používá přímo z Windows Certificate Store a jeho privátní klíč se neexportuje ani neposílá do prohlížeče. Heslo k TSA se trvale neukládá. TSA login/heslo používá pouze lokální bridge pro přihlášení k nastavenému serveru časových razítek.</div>

            <button id="auth-sign-btn" class="auth-primary" onclick="signAuthorizationBatch()">PDF/A-3b + podepsat + stáhnout ZIP</button>
            <button class="auth-secondary" onclick="authClearAll()">Vyčistit dokumenty</button>
          </div>
        </section>
      </div>
      <div id="auth-toast"></div>
    `;
    host.appendChild(view);
  }

  function authVersionAtLeast(actual, required) {
    const a=String(actual||'0').split('.').map(x=>parseInt(x,10)||0);
    const b=String(required||'0').split('.').map(x=>parseInt(x,10)||0);
    for(let i=0;i<Math.max(a.length,b.length);i++){
      const av=a[i]||0,bv=b[i]||0;
      if(av>bv)return true;
      if(av<bv)return false;
    }
    return true;
  }

  async function authFetchBridgeSession(timeout=2500) {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), timeout);
    try {
      const r = await fetch(BRIDGE_URL + '/session', {cache:'no-store', signal:ctrl.signal});
      const j = await r.json().catch(() => ({}));
      if (!r.ok || !j.ok || !j.token) throw new Error(j.error || 'Bridge nevydal bezpečnostní session.');
      state.bridgeToken = j.token;
      return j.token;
    } finally {
      clearTimeout(t);
    }
  }

  async function bridgeFetch(path, opts={}, timeout=2500) {
    const needsToken = path !== '/status' && path !== '/session';
    if (needsToken && !state.bridgeToken) await authFetchBridgeSession(Math.min(timeout, 5000));

    async function runOnce() {
      const ctrl = new AbortController();
      const t = setTimeout(() => ctrl.abort(), timeout);
      try {
        const headers = new Headers(opts.headers || {});
        if (needsToken && state.bridgeToken) headers.set('X-20-20-Session', state.bridgeToken);
        return await fetch(BRIDGE_URL + path, {...opts, headers, cache:'no-store', signal:ctrl.signal});
      } finally {
        clearTimeout(t);
      }
    }

    let response = await runOnce();
    if (needsToken && response.status === 401) {
      state.bridgeToken = null;
      await authFetchBridgeSession(Math.min(timeout, 5000));
      response = await runOnce();
    }
    return response;
  }

  window.checkAuthorizationBridge = async function(silent=false) {
    const el = document.getElementById('auth-health');
    if (!silent && el) {
      el.className = 'auth-health warn';
      el.querySelector('.auth-health-copy').innerHTML = '<b>Kontroluji AuthorizationBridge…</b><span>127.0.0.1:8094</span>';
    }
    try {
      const r = await bridgeFetch('/status', {}, 1400);
      const j = await r.json();
      if (!r.ok || !j.ok) throw new Error(j.error || 'Bridge neodpovídá.');
      const secureBridge = authVersionAtLeast(j.version, '1.5.0') && !!j.features?.origin_lock && !!j.features?.session_token;
      const staleForTest = authIsTestMode() && (!authVersionAtLeast(j.version, '1.4.0') || !j.features?.test_signing);
      if (secureBridge && !state.bridgeToken) await authFetchBridgeSession(3000);
      state.bridge = j;
      if (el) {
        const bad = !secureBridge || staleForTest;
        el.className = bad ? 'auth-health bad' : 'auth-health ok';
        el.querySelector('.auth-health-copy').innerHTML = !secureBridge
          ? '<b>AuthorizationBridge je potřeba aktualizovat</b><span>běží v' + esc(j.version || '–') + ' · bezpečný režim vyžaduje 1.5.0+ · spusť Instalátor</span>'
          : staleForTest
            ? '<b>AuthorizationBridge je zastaralý pro TEST</b><span>běží v' + esc(j.version || '–') + ' · spusť znovu Instalátor</span>'
            : '<b>AuthorizationBridge je připravený a zabezpečený</b><span>verze ' + esc(j.version || '–') + ' · origin lock + session token · pyHanko ' + esc(j.pyhanko || '–') + '</span>';
      }
      return j;
    } catch (e) {
      state.bridge = null;
      if (el) {
        el.className = 'auth-health bad';
        el.querySelector('.auth-health-copy').innerHTML = '<b>AuthorizationBridge neběží</b><span>Nainstaluj ho jednou a potom ho Toolbox umí spouštět lokálně.</span>';
      }
      return null;
    }
  };

  window.launchAuthorizationBridge = async function() {
    state.bridgeToken = null;
    const frame = document.createElement('iframe');
    frame.style.display = 'none';
    frame.src = BRIDGE_SCHEME;
    document.body.appendChild(frame);
    setTimeout(() => frame.remove(), 1800);
    for (let i=0;i<16;i++) {
      await new Promise(r => setTimeout(r, 300));
      const s = await checkAuthorizationBridge(true);
      if (s) { toast('AuthorizationBridge spuštěn.'); return; }
    }
    toast('Bridge se nespustil. Pokud ještě není nainstalovaný, použij tlačítko Instalátor.', true);
  };

  window.downloadAuthorizationBridgeInstaller = async function() {
    try {
      const r = await fetch(INSTALLER_URL, {cache:'no-store'});
      if (!r.ok) throw new Error('HTTP ' + r.status);
      const blob = await r.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url; a.download = 'INSTALL_20-20_AUTHORIZATION_BRIDGE.bat';
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 2000);
      toast('Instalátor stažen. Spusť ho jednou.');
    } catch (e) {
      toast('Instalátor se nepodařilo stáhnout: ' + e.message, true);
    }
  };

  async function addFiles(list) {
    const incoming = Array.from(list || []).filter(f => /\.pdf$/i.test(f.name) || f.type === 'application/pdf');
    if (!incoming.length) { toast('Vyber PDF soubory.', true); return; }
    for (const file of incoming) {
      const rec = {
        id: uid(), file, name:file.name, size:file.size, status:'ready',
        pages:null, page:1,
        placement:{x:.64,y:.78,w:.30,h:.12}
      };
      state.files.push(rec);
    }
    renderFileList();
    if (state.current < 0) await selectFile(0);
    updateSessionOverview();
  }

  function renderFileList() {
    const list = document.getElementById('auth-file-list');
    const cnt = document.getElementById('auth-file-count');
    if (cnt) cnt.textContent = state.files.length + ' PDF';
    if (!list) return;
    if (!state.files.length) {
      list.innerHTML = '<div class="auth-small" style="padding:8px">Zatím žádné PDF.</div>';
      return;
    }
    list.innerHTML = state.files.map((r,i) => `
      <button class="auth-file ${i===state.current?'active':''}" onclick="authSelectFile(${i})" title="${esc(r.name)}">
        <div class="auth-file-top"><span class="auth-file-name">${esc(r.name)}</span><span class="auth-dot ${esc(r.status)}"></span></div>
        <div class="auth-file-meta">${fmtSize(r.size)} · ${r.pages ? r.pages + ' str.' : 'načítám…'} · razítko: 1. strana</div>
      </button>`).join('');
  }

  async function getPdf(rec) {
    if (state.pdfCache.has(rec.id)) return state.pdfCache.get(rec.id);
    if (!window.pdfjsLib) throw new Error('PDF.js není dostupné.');
    const bytes = new Uint8Array(await rec.file.arrayBuffer());
    const task = pdfjsLib.getDocument({data:bytes});
    const doc = await task.promise;
    rec.pages = doc.numPages;
    if (rec.page > rec.pages) rec.page = rec.pages;
    state.pdfCache.set(rec.id, doc);
    renderFileList();
    return doc;
  }

  async function selectFile(i) {
    if (i < 0 || i >= state.files.length) return;
    state.current = i;
    state.zoom = 1;
    renderFileList();
    await renderCurrent();
  }
  window.authSelectFile = selectFile;

  async function renderCurrent() {
    const empty = document.getElementById('auth-empty');
    const wrap = document.getElementById('auth-page-wrap');
    if (state.current < 0 || !state.files[state.current]) {
      if (empty) empty.style.display = 'block';
      if (wrap) wrap.style.display = 'none';
      return;
    }
    const rec = state.files[state.current];
    try {
      const doc = await getPdf(rec);
      rec.page = 1;
      const page = await doc.getPage(1);
      [
      'auth-visible','auth-add-architect','auth-architect-name','auth-add-datetime',
      'auth-profile','auth-tsa','auth-tsa-user','auth-local-test-tsa','auth-reason','auth-location','auth-contact'
    ].forEach(id => {
      const el = document.getElementById(id);
      if (!el) return;
      const eventName = (el.tagName === 'INPUT' && !['checkbox'].includes(el.type)) ? 'input' : 'change';
      el.addEventListener(eventName, () => { if (authRememberEnabled()) authSaveSettings(false); });
    });

    const stage = document.getElementById('auth-stage');
      const base = page.getViewport({scale:1});
      // Výchozí zoom je vždy FIT PAGE: celá první strana musí být vidět
      // současně na šířku i na výšku, bez ohledu na formát/orientaci PDF.
      // state.zoom je pak pouze uživatelský násobek nad tímto fit měřítkem.
      const maxW = Math.max(260, (stage?.clientWidth || 700) - 28);
      const maxH = Math.max(220, (stage?.clientHeight || 760) - 28);
      const fitScale = Math.max(.08, Math.min(2.2, maxW/base.width, maxH/base.height));
      const scale = Math.max(.05, Math.min(6, fitScale * state.zoom));
      const vp = page.getViewport({scale});
      state.viewport = vp;
      const zoomReadout = document.getElementById('auth-zoom-readout');
      if (zoomReadout) zoomReadout.textContent = Math.round(state.zoom * 100) + ' %';
      const canvas = document.getElementById('auth-canvas');
      const ctx = canvas.getContext('2d', {alpha:false});
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = Math.floor(vp.width*dpr);
      canvas.height = Math.floor(vp.height*dpr);
      canvas.style.width = vp.width + 'px';
      canvas.style.height = vp.height + 'px';
      wrap.style.width = vp.width + 'px';
      wrap.style.height = vp.height + 'px';
      wrap.style.display = 'block';
      empty.style.display = 'none';
      if (state.renderTask) { try { state.renderTask.cancel(); } catch {} }
      state.renderTask = page.render({canvasContext:ctx, viewport:vp, transform:dpr!==1?[dpr,0,0,dpr,0,0]:null});
      await state.renderTask.promise.catch(e => { if (e?.name !== 'RenderingCancelledException') throw e; });
      state.renderTask = null;
      updatePageControls();
      placeOverlay(rec);
    } catch (e) {
      toast('PDF se nepodařilo zobrazit: ' + (e.message || e), true);
    }
  }

  function updatePageControls() {
    const rec = state.files[state.current];
    const info = document.getElementById('auth-page-info');
    if (!rec || !rec.pages || !info) return;
    rec.page = 1;
    info.textContent = rec.pages > 1
      ? 'Náhled: 1. strana · dokument má ' + rec.pages + ' stran'
      : 'Náhled: 1. strana · 1 strana';
  }

  // Vícestránkové PDF se záměrně chová jako jeden dokument.
  // V editoru je vidět pouze titulní / první strana; ostatní stránky zůstávají
  // v původním PDF a při exportu se nijak neodstraňují.
  window.authSetPage = async function() {
    const rec = state.files[state.current]; if (!rec) return;
    rec.page = 1;
    await renderCurrent();
  };
  window.authPrevPage = () => {};
  window.authNextPage = () => {};

  function placeOverlay(rec) {
    const box = document.getElementById('auth-sig-box');
    const wrap = document.getElementById('auth-page-wrap');
    const visible = document.getElementById('auth-visible')?.checked;
    if (!box || !wrap || !rec) return;
    box.classList.toggle('hidden', !visible);
    const p = rec.placement || (rec.placement={x:.64,y:.78,w:.30,h:.12});
    const W = wrap.clientWidth, H = wrap.clientHeight;
    box.style.left = (p.x*W) + 'px';
    box.style.top = (p.y*H) + 'px';
    box.style.width = (p.w*W) + 'px';
    box.style.height = (p.h*H) + 'px';
    updatePlacementStampPreview();
  }

  function persistOverlay() {
    const rec = state.files[state.current];
    const box = document.getElementById('auth-sig-box');
    const wrap = document.getElementById('auth-page-wrap');
    if (!rec || !box || !wrap || !wrap.clientWidth || !wrap.clientHeight) return;
    rec.placement = {
      x: Math.max(0, Math.min(1, box.offsetLeft / wrap.clientWidth)),
      y: Math.max(0, Math.min(1, box.offsetTop / wrap.clientHeight)),
      w: Math.max(.03, Math.min(1, box.offsetWidth / wrap.clientWidth)),
      h: Math.max(.02, Math.min(1, box.offsetHeight / wrap.clientHeight))
    };
  }

  function setupOverlayDrag() {
    const box = document.getElementById('auth-sig-box');
    const handle = document.getElementById('auth-resize');
    const wrap = document.getElementById('auth-page-wrap');
    if (!box || !handle || !wrap || box.dataset.ready) return;
    box.dataset.ready = '1';
    let mode=null,sx=0,sy=0,sl=0,st=0,sw=0,sh=0;
    const move = e => {
      if (!mode) return;
      const dx=e.clientX-sx, dy=e.clientY-sy;
      if (mode==='move') {
        box.style.left = Math.max(0, Math.min(wrap.clientWidth-box.offsetWidth, sl+dx))+'px';
        box.style.top = Math.max(0, Math.min(wrap.clientHeight-box.offsetHeight, st+dy))+'px';
      } else {
        box.style.width = Math.max(48, Math.min(wrap.clientWidth-box.offsetLeft, sw+dx))+'px';
        box.style.height = Math.max(26, Math.min(wrap.clientHeight-box.offsetTop, sh+dy))+'px';
      }
      persistOverlay();
    };
    const up = () => {
      if (!mode) return;
      mode=null; persistOverlay();
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
    };
    box.addEventListener('pointerdown', e => {
      if (e.target===handle) return;
      e.preventDefault(); mode='move'; sx=e.clientX;sy=e.clientY;sl=box.offsetLeft;st=box.offsetTop;
      window.addEventListener('pointermove', move);window.addEventListener('pointerup', up);
    });
    handle.addEventListener('pointerdown', e => {
      e.preventDefault();e.stopPropagation();mode='resize';sx=e.clientX;sy=e.clientY;sw=box.offsetWidth;sh=box.offsetHeight;
      window.addEventListener('pointermove', move);window.addEventListener('pointerup', up);
    });
  }

  window.authZoomIn = async function() {
    state.zoom = Math.min(4, Math.round((state.zoom + 0.15) * 100) / 100);
    await renderCurrent();
  };
  window.authZoomOut = async function() {
    state.zoom = Math.max(0.35, Math.round((state.zoom - 0.15) * 100) / 100);
    await renderCurrent();
  };
  window.authZoomFit = async function() {
    state.zoom = 1;
    await renderCurrent();
  };

  window.authToggleVisible = function() {
    const rec = state.files[state.current];
    if (rec) placeOverlay(rec);
  };

  window.authOutputNamingChanged = function() {
    const info = document.getElementById('auth-output-name-info');
    if (info) {
      info.innerHTML = '<b>PDF/A-3b + PAdES</b><br>Každý soubor bude exportovaný jako <b>' +
        (authAppendEarEnabled() ? 'název_EAR.pdf' : 'název.pdf') +
        '</b>. Pořadí je záměrně PDF/A-3b → podpis, aby se podpis následnou konverzí nezneplatnil.';
    }
    if (authRememberEnabled()) authSaveSettings(false);
  };

  async function bottomRightPlacementMetrics(rec) {
    const doc = await getPdf(rec);
    const page = await doc.getPage(1);
    const vp = page.getViewport({scale:1});
    const p = rec.placement || {x:.64,y:.78,w:.30,h:.12};
    const width = Math.max(1, p.w * vp.width);
    const height = Math.max(1, p.h * vp.height);
    return {
      width,
      height,
      right: Math.max(0, vp.width - ((p.x + p.w) * vp.width)),
      bottom: Math.max(0, vp.height - ((p.y + p.h) * vp.height))
    };
  }

  async function applyBottomRightPlacement(rec, metrics) {
    const doc = await getPdf(rec);
    const page = await doc.getPage(1);
    const vp = page.getViewport({scale:1});
    const width = Math.min(Math.max(1, metrics.width), vp.width);
    const height = Math.min(Math.max(1, metrics.height), vp.height);
    const left = Math.max(0, Math.min(vp.width - width, vp.width - metrics.right - width));
    const top = Math.max(0, Math.min(vp.height - height, vp.height - metrics.bottom - height));
    rec.page = 1;
    rec.placement = {
      x: left / vp.width,
      y: top / vp.height,
      w: width / vp.width,
      h: height / vp.height
    };
  }

  window.authApplyPlacementToAll = async function() {
    const src = state.files[state.current];
    if (!src) return;
    persistOverlay();
    try {
      const metrics = await bottomRightPlacementMetrics(src);
      for (const r of state.files) await applyBottomRightPlacement(r, metrics);
      renderFileList();
      placeOverlay(src);
      toast('Pozice byla nastavena všem podle pravého dolního rohu — stejný fyzický odstup i velikost razítka.');
    } catch (e) {
      toast('Pozici se nepodařilo přenést na všechny dokumenty: ' + (e.message || e), true);
    }
  };

  function authSelectedWindowsCertificate() {
    return state.windowsCerts.find(c => String(c.thumbprint || '').toUpperCase() === String(state.selectedCertThumbprint || '').toUpperCase()) || null;
  }

  function authRenderWindowsCertificateInfo() {
    const box = document.getElementById('auth-cert-info');
    if (!box || authIsTestMode()) return;
    const cert = authSelectedWindowsCertificate();
    state.certInfo = cert;
    if (!cert) {
      box.className = 'auth-cert-card';
      box.textContent = state.windowsCerts.length
        ? 'Vyber podpisový certifikát z Windows.'
        : 'Nebyl nalezen žádný podporovaný RSA certifikát s privátním klíčem.';
      authUpdateLocalStatus();
      return;
    }
    const until = cert.valid_to ? new Date(cert.valid_to).toLocaleDateString('cs-CZ') : '–';
    box.className = 'auth-cert-card ' + (cert.expired ? 'bad' : 'ok');
    box.innerHTML = '<b>'+esc(cert.display_name || cert.subject || 'Windows certifikát')+'</b><br>' +
      'Vydavatel: '+esc(cert.issuer || '–')+'<br>Platnost do: '+esc(until)+'<br>' +
      'RSA: '+esc(cert.key_bits || '–')+' bit · Windows Certificate Store';
    const architect = document.getElementById('auth-architect-name');
    if (architect && !architect.value.trim() && cert.display_name) {
      architect.value = cert.display_name;
      authStampOptionsChanged();
    }
    authUpdateLocalStatus();
  }

  window.authWindowsCertificateChanged = function() {
    const sel = document.getElementById('auth-win-cert');
    state.selectedCertThumbprint = sel?.value || '';
    authRenderWindowsCertificateInfo();
    if (authRememberEnabled()) authSaveSettings(false);
  };

  window.authLoadWindowsCertificates = async function(showToast=false) {
    if (authIsTestMode()) return;
    const sel = document.getElementById('auth-win-cert');
    const box = document.getElementById('auth-cert-info');
    if (sel) {
      sel.disabled = true;
      sel.innerHTML = '<option value="">Načítám certifikáty z Windows…</option>';
    }
    try {
      const bridge = state.bridge || await checkAuthorizationBridge(true);
      if (!bridge) throw new Error('AuthorizationBridge neběží.');
      if (!bridge.features?.windows_cert_store) {
        throw new Error('Aktualizuj AuthorizationBridge přes Instalátor na verzi 1.8.0+.');
      }
      const r = await bridgeFetch('/windows-certificates', {method:'GET'}, 20000);
      const j = await r.json().catch(()=>({}));
      if (!r.ok || !j.ok) throw new Error(j.error || 'Certifikáty z Windows se nepodařilo načíst.');
      state.windowsCerts = Array.isArray(j.certificates) ? j.certificates : [];
      if (sel) {
        const available = state.windowsCerts.filter(c => !c.expired && c.supported !== false && c.has_private_key !== false);
        const diagnostics = state.windowsCerts.filter(c => !available.includes(c));
        sel.innerHTML = '<option value="">— vyber certifikát —</option>' +
          available.map(cert => {
            const until = cert.valid_to ? new Date(cert.valid_to).toLocaleDateString('cs-CZ') : '–';
            const where = cert.store_location ? ' · '+cert.store_location : '';
            const label = (cert.display_name || cert.subject || 'Certifikát') + ' · '+(cert.key_type || 'RSA')+' '+(cert.key_bits || '')+' · do ' + until + where;
            return '<option value="'+esc(cert.thumbprint || '')+'">'+esc(label)+'</option>';
          }).join('') +
          diagnostics.map(cert => {
            const until = cert.valid_to ? new Date(cert.valid_to).toLocaleDateString('cs-CZ') : '–';
            const reason = cert.expired ? 'EXPIROVANÝ' : (!cert.has_private_key ? 'bez privátního klíče' : 'nepodporovaný '+(cert.key_type || 'typ klíče'));
            const label = '⚠ '+(cert.display_name || cert.subject || 'Certifikát')+' · '+reason+' · do '+until;
            return '<option value="" disabled>'+esc(label)+'</option>';
          }).join('');
        if (state.selectedCertThumbprint && available.some(c => String(c.thumbprint).toUpperCase() === String(state.selectedCertThumbprint).toUpperCase())) {
          sel.value = state.selectedCertThumbprint;
        } else if (available.length === 1) {
          state.selectedCertThumbprint = available[0].thumbprint;
          sel.value = available[0].thumbprint;
        } else {
          state.selectedCertThumbprint = sel.value || '';
        }
      }
      authRenderWindowsCertificateInfo();
      if (showToast) {
        const supportedCount = state.windowsCerts.filter(c => !c.expired && c.supported !== false && c.has_private_key !== false).length;
        toast(
          supportedCount
            ? 'Načteno podpisových certifikátů: '+supportedCount+'.'
            : (state.windowsCerts.length
              ? 'Windows certifikáty byly nalezeny, ale žádný zatím nesplňuje podmínky podpisu. Podívej se do seznamu na důvod.'
              : 'Ve Windows nebyl nalezen žádný certifikát v osobním úložišti CurrentUser ani LocalMachine.'),
          !supportedCount
        );
      }
    } catch (e) {
      state.windowsCerts = [];
      state.certInfo = null;
      if (sel) sel.innerHTML = '<option value="">Certifikáty se nepodařilo načíst</option>';
      if (box) { box.className='auth-cert-card bad'; box.textContent=e.message || String(e); }
      if (showToast) toast(e.message || String(e), true);
    } finally {
      if (sel) sel.disabled = false;
    }
  };

  function authIsTestMode() {
    return !!document.getElementById('auth-test-mode')?.checked;
  }

  window.authTestModeChanged = function() {
    const on = authIsTestMode();
    const stateLabel = document.getElementById('auth-test-state');
    const banner = document.getElementById('auth-test-banner');
    const certBox = document.getElementById('auth-cert-box');
    const levelBox = document.getElementById('auth-sign-level-box');
    const profile = document.getElementById('auth-profile');
    const certInfo = document.getElementById('auth-cert-info');

    if (stateLabel) stateLabel.textContent = on ? 'ON' : 'OFF';
    if (banner) banner.classList.toggle('active', on);
    if (certBox) certBox.classList.toggle('auth-disabled', on);
    if (levelBox) levelBox.classList.toggle('auth-disabled', on);

    if (profile) {
      if (on) {
        state.previousProfile = profile.value || 'bt';
        profile.value = 'bb';
        profile.disabled = true;
      } else {
        profile.disabled = false;
        profile.value = state.previousProfile || 'bt';
      }
    }

    const certControls = certBox ? certBox.querySelectorAll('input,button,select') : [];
    certControls.forEach(el => { el.disabled = on; });

    if (certInfo) {
      if (on) {
        certInfo.className = 'auth-cert-card ok';
        certInfo.innerHTML = '<b>TEST certifikát se vytvoří automaticky</b><br>Dočasný self-signed certifikát vznikne pouze lokálně při exportu a nebude důvěryhodný.';
      } else {
        authRenderWindowsCertificateInfo();
      }
    }

    authProfileChanged();
    const signBtn = document.getElementById('auth-sign-btn');
    if (signBtn) signBtn.textContent = on ? 'TEST · PDF/A-3b + podepsat + stáhnout ZIP' : 'PDF/A-3b + podepsat + stáhnout ZIP';
    updatePlacementStampPreview();
    checkAuthorizationBridge(true).then(b => {
      if (!on && b?.features?.windows_cert_store) authLoadWindowsCertificates(false);
    });
  };

  window.authProfileChanged = function() {
    const bt = !authIsTestMode() && document.getElementById('auth-profile')?.value === 'bt';
    const wrap = document.getElementById('auth-tsa-wrap');
    if (wrap) wrap.style.display = bt ? 'grid' : 'none';
  };

  window.authLocalTestTsaChanged = function() {
    const on = !!document.getElementById('auth-local-test-tsa')?.checked;
    const profile = document.getElementById('auth-profile');
    const tsa = document.getElementById('auth-tsa');
    const user = document.getElementById('auth-tsa-user');
    const pass = document.getElementById('auth-tsa-pass');
    const note = document.getElementById('auth-test-tsa-note');

    if (on) {
      if (profile) profile.value = 'bt';
      if (tsa) tsa.value = 'http://127.0.0.1:8094/test-tsa';
      if (user) user.value = 'TEST';
      if (pass) pass.value = 'TEST-ONLY';
      if (note) note.style.display = 'block';
    } else {
      if (tsa && tsa.value === 'http://127.0.0.1:8094/test-tsa') tsa.value = 'https://www3.postsignum.cz/TSS/TSS_user/';
      if (user && user.value === 'TEST') user.value = '';
      if (pass && pass.value === 'TEST-ONLY') pass.value = '';
      if (note) note.style.display = 'none';
    }
    authProfileChanged();
    if (authRememberEnabled()) authSaveSettings(false);
  };

  async function fileToImageElement(file) {
    const url = URL.createObjectURL(file);
    try {
      const img = new Image();
      img.decoding = 'async';
      await new Promise((resolve, reject) => {
        img.onload = resolve;
        img.onerror = () => reject(new Error('Obrázek razítka se nepodařilo načíst.'));
        img.src = url;
      });
      return img;
    } finally {
      // URL is revoked after rasterisation by callers that draw synchronously.
    }
  }

  async function pdfStampToPng(file) {
    if (!window.pdfjsLib) throw new Error('PDF.js není dostupné.');
    const bytes = new Uint8Array(await file.arrayBuffer());
    const doc = await pdfjsLib.getDocument({data:bytes}).promise;
    try {
      const page = await doc.getPage(1);
      const base = page.getViewport({scale:1});
      const targetW = 1800;
      const scale = Math.max(1, Math.min(5, targetW / Math.max(1, base.width)));
      const vp = page.getViewport({scale});
      const canvas = document.createElement('canvas');
      canvas.width = Math.ceil(vp.width);
      canvas.height = Math.ceil(vp.height);
      const ctx = canvas.getContext('2d', {alpha:true});
      await page.render({canvasContext:ctx, viewport:vp, background:'rgba(255,255,255,0)'}).promise;
      const blob = await new Promise((resolve,reject)=>canvas.toBlob(b=>b?resolve(b):reject(new Error('PDF razítko se nepodařilo převést.')),'image/png'));
      const name = String(file.name || 'razitko.pdf').replace(/\.pdf$/i,'') + '.png';
      return new File([blob], name, {type:'image/png', lastModified:Date.now()});
    } finally {
      try { await doc.destroy(); } catch {}
    }
  }

  async function loadStampGraphic(file) {
    const url = URL.createObjectURL(file);
    try {
      const img = new Image();
      img.decoding = 'async';
      await new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=()=>reject(new Error('Grafiku razítka nelze načíst.'));img.src=url;});
      return {img, url};
    } catch(e) {
      URL.revokeObjectURL(url);
      throw e;
    }
  }

  function signatureDisplayLines(signTime) {
    const addName = document.getElementById('auth-add-architect')?.checked;
    const addTime = document.getElementById('auth-add-datetime')?.checked;
    const name = document.getElementById('auth-architect-name')?.value.trim() || '';
    const lines = [];
    if (addName && name) lines.push(name);
    if (addTime) lines.push(signTime || new Intl.DateTimeFormat('cs-CZ',{dateStyle:'short',timeStyle:'short'}).format(new Date()));
    return lines;
  }

  function fitCanvasFontSize(ctx, text, weight, maxSize, maxWidth, family='Arial, sans-serif') {
    const value = String(text || '');
    let size = Math.max(1, Number(maxSize) || 1);
    ctx.font = weight+' '+size+'px '+family;
    const measured = ctx.measureText(value).width || 1;
    if (measured > maxWidth) size = Math.max(6, Math.floor(size * (maxWidth / measured)));
    // Po zaokrouhlení ještě ověř, že se text skutečně vejde.
    while (size > 6) {
      ctx.font = weight+' '+size+'px '+family;
      if (ctx.measureText(value).width <= maxWidth) break;
      size -= 1;
    }
    return size;
  }

  async function buildCompositeStamp(signTime) {
    const lines = signatureDisplayLines(signTime);
    if (!state.stampFile && !lines.length) return null;
    if (state.stampFile && !lines.length) return state.stampFile;

    let graphic = null;
    if (state.stampFile) graphic = await loadStampGraphic(state.stampFile);
    try {
      const gh = graphic ? graphic.img.naturalHeight : 0;
      const gw = graphic ? graphic.img.naturalWidth : 0;
      const textW = lines.length ? 720 : 0;
      const gap = graphic && lines.length ? 50 : 0;
      const h = Math.max(220, gh || 0);
      const scale = graphic && gh ? h / gh : 1;
      const drawnW = graphic ? Math.round(gw * scale) : 0;
      const canvas = document.createElement('canvas');
      canvas.width = Math.max(320, drawnW + gap + textW);
      canvas.height = h;
      const ctx = canvas.getContext('2d');
      ctx.clearRect(0,0,canvas.width,canvas.height);
      if (graphic) ctx.drawImage(graphic.img,0,0,drawnW,h);
      if (lines.length) {
        const x = drawnW + gap;
        const rightPadding = 28;
        const maxTextWidth = Math.max(40, canvas.width - x - rightPadding);
        const baseMainSize = Math.max(30, Math.round(h * .18));
        const baseSubSize = Math.max(24, Math.round(h * .135));
        const mainSize = fitCanvasFontSize(ctx, lines[0], '600', baseMainSize, maxTextWidth);
        ctx.fillStyle = '#18181b';
        ctx.textBaseline = 'middle';
        ctx.font = '600 '+mainSize+'px Arial, sans-serif';
        const startY = lines.length===2 ? h*.40 : h*.50;
        ctx.fillText(lines[0], x, startY);
        if (lines.length===2) {
          const subSize = fitCanvasFontSize(ctx, lines[1], '400', baseSubSize, maxTextWidth);
          ctx.font = '400 '+subSize+'px Arial, sans-serif';
          ctx.fillText(lines[1], x, h*.66);
        }
      }
      const blob = await new Promise((resolve,reject)=>canvas.toBlob(b=>b?resolve(b):reject(new Error('Vzhled podpisu se nepodařilo vytvořit.')),'image/png'));
      return new File([blob], '20-20_signature_appearance.png', {type:'image/png',lastModified:Date.now()});
    } finally {
      if (graphic?.url) URL.revokeObjectURL(graphic.url);
    }
  }

  async function updatePlacementStampPreview() {
    const img = document.getElementById('auth-sig-preview-img');
    if (!img) return;
    try {
      const appearance = await buildCompositeStamp('');
      if (state.placementPreviewUrl) {
        URL.revokeObjectURL(state.placementPreviewUrl);
        state.placementPreviewUrl = null;
      }
      if (!appearance) {
        img.hidden = true;
        img.removeAttribute('src');
        return;
      }
      state.placementPreviewUrl = URL.createObjectURL(appearance);
      img.src = state.placementPreviewUrl;
      img.hidden = false;
    } catch (e) {
      img.hidden = true;
      img.removeAttribute('src');
    }
  }

  async function renderStampPreview() {
    const box = document.getElementById('auth-stamp-preview');
    if (!box) return;
    const lines = signatureDisplayLines('');
    box.innerHTML = '';
    if (state.stampFile) {
      const url = URL.createObjectURL(state.stampFile);
      const img = document.createElement('img');
      img.src = url;
      img.onload = () => setTimeout(()=>URL.revokeObjectURL(url),1000);
      box.appendChild(img);
    }
    const text = document.createElement('div');
    text.className = 'auth-stamp-preview-text';
    if (lines.length) {
      text.innerHTML = lines.map((x,i)=> i===0?'<b>'+esc(x)+'</b>':esc(x)).join('<br>');
    } else {
      text.innerHTML = '<span class="auth-small">'+(state.stampFile?'Pouze grafika razítka':'Bez vlastního vzhledu')+'</span>';
    }
    box.appendChild(text);
    updatePlacementStampPreview();
  }

  window.authStampOptionsChanged = function() {
    const wrap = document.getElementById('auth-architect-wrap');
    if (wrap) wrap.style.display = document.getElementById('auth-add-architect')?.checked ? 'grid' : 'none';
    renderStampPreview();
  };

  window.inspectAuthorizationCertificate = async function() {
    await authLoadWindowsCertificates(true);
  };


  async function absolutePlacementForPdfFile(file, metrics) {
    if (!document.getElementById('auth-visible')?.checked || !metrics) return null;
    if (!window.pdfjsLib) throw new Error('PDF.js není dostupné.');
    const bytes = new Uint8Array(await file.arrayBuffer());
    const doc = await pdfjsLib.getDocument({data:bytes}).promise;
    try {
      const page = await doc.getPage(1);
      // DŮLEŽITÉ: souřadnice se počítají až z FINÁLNÍHO PDF/A, které jde do podpisu.
      // Ghostscript může u některých výkresů změnit MediaBox/CropBox/Rotate/UserUnit.
      // PDF.js viewport + convertToPdfPoint tak mapuje přesně souřadný systém
      // výsledného souboru, ne původního náhledu.
      const vp = page.getViewport({scale:1});
      const width = Math.min(Math.max(1, metrics.width), vp.width);
      const height = Math.min(Math.max(1, metrics.height), vp.height);
      const left = Math.max(0, Math.min(vp.width - width, vp.width - metrics.right - width));
      const top = Math.max(0, Math.min(vp.height - height, vp.height - metrics.bottom - height));
      const right = left + width;
      const bottom = top + height;
      const a = vp.convertToPdfPoint(left, bottom);
      const b = vp.convertToPdfPoint(right, top);
      return {
        page: 0,
        box: [
          Math.round(Math.min(a[0],b[0])*100)/100,
          Math.round(Math.min(a[1],b[1])*100)/100,
          Math.round(Math.max(a[0],b[0])*100)/100,
          Math.round(Math.max(a[1],b[1])*100)/100
        ]
      };
    } finally {
      try { await doc.destroy(); } catch {}
    }
  }

  window.signAuthorizationBatch = async function() {
    if (!state.files.length) { toast('Nejdřív nahraj PDF.', true); return; }
    const testMode = authIsTestMode();
    if (!testMode && !state.selectedCertThumbprint) { toast('Vyber podpisový certifikát z Windows.', true); return; }
    if (typeof window.convertPdfToPdfa !== 'function') {
      toast('PDF/A engine z hlavního Toolboxu není dostupný. Obnov stránku přes Ctrl+F5.', true);
      return;
    }

    const profile = testMode ? 'bb' : document.getElementById('auth-profile').value;
    const tsa = testMode ? '' : document.getElementById('auth-tsa').value.trim();
    const tsaUser = testMode ? '' : document.getElementById('auth-tsa-user')?.value.trim() || '';
    const tsaPass = testMode ? '' : document.getElementById('auth-tsa-pass')?.value || '';
    const localTestTsa = !testMode && !!document.getElementById('auth-local-test-tsa')?.checked;
    if (!testMode && profile==='bt' && !tsa) { toast('Pro PAdES B-T zadej RFC 3161 TSA server.', true); return; }
    if (!testMode && profile==='bt' && (!!tsaUser !== !!tsaPass)) {
      toast('Pro přihlášení k TSA vyplň login i heslo, nebo nech obě pole prázdná.', true);
      return;
    }
    const bridge = await checkAuthorizationBridge(true);
    if (!bridge) { toast('AuthorizationBridge neběží.', true); return; }
    if (!authVersionAtLeast(bridge.version, '1.5.0') || !bridge.features?.origin_lock || !bridge.features?.session_token) {
      toast('Kvůli bezpečnosti je potřeba AuthorizationBridge 1.5.0+. Spusť aktuální Instalátor a potom Zkontrolovat.', true);
      return;
    }
    if (!testMode && !bridge.features?.windows_cert_store) {
      toast('Pro podpis certifikátem z Windows aktualizuj AuthorizationBridge přes Instalátor na verzi 1.8.0+.', true);
      return;
    }
    if (!authAppendEarEnabled() && !bridge.features?.optional_ear_suffix) {
      toast('Pro export bez _EAR aktualizuj AuthorizationBridge přes Instalátor a potom dej Zkontrolovat.', true);
      return;
    }
    if (!testMode && profile === 'bt' && tsaUser && !bridge.features?.tsa_basic_auth) {
      toast('Pro přihlášení k TSA aktualizuj AuthorizationBridge přes Instalátor a potom dej Zkontrolovat.', true);
      return;
    }
    if (localTestTsa && !bridge.features?.local_test_tsa) {
      toast('Pro lokální TEST časové razítko aktualizuj AuthorizationBridge na 1.9.0+.', true);
      return;
    }
    if (testMode && !bridge.features?.test_signing) {
      toast('Běží bridge bez podpory TEST podpisu. Spusť znovu aktuální Instalátor.', true);
      return;
    }

    persistOverlay();
    const btn = document.getElementById('auth-sign-btn');
    btn.disabled = true;

    try {
      // DŮLEŽITÉ: PDF/A konverze musí proběhnout PŘED kryptografickým podpisem.
      // Převod podepsaného PDF přes Ghostscript by existující podpis zneplatnil.
      const docs = new Array(state.files.length);
      const convertedFiles = new Array(state.files.length);
      const placementMetrics = new Array(state.files.length);

      // Ulož fyzickou velikost razítka a vzdálenost od pravého/spodního okraje
      // z náhledu. Absolutní PDF souřadnice se ZÁMĚRNĚ dopočítají až po PDF/A
      // konverzi, protože konverze může změnit page boxy nebo jednotky.
      for (let i=0;i<state.files.length;i++) {
        const rec = state.files[i];
        placementMetrics[i] = document.getElementById('auth-visible')?.checked
          ? await bottomRightPlacementMetrics(rec)
          : null;
        docs[i] = {
          index:i,
          name:rec.name,
          output_name:authorizationOutputName(rec.name),
          pdfa:'3b',
          page_count: rec.pages || null,
          preview_page: 1,
          placement:null
        };
        rec.status = 'converting';
      }
      renderFileList();

      if (typeof window.convertPdfBatchToPdfaFast === 'function') {
        const convertedBytes = await window.convertPdfBatchToPdfaFast(
          state.files.map(r => r.file),
          '3',
          ({index, completed, total, parallelism}) => {
            const rec = state.files[index];
            if (rec) rec.status = 'ready';
            renderFileList();
            btn.textContent = 'PDF/A-3b ' + completed + '/' + total + (parallelism > 1 ? ' · '+parallelism+'× paralelně' : '') + '…';
          }
        );
        for (let i=0;i<convertedBytes.length;i++) {
          convertedFiles[i] = new File([convertedBytes[i]], docs[i].output_name, {
            type:'application/pdf',
            lastModified:Date.now()
          });
          state.files[i].status = 'ready';
        }
      } else {
        for (let i=0;i<state.files.length;i++) {
          const rec = state.files[i];
          btn.textContent = 'PDF/A-3b ' + (i+1) + '/' + state.files.length + '…';
          const sourceBytes = new Uint8Array(await rec.file.arrayBuffer());
          const pdfaBytes = await window.convertPdfToPdfa(sourceBytes, '3');
          convertedFiles[i] = new File([pdfaBytes], docs[i].output_name, {
            type:'application/pdf',
            lastModified:Date.now()
          });
          rec.status = 'ready';
          renderFileList();
        }
      }
      // Teprve teď máme přesně ty PDF/A soubory, které bridge podepíše.
      // Přepočítej box razítka proti jejich skutečnému MediaBox/CropBox/Rotate/UserUnit.
      btn.textContent = 'Přepočítávám pozici razítka…';
      for (let i=0;i<convertedFiles.length;i++) {
        docs[i].placement = await absolutePlacementForPdfFile(convertedFiles[i], placementMetrics[i]);
      }
      renderFileList();

      btn.textContent = 'Podepisuji PDF/A-3b…';
      const signTime = new Intl.DateTimeFormat('cs-CZ',{dateStyle:'short',timeStyle:'short'}).format(new Date());
      const appearanceFile = await buildCompositeStamp(signTime);
      const meta = {
        profile,
        test_mode: testMode,
        tsa_url: tsa,
        tsa_user: tsaUser,
        tsa_password: tsaPass,
        tsa_test_mode: localTestTsa,
        certificate_thumbprint: testMode ? '' : state.selectedCertThumbprint,
        reason: (testMode ? 'TEST – ' : '') + document.getElementById('auth-reason').value.trim(),
        location: document.getElementById('auth-location').value.trim(),
        contact: document.getElementById('auth-contact').value.trim(),
        output_standard:'PDF/A-3b',
        append_ear: authAppendEarEnabled(),
        documents: docs
      };

      const fd = new FormData();
      fd.append('metadata', JSON.stringify(meta));
      if (appearanceFile) fd.append('stamp', appearanceFile, appearanceFile.name);
      convertedFiles.forEach((file, i) => fd.append('pdfs', file, docs[i].output_name));

      const resp = await bridgeFetch(testMode ? '/sign-batch-test' : '/sign-batch', {method:'POST', body:fd}, 240000);
      if (!resp.ok) {
        let msg='Podepisování selhalo.';
        try { const j=await resp.json(); msg=j.error || j.detail || msg; } catch {}
        throw new Error(msg);
      }

      const blob = await resp.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href=url;
      a.download='autorizovane_PDF-A-3b'+(authAppendEarEnabled()?'_EAR':'')+'_'+new Date().toISOString().slice(0,10)+'.zip';
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(()=>URL.revokeObjectURL(url),4000);

      state.files.forEach(r=>r.status='signed');
      renderFileList();
      toast(testMode
        ? 'Hotovo — TEST PDF/A-3b jsou digitálně podepsaná testovacím certifikátem a stažená v ZIPu.'
        : (localTestTsa
          ? 'Hotovo — PDF/A-3b je podepsané a obsahuje TEST TEST TEST lokální časové razítko.'
          : (authAppendEarEnabled()
          ? 'Hotovo — PDF/A-3b dokumenty s příponou _EAR byly podepsané a stažené v ZIPu.'
          : 'Hotovo — PDF/A-3b dokumenty byly podepsané a stažené v ZIPu bez přípony _EAR v názvu.')));
    } catch (e) {
      state.files.forEach(r=>{ if(r.status!=='signed') r.status='error'; });
      renderFileList();
      toast(e.message || String(e), true);
    } finally {
      btn.disabled = false;
      btn.textContent = authIsTestMode() ? 'TEST · PDF/A-3b + podepsat + stáhnout ZIP' : 'PDF/A-3b + podepsat + stáhnout ZIP';
    }
  };

  window.authClearAll = function() {
    if (state.renderTask) { try{state.renderTask.cancel()}catch{} }
    state.pdfCache.forEach(d=>{ try{d.destroy()}catch{} });
    state.pdfCache.clear();
    state.files=[];state.current=-1;
    renderFileList();renderCurrent();updateSessionOverview();
  };

  function updateSessionOverview() {
    try { window.renderSessionDataOverview?.(); } catch {}
  }

  function wireInputs() {
    const view = document.getElementById('tool-authorization');
    const drop = document.getElementById('auth-drop');
    const inp = document.getElementById('auth-files');

    drop.addEventListener('click', e => { if (e.target !== inp) inp.click(); });
    inp.addEventListener('change', async () => { await addFiles(inp.files); inp.value=''; });

    const markDrag = e => {
      if (!e.dataTransfer || !Array.from(e.dataTransfer.types || []).includes('Files')) return;
      e.preventDefault();
      e.stopPropagation();
      if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
      drop.classList.add('over');
    };
    const receiveDrop = e => {
      e.preventDefault();
      e.stopPropagation();
      drop.classList.remove('over');
      const files = e.dataTransfer?.files;
      if (files?.length) addFiles(files);
    };

    // Drag & drop funguje nad celou aplikací Autorizace, nejen nad malým boxem.
    ['dragenter','dragover'].forEach(type => view.addEventListener(type, markDrag));
    view.addEventListener('drop', receiveDrop);
    view.addEventListener('dragleave', e => {
      if (!view.contains(e.relatedTarget)) drop.classList.remove('over');
    });

    document.getElementById('auth-stamp-file').addEventListener('change', async e => {
      await authSetStampSource(e.target.files?.[0] || null);
    });

    const stage = document.getElementById('auth-stage');
    stage.addEventListener('wheel', e => {
      if (!e.ctrlKey) return;
      e.preventDefault();
      state.zoom = Math.max(.35, Math.min(4, state.zoom + (e.deltaY < 0 ? .12 : -.12)));
      renderCurrent();
    }, {passive:false});
    window.addEventListener('resize', () => { if(document.getElementById('tool-authorization')?.classList.contains('active')) renderCurrent(); });
  }

  function patchOpenTool() {
    if (window.__authOpenToolPatched || typeof window.openTool !== 'function') return;
    window.__authOpenToolPatched = true;
    const old = window.openTool;
    window.openTool = function(name) {
      old(name);
      if (name === 'authorization') {
        initAuthorizationApp();
        setTimeout(()=>renderCurrent(),50);
      }
    };
  }

  function patchSessionOverview() {
    if (window.__authSessionPatched || typeof window.sessionDataSections !== 'function') return;
    window.__authSessionPatched = true;
    const old = window.sessionDataSections;
    window.sessionDataSections = function() {
      const arr = old();
      arr.push({title:'Autorizace PDF', files:state.files.map(x=>x.file)});
      return arr;
    };
  }

  window.initAuthorizationApp = async function() {
    if (!state.initialized) {
      state.initialized = true;
      authTestModeChanged();
      authStampOptionsChanged();
      checkAuthorizationBridge(true);
    }
    // Reload saved values every time the tool is opened, not only on the first
    // visit in the current page session. This fixes "Uložit -> zavřít -> otevřít".
    await authLoadSavedSettings(false);
    const bridge = await checkAuthorizationBridge(true);
    if (!authIsTestMode() && bridge?.features?.windows_cert_store) await authLoadWindowsCertificates(false);
    renderFileList();
  };

  function boot() {
    injectStyles();
    injectMenuTile();
    injectView();
    setupOverlayDrag();
    wireInputs();
    patchOpenTool();
    patchSessionOverview();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();