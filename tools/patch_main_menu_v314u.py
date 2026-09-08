from pathlib import Path
import re

p = Path('index.html')
h = p.read_text(encoding='utf-8-sig')

# Web app version only. PrusaBridge remains 3.14s.
h = h.replace('<div class="app-version" id="app-version">V3.14t</div>', '<div class="app-version" id="app-version">V3.14u</div>')
h = h.replace('<div class="app-version" id="app-version">V3.14s</div>', '<div class="app-version" id="app-version">V3.14u</div>')

# Main-menu layout styles.
css_marker = '/* HLAVNI MENU — V3.14u: stabilni / beta + vyuziti dat */'
if css_marker not in h:
    anchor = ".menu-status{display:inline-block;margin-left:7px;padding:1px 5px;border:1px solid #d4d4d8;border-radius:999px;background:#f4f4f5;color:#71717a;font:500 9px/1.45 system-ui,Segoe UI,sans-serif;letter-spacing:.45px;vertical-align:2px;text-transform:uppercase}\n"
    css = r'''

/* HLAVNI MENU — V3.14u: stabilni / beta + vyuziti dat */
.menu-app-groups{display:flex;flex-direction:column;gap:16px}
.menu-app-row{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px}
.menu-section-divider{height:1px;background:var(--border);margin:1cm 0}
.session-data-overview{margin-top:0!important;border-top:0!important;padding-top:0!important}
.session-data-grid{grid-template-columns:repeat(3,minmax(0,1fr));gap:12px;margin-top:12px}
.session-data-card{min-height:92px;display:flex;flex-direction:column;justify-content:center}
.session-data-card .session-data-mb{font-family:'Antarctican Mono',monospace;font-size:20px;line-height:1.15;color:var(--text);margin:1px 0 4px}
.session-data-card .session-data-count{font-size:10px;color:var(--muted)}
@media(max-width:900px){.menu-app-row,.session-data-grid{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media(max-width:580px){.menu-app-row,.session-data-grid{grid-template-columns:1fr}.menu-section-divider{margin:.7cm 0}}
'''
    if anchor not in h:
        raise SystemExit('CSS anchor not found')
    h = h.replace(anchor, anchor + css, 1)

old_menu = '''    <div class="grid">
      <div class="tile" onclick="openTool('pdfa')"><b>Konverze do PDF/A</b><span>Standardy 1b, 2b, 3b + hromadný ZIP</span></div>
      <div class="tile" onclick="openPanelProjects()"><b>Prezentační nástroj</b><span>Vytvářejte prezentace v pár kliknutích</span></div>
      <div class="tile" onclick="openTool('docs'); openDocsSection('preflight')"><b>Dokumentační nástroje <small class="menu-status">BETA</small></b><span>Pre-flight, seznam výkresů, přejmenování a porovnání PDF</span></div>
      <div class="tile" onclick="openTool('designcheck')"><b>Kontrola návrhu <small class="menu-status">BETA</small></b><span>Audit výkresů, místností, schodišť a vzájemné konzistence PDF</span></div>
      <div class="tile" onclick="openTool('3dprint')"><b>3D tisk <small class="menu-status">BETA</small></b><span>Prusa MK3S, slicerové vrstvy, odhad a export G-code</span></div>
      <div class="tile" onclick="openTool('3dmodels')"><b>3D knihovna výrobků <small class="menu-status">BETA</small></b><span>Reálné produkty, BIM/CAD odkazy a živé 3D náhledy</span></div>
    </div>
    <div class="session-data-overview">
      <div class="storage-overview-head"><b>NAČTENÁ DATA V TÉTO RELACI</b><span class="muted" style="margin:0;font-size:11px">Přehled toho, co je právě načtené v jednotlivých částech aplikace.</span></div>
      <div id="session-data-overview" class="session-data-grid"></div>
    </div>'''

