// 20-20 TOOLBOX · AUTORIZACE PDF · V3.26
// Hromadné PAdES podepisování PDF přes lokální AuthorizationBridge.
// Privátní klíč / PFX zůstává v počítači uživatele a posílá se pouze na 127.0.0.1.

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
    stampFile: null,
    certInfo: null,
    bridge: null,
    zoom: 1,
    stampSourceName: '',
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
  function earOutputName(name) {
    let base = String(name || 'document.pdf').replace(/\.pdf$/i, '');
    try {
      if (typeof window.removeDiacritics === 'function') base = window.removeDiacritics(base);
    } catch (_) {}
    base = base.replace(/_EAR$/i, '');
    return base + '_EAR.pdf';
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

  function injectStyles() {
    if (document.getElementById('auth-pdf-styles')) return;
    const s = document.createElement('style');
    s.id = 'auth-pdf-styles';
    s.textContent = `
      #tool-authorization{width:calc(100vw - 32px);max-width:none;margin-left:50%;transform:translateX(-50%);background:var(--card);padding:18px 20px;border-radius:12px}
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
      .auth-file-top{display:flex;justify-content:space-between;gap:8px}.auth-file-name{font-size:11px;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:175px}
      .auth-file-meta{font-size:9px;color:var(--muted);margin-top:3px}.auth-dot{width:8px;height:8px;border-radius:50%;background:#a1a1aa;flex:0 0 auto;margin-top:3px}
      .auth-dot.ready{background:#eab308}.auth-dot.converting{background:#2563eb}.auth-dot.signed{background:#16a34a}.auth-dot.error{background:#dc2626}
      .auth-viewer{height:calc(100vh - 205px);min-height:720px;display:flex;flex-direction:column;background:#e4e4e7}
      .auth-toolbar{padding:7px 8px;background:#fafafa;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:6px;flex-wrap:wrap}
      .auth-toolbar button{border:1px solid var(--border);background:#fff;border-radius:6px;padding:5px 8px;cursor:pointer;font-size:10px;color:var(--text)}
      .auth-toolbar button:hover{background:#fffdec}.auth-toolbar button:disabled{opacity:.4;cursor:not-allowed}
      .auth-toolbar select{font-size:10px;padding:4px 6px;border:1px solid var(--border);border-radius:5px;background:#fff}
      .auth-stage{flex:1;overflow:auto;padding:12px;position:relative}
      .auth-page-wrap{position:relative;margin:0 auto;background:#fff;box-shadow:0 4px 22px rgba(0,0,0,.13);user-select:none}
      #auth-canvas{display:block}
      .auth-sig-box{position:absolute;border:2px solid #d4c700;background:rgba(247,241,151,.14);cursor:move;min-width:48px;min-height:26px;box-shadow:0 0 0 1px rgba(255,255,255,.8) inset}
      .auth-sig-box.hidden{display:none}
      .auth-resize{position:absolute;width:13px;height:13px;right:-7px;bottom:-7px;border-radius:50%;background:#18181b;border:2px solid #fff;cursor:nwse-resize}
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
      .auth-stamp-preview-text{font-size:10px;line-height:1.35}
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
      <h1>Autorizace PDF <small class="menu-status">BETA</small></h1>
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
        <span class="auth-small">Lze vložit více PDF najednou — kliknutím nebo drag & drop kamkoli do této aplikace. Každý dokument má vlastní stránku a pozici razítka.</span>
        <input id="auth-files" type="file" accept=".pdf,application/pdf" multiple hidden>
      </div>

      <div class="auth-shell">
        <section class="auth-pane">
          <div class="auth-pane-head"><b>DOKUMENTY</b><span id="auth-file-count" class="auth-small">0 PDF</span></div>
          <div id="auth-file-list" class="auth-file-list"><div class="auth-small" style="padding:8px">Zatím žádné PDF.</div></div>
        </section>

        <section class="auth-pane auth-viewer">
          <div class="auth-toolbar">
            <button id="auth-prev" onclick="authPrevPage()">←</button>
            <select id="auth-page-select" onchange="authSetPage(Number(this.value))"></select>
            <button id="auth-next" onclick="authNextPage()">→</button>
            <span id="auth-page-info" class="auth-small">–</span>
            <button onclick="authZoomOut()" title="Oddálit">−</button>
            <span id="auth-zoom-readout" class="auth-zoom-readout">100 %</span>
            <button onclick="authZoomIn()" title="Přiblížit">+</button>
            <button onclick="authZoomFit()" title="Přizpůsobit šířce">Přizpůsobit</button>
            <button style="margin-left:auto" onclick="authApplyPlacementToAll()">Použít pozici na všechny</button>
          </div>
          <div id="auth-stage" class="auth-stage">
            <div id="auth-page-wrap" class="auth-page-wrap" style="display:none">
              <canvas id="auth-canvas"></canvas>
              <div id="auth-sig-box" class="auth-sig-box">
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
              <h3>VIDITELNÉ RAZÍTKO</h3>
              <label class="auth-check"><input id="auth-visible" type="checkbox" checked onchange="authToggleVisible()"> zobrazit podpis na stránce</label>
              <div class="auth-field"><label>Grafika razítka / podpisu (PNG, JPG nebo PDF)</label><input id="auth-stamp-file" type="file" accept=".png,.jpg,.jpeg,.pdf,image/png,image/jpeg,application/pdf"></div>
              <div id="auth-stamp-info" class="auth-small">U PDF se jako grafika razítka použije první strana.</div>
              <div class="auth-stamp-layout-options">
                <label class="auth-check"><input id="auth-add-architect" type="checkbox" onchange="authStampOptionsChanged()"> přidat jméno architekta vedle razítka</label>
                <div id="auth-architect-wrap" class="auth-field" style="display:none"><label>Jméno architekta</label><input id="auth-architect-name" placeholder="Jméno a příjmení" oninput="authStampOptionsChanged()"></div>
                <label class="auth-check"><input id="auth-add-datetime" type="checkbox" onchange="authStampOptionsChanged()"> přidat datum a čas podpisu</label>
                <div id="auth-stamp-preview" class="auth-stamp-preview"><span class="auth-small">Náhled vzhledu podpisu</span></div>
              </div>
            </div>

            <div class="auth-box">
              <h3>CERTIFIKÁT</h3>
              <div class="auth-field"><label>PFX / P12 s privátním klíčem</label><input id="auth-cert-file" type="file" accept=".pfx,.p12,application/x-pkcs12"></div>
              <div class="auth-field"><label>Heslo k certifikátu</label><input id="auth-cert-pass" type="password" autocomplete="off" placeholder="Heslo se nikam neukládá"></div>
              <button class="auth-secondary" onclick="inspectAuthorizationCertificate()">Ověřit certifikát</button>
              <div id="auth-cert-info" class="auth-cert-card" style="margin-top:7px">Certifikát zatím nebyl načten.</div>
            </div>

            <div class="auth-box">
              <h3>ÚROVEŇ PODPISU</h3>
              <div class="auth-field"><label>Profil</label>
                <select id="auth-profile" onchange="authProfileChanged()">
                  <option value="bt" selected>PAdES B-T · podpis + časové razítko</option>
                  <option value="bb">PAdES B-B · podpis bez TSA</option>
                </select>
              </div>
              <div id="auth-tsa-wrap" class="auth-field"><label>RFC 3161 TSA server</label><input id="auth-tsa" type="url" placeholder="https://tsa.example.cz/..."></div>
              <div class="auth-note">Pro B-T musí TSA URL odpovídat serveru, který poskytuje RFC 3161 časová razítka. Toolbox žádný cizí server nenastavuje automaticky.</div>
            </div>

            <div class="auth-box">
              <h3>METADATA</h3>
              <div class="auth-field"><label>Důvod podpisu</label><input id="auth-reason" value="Autorizace dokumentace"></div>
              <div class="auth-field"><label>Místo</label><input id="auth-location" placeholder="Praha"></div>
              <div class="auth-field"><label>Kontakt</label><input id="auth-contact" placeholder="volitelné"></div>
            </div>

            <div class="auth-box">
              <h3>VÝSTUP</h3>
              <div class="auth-cert-card ok"><b>PDF/A-3b + PAdES</b><br>Každý soubor bude exportovaný jako <b>název_EAR.pdf</b>. Pořadí je záměrně PDF/A-3b → podpis, aby se podpis následnou konverzí nezneplatnil.</div>
            </div>

            <div class="auth-warn">Soubor s certifikátem ani heslo se neukládají do localStorage. Při podepisování jsou odeslány pouze lokální službě na <b>127.0.0.1</b>. Výsledná právní úroveň podpisu závisí také na typu certifikátu a způsobu jeho vydání/uložení.</div>

            <button id="auth-sign-btn" class="auth-primary" onclick="signAuthorizationBatch()">PDF/A-3b + podepsat + stáhnout ZIP</button>
            <button class="auth-secondary" onclick="authClearAll()">Vyčistit dokumenty</button>
          </div>
        </section>
      </div>
      <div id="auth-toast"></div>
    `;
    host.appendChild(view);
  }

  async function bridgeFetch(path, opts={}, timeout=2500) {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), timeout);
    try {
      return await fetch(BRIDGE_URL + path, {...opts, cache:'no-store', signal:ctrl.signal});
    } finally {
      clearTimeout(t);
    }
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
      state.bridge = j;
      if (el) {
        el.className = 'auth-health ok';
        el.querySelector('.auth-health-copy').innerHTML = '<b>AuthorizationBridge je připravený</b><span>verze ' + esc(j.version || '–') + ' · pyHanko ' + esc(j.pyhanko || '–') + '</span>';
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
        <div class="auth-file-meta">${fmtSize(r.size)} · ${r.pages ? r.pages + ' str.' : 'načítám…'} · podpis str. ${r.page}</div>
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
      const page = await doc.getPage(rec.page);
      const stage = document.getElementById('auth-stage');
      const base = page.getViewport({scale:1});
      const maxW = Math.max(260, (stage?.clientWidth || 700) - 28);
      const fitScale = Math.max(.15, Math.min(2.2, maxW/base.width));
      const scale = Math.max(.08, Math.min(6, fitScale * state.zoom));
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
    const sel = document.getElementById('auth-page-select');
    const info = document.getElementById('auth-page-info');
    if (!rec || !rec.pages) return;
    sel.innerHTML = Array.from({length:rec.pages}, (_,i) => '<option value="'+(i+1)+'">Strana '+(i+1)+'</option>').join('');
    sel.value = String(rec.page);
    info.textContent = rec.page + ' / ' + rec.pages;
    document.getElementById('auth-prev').disabled = rec.page <= 1;
    document.getElementById('auth-next').disabled = rec.page >= rec.pages;
  }

  window.authSetPage = async function(p) {
    const rec = state.files[state.current]; if (!rec) return;
    rec.page = Math.max(1, Math.min(rec.pages || 1, Number(p)||1));
    renderFileList(); await renderCurrent();
  };
  window.authPrevPage = () => { const r=state.files[state.current]; if(r && r.page>1) authSetPage(r.page-1); };
  window.authNextPage = () => { const r=state.files[state.current]; if(r && r.page<(r.pages||1)) authSetPage(r.page+1); };

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

  window.authApplyPlacementToAll = function() {
    const src = state.files[state.current];
    if (!src) return;
    persistOverlay();
    for (const r of state.files) {
      r.placement = {...src.placement};
      r.page = Math.min(src.page, r.pages || src.page);
    }
    renderFileList();
    toast('Pozice a číslo stránky byly přeneseny na všechny dokumenty.');
  };

  window.authProfileChanged = function() {
    const bt = document.getElementById('auth-profile')?.value === 'bt';
    const wrap = document.getElementById('auth-tsa-wrap');
    if (wrap) wrap.style.display = bt ? 'grid' : 'none';
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
        const mainSize = Math.max(30, Math.round(h * .18));
        const subSize = Math.max(24, Math.round(h * .135));
        ctx.fillStyle = '#18181b';
        ctx.textBaseline = 'middle';
        ctx.font = '600 '+mainSize+'px Arial, sans-serif';
        const startY = lines.length===2 ? h*.40 : h*.50;
        ctx.fillText(lines[0], x, startY);
        if (lines.length===2) {
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
  }

  window.authStampOptionsChanged = function() {
    const wrap = document.getElementById('auth-architect-wrap');
    if (wrap) wrap.style.display = document.getElementById('auth-add-architect')?.checked ? 'grid' : 'none';
    renderStampPreview();
  };

  window.inspectAuthorizationCertificate = async function() {
    const f = state.certFile;
    const pass = document.getElementById('auth-cert-pass')?.value || '';
    const info = document.getElementById('auth-cert-info');
    if (!f) { toast('Vyber PFX nebo P12.', true); return; }
    const bridge = await checkAuthorizationBridge(true);
    if (!bridge) { toast('AuthorizationBridge neběží.', true); return; }
    info.className = 'auth-cert-card'; info.textContent = 'Ověřuji certifikát…';
    try {
      const fd = new FormData();
      fd.append('certificate', f, f.name);
      fd.append('password', pass);
      const r = await bridgeFetch('/certificate-info', {method:'POST', body:fd}, 15000);
      const j = await r.json().catch(() => ({}));
      if (!r.ok || !j.ok) throw new Error(j.error || 'Certifikát se nepodařilo načíst.');
      state.certInfo = j;
      const architect = document.getElementById('auth-architect-name');
      if (architect && !architect.value.trim() && j.display_name) architect.value = j.display_name;
      info.className = 'auth-cert-card ok';
      info.innerHTML = '<b>'+esc(j.subject || 'Certifikát načten')+'</b><br>Vydavatel: '+esc(j.issuer || '–')+'<br>Platnost: '+esc(j.valid_from || '–')+' → '+esc(j.valid_to || '–')+'<br>Serial: '+esc(j.serial || '–');
      toast('Certifikát je čitelný a obsahuje privátní klíč.');
    } catch (e) {
      state.certInfo = null;
      info.className = 'auth-cert-card bad';
      info.textContent = e.message || String(e);
      toast('Certifikát se nepodařilo ověřit.', true);
    }
  };

  async function absolutePlacement(rec) {
    if (!document.getElementById('auth-visible')?.checked) return null;
    const doc = await getPdf(rec);
    const page = await doc.getPage(rec.page);
    const vp = page.getViewport({scale:1});
    const p = rec.placement;
    const left=p.x*vp.width, top=p.y*vp.height, right=(p.x+p.w)*vp.width, bottom=(p.y+p.h)*vp.height;
    const a = vp.convertToPdfPoint(left, bottom);
    const b = vp.convertToPdfPoint(right, top);
    return {
      page: rec.page-1,
      box: [
        Math.round(Math.min(a[0],b[0])*100)/100,
        Math.round(Math.min(a[1],b[1])*100)/100,
        Math.round(Math.max(a[0],b[0])*100)/100,
        Math.round(Math.max(a[1],b[1])*100)/100
      ]
    };
  }

  window.signAuthorizationBatch = async function() {
    if (!state.files.length) { toast('Nejdřív nahraj PDF.', true); return; }
    if (!state.certFile) { toast('Vyber PFX/P12 certifikát.', true); return; }
    if (typeof window.convertPdfToPdfa !== 'function') {
      toast('PDF/A engine z hlavního Toolboxu není dostupný. Obnov stránku přes Ctrl+F5.', true);
      return;
    }

    const profile = document.getElementById('auth-profile').value;
    const tsa = document.getElementById('auth-tsa').value.trim();
    if (profile==='bt' && !tsa) { toast('Pro PAdES B-T zadej RFC 3161 TSA server.', true); return; }
    const bridge = await checkAuthorizationBridge(true);
    if (!bridge) { toast('AuthorizationBridge neběží.', true); return; }

    persistOverlay();
    const btn = document.getElementById('auth-sign-btn');
    btn.disabled = true;

    try {
      // DŮLEŽITÉ: PDF/A konverze musí proběhnout PŘED kryptografickým podpisem.
      // Převod podepsaného PDF přes Ghostscript by existující podpis zneplatnil.
      const docs = [];
      const convertedFiles = [];

      for (let i=0;i<state.files.length;i++) {
        const rec = state.files[i];
        rec.status = 'converting';
        renderFileList();
        btn.textContent = 'PDF/A-3b ' + (i+1) + '/' + state.files.length + '…';

        await new Promise(resolve => setTimeout(resolve, 20));
        const sourceBytes = new Uint8Array(await rec.file.arrayBuffer());
        const pdfaBytes = await window.convertPdfToPdfa(sourceBytes, '3');
        const outputName = earOutputName(rec.name);
        const converted = new File([pdfaBytes], outputName, {
          type:'application/pdf',
          lastModified:Date.now()
        });

        docs.push({
          index:i,
          name:rec.name,
          output_name:outputName,
          pdfa:'3b',
          placement:await absolutePlacement(rec)
        });
        convertedFiles.push(converted);
        rec.status = 'ready';
        renderFileList();
      }

      btn.textContent = 'Podepisuji PDF/A-3b…';
      const signTime = new Intl.DateTimeFormat('cs-CZ',{dateStyle:'short',timeStyle:'short'}).format(new Date());
      const appearanceFile = await buildCompositeStamp(signTime);
      const meta = {
        profile,
        tsa_url: tsa,
        reason: document.getElementById('auth-reason').value.trim(),
        location: document.getElementById('auth-location').value.trim(),
        contact: document.getElementById('auth-contact').value.trim(),
        output_standard:'PDF/A-3b',
        documents: docs
      };

      const fd = new FormData();
      fd.append('certificate', state.certFile, state.certFile.name);
      fd.append('password', document.getElementById('auth-cert-pass').value || '');
      fd.append('metadata', JSON.stringify(meta));
      if (appearanceFile) fd.append('stamp', appearanceFile, appearanceFile.name);
      convertedFiles.forEach((file, i) => fd.append('pdfs', file, docs[i].output_name));

      const resp = await bridgeFetch('/sign-batch', {method:'POST', body:fd}, 240000);
      if (!resp.ok) {
        let msg='Podepisování selhalo.';
        try { const j=await resp.json(); msg=j.error || j.detail || msg; } catch {}
        throw new Error(msg);
      }

      const blob = await resp.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href=url;
      a.download='autorizovane_PDF-A-3b_EAR_'+new Date().toISOString().slice(0,10)+'.zip';
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(()=>URL.revokeObjectURL(url),4000);

      state.files.forEach(r=>r.status='signed');
      renderFileList();
      toast('Hotovo — PDF/A-3b dokumenty s příponou _EAR byly podepsané a stažené v ZIPu.');
    } catch (e) {
      state.files.forEach(r=>{ if(r.status!=='signed') r.status='error'; });
      renderFileList();
      toast(e.message || String(e), true);
    } finally {
      btn.disabled = false;
      btn.textContent = 'PDF/A-3b + podepsat + stáhnout ZIP';
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

    document.getElementById('auth-cert-file').addEventListener('change', e => {
      state.certFile = e.target.files?.[0] || null; state.certInfo=null;
      const box=document.getElementById('auth-cert-info'); box.className='auth-cert-card'; box.textContent=state.certFile?'Vybráno: '+state.certFile.name+'. Klikni na Ověřit certifikát.':'Certifikát zatím nebyl načten.';
    });
    document.getElementById('auth-stamp-file').addEventListener('change', async e => {
      const source = e.target.files?.[0] || null;
      state.stampFile = null;
      state.stampSourceName = source?.name || '';
      const info = document.getElementById('auth-stamp-info');
      if (!source) {
        info.textContent = 'U PDF se jako grafika razítka použije první strana.';
        renderStampPreview();
        return;
      }
      try {
        info.textContent = /\.pdf$/i.test(source.name) || source.type==='application/pdf' ? 'Převádím 1. stranu PDF razítka…' : 'Načítám grafiku razítka…';
        state.stampFile = (/\.pdf$/i.test(source.name) || source.type==='application/pdf') ? await pdfStampToPng(source) : source;
        info.textContent = 'Použije se: '+source.name + ((/\.pdf$/i.test(source.name) || source.type==='application/pdf') ? ' · 1. strana PDF' : '');
        await renderStampPreview();
      } catch(err) {
        state.stampFile = null;
        info.textContent = 'Chyba: '+(err.message || err);
        toast('Razítko se nepodařilo načíst.', true);
      }
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

  window.initAuthorizationApp = function() {
    if (!state.initialized) {
      state.initialized = true;
      authProfileChanged();
      authStampOptionsChanged();
      checkAuthorizationBridge(true);
    }
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