new_menu = '''    <div class="menu-app-groups">
      <div class="menu-app-row">
        <div class="tile" onclick="openTool('pdfa')"><b>Konverze do PDF/A</b><span>Standardy 1b, 2b, 3b + hromadný ZIP</span></div>
        <div class="tile" onclick="openPanelProjects()"><b>Prezentační nástroj</b><span>Vytvářejte prezentace v pár kliknutích</span></div>
        <div class="tile" onclick="openTool('3dprint')"><b>3D tisk</b><span>Prusa MK3S, slicerové vrstvy, odhad a export G-code</span></div>
      </div>
      <div class="menu-app-row">
        <div class="tile" onclick="openTool('docs'); openDocsSection('preflight')"><b>Dokumentační nástroje <small class="menu-status">BETA</small></b><span>Pre-flight, seznam výkresů, přejmenování a porovnání PDF</span></div>
        <div class="tile" onclick="openTool('designcheck')"><b>Kontrola návrhu <small class="menu-status">BETA</small></b><span>Audit výkresů, místností, schodišť a vzájemné konzistence PDF</span></div>
        <div class="tile" onclick="openTool('3dmodels')"><b>3D knihovna výrobků <small class="menu-status">BETA</small></b><span>Reálné produkty, BIM/CAD odkazy a živé 3D náhledy</span></div>
      </div>
    </div>
    <div class="menu-section-divider" aria-hidden="true"></div>
    <div class="session-data-overview">
      <div class="storage-overview-head"><b>AKTUÁLNĚ VYUŽITÁ DATA APLIKACEMI</b><span class="muted" style="margin:0;font-size:11px">Kolik lokálně načtených souborových dat má právě každá část Toolboxu. Nejde o celkovou RAM prohlížeče.</span></div>
      <div id="session-data-overview" class="session-data-grid"></div>
    </div>'''

if old_menu in h:
    h = h.replace(old_menu, new_menu, 1)
elif 'class="menu-app-groups"' not in h:
    raise SystemExit('Main menu block not found')

# 3D tisk is no longer marked beta, both in menu and inside the tool.
h = h.replace('<h1>3D tisk <small class="menu-status">BETA</small></h1>', '<h1>3D tisk</h1>')

# Aggregate loaded file data by the six top-level applications, not by every subtool.
new_session = r'''function sessionDataSections(){return [
  {title:'Konverze do PDF/A',files:filesData.pdfa||[]},
  {title:'Prezentační nástroj',files:filesData.panel||[]},
  {title:'3D tisk',files:print3dState.file?[print3dState.file]:[]},
  {title:'Dokumentační nástroje',files:[...(docsData.preflight||[]),...(docsData.drawinglist||[]),...(docsData.renamer||[]),docsData.compareA,docsData.compareB].filter(Boolean)},
  {title:'Kontrola návrhu',files:designAuditState.file?[designAuditState.file]:[]},
  {title:'3D knihovna výrobků',files:[]}
];}
function uniqueSessionFiles(files){
  const seen=new Set();return (files||[]).filter(f=>{if(!f)return false;const key=[f.name||'',f.size||0,f.lastModified||0].join('|');if(seen.has(key))return false;seen.add(key);return true});
}
function formatSessionMb(bytes){return ((Number(bytes)||0)/(1024*1024)).toFixed(2).replace('.',',')+' MB';}
function renderSessionDataOverview(){
  const el=document.getElementById('session-data-overview');if(!el)return;const sections=sessionDataSections();
  el.innerHTML=sections.map(x=>{const files=uniqueSessionFiles(x.files),count=files.length,size=fileListSize(files);return `<div class="session-data-card"><b>${escapeHtml(x.title)}</b><div class="session-data-mb">${formatSessionMb(size)}</div><div class="session-data-count">${count?`${count} ${count===1?'soubor':'souborů'} právě načteno`:'žádná lokální data'}</div></div>`}).join('');
}
'''

pattern = r'function sessionDataSections\(\)\{return \[.*?\nfunction renderSessionDataOverview\(\)\{.*?\n\}\n(?=\nfunction openTool\(name\))'
if re.search(pattern, h, flags=re.S):
    h = re.sub(pattern, new_session.rstrip(), h, count=1, flags=re.S)
elif 'function formatSessionMb' not in h:
    raise SystemExit('Session overview function block not found')

p.write_text(h, encoding='utf-8')
