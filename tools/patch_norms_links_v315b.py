from pathlib import Path
import re

INDEX=Path('index.html')
ENGINE=Path('norms_engine_v314y.js')

# ---- index/version/cache/changelog ----
s=INDEX.read_text(encoding='utf-8-sig')
s=re.sub(r'(<div class="app-version" id="app-version">)V3\.15a(</div>)',r'\1V3.15b\2',s,count=1)
s=s.replace('; 20-20-TOOLBOX V3.15a\\n;','; 20-20-TOOLBOX V3.15b\\n;',1)
s=s.replace('norms_data_v314y.js?v=315a','norms_data_v314y.js?v=315b')
s=s.replace('norms_engine_v314y.js?v=315a','norms_engine_v314y.js?v=315b')
s=s.replace('<span class="whatsnew-ver">V3.15a</span>','<span class="whatsnew-ver">V3.15b</span>',1)
s=s.replace("const VERSION='V3.15a', KEY='20-20-toolbox-whatsnew-seen';","const VERSION='V3.15b', KEY='20-20-toolbox-whatsnew-seen';",1)
new_body='''<div class="whatsnew-body">
      <div class="whatsnew-item"><strong>Normy — celá karta je teď odkaz</strong><span>Zmizelo samostatné tlačítko „Otevřít zdroj“. Kliknutí kamkoli na kartu otevře zdrojovou stránku.</span></div>
      <div class="whatsnew-item"><strong>Přesnější skok na konkrétní ustanovení</strong><span>U právních předpisů se nyní odkaz skládá i z odstavce, například § 39 odst. 1 otevře přímo #p39-1 místo začátku celé vyhlášky.</span></div>
      <div class="whatsnew-item"><strong>Přílohy a tabulky</strong><span>Pokud záznam pochází z přílohy nebo tabulky, Toolbox používá cílený textový odkaz na danou část zdroje, pokud jej prohlížeč podporuje.</span></div>
      <div class="whatsnew-item"><strong>Interiérové standardy</strong><span>Vyhledávání zůstává nahoře a prohledává všechny aktuálně zařazené rozměry, odstupy, výšky, nábytek, sanitu, kuchyně, kanceláře a další kategorie.</span></div>
    </div>'''
s=re.sub(r'<div class="whatsnew-body">.*?</div>\s*<div class="whatsnew-actions">',new_body+'\n    <div class="whatsnew-actions">',s,count=1,flags=re.S)
INDEX.write_text(s,encoding='utf-8')

# ---- engine: exact paragraph links + whole-card links ----
e=ENGINE.read_text(encoding='utf-8-sig')
old_start=e.index('function normSourceUrl(x){')
old_end=e.index('\nfunction renderNormBrowser()',old_start)
replacement=r'''function normBaseUrl(x){
  const src=String(x.source||'');
  if(src.includes('146/2024'))return 'https://www.zakonyprolidi.cz/cs/2024-146';
  if(src.includes('131/2024'))return 'https://www.zakonyprolidi.cz/cs/2024-131';
  return String(x.url||'');
}
function normSourceUrl(x){
  const base=normBaseUrl(x), sec=String(x.section||'');
  if(!base)return 'https://csnonline.agentura-cas.cz/';

  // ZakonyProLidi uses anchors like #p39-1 for § 39 odst. 1.
  if(base.includes('zakonyprolidi.cz')){
    const p=sec.match(/§\s*(\d+)(?:\s*odst\.?\s*(\d+))?/i);
    if(p)return base+'#p'+p[1]+(p[2]?'-'+p[2]:'');

    // Annex/table records do not always expose stable paragraph IDs.
    // Use a Scroll-To-Text fragment to land on the most specific visible text.
    const annex=sec.match(/Příloha\s*č\.?\s*(\d+)/i);
    if(annex){
      const needle=(String(x.value||'').trim()||String(x.title||'').trim()||('Příloha č. '+annex[1])).replace(/\s+/g,' ');
      return base+'#:~:text='+encodeURIComponent(needle);
    }
  }
  return base;
}
function openNormSource(id){
  const x=(window.TOOLBOX_NORMS_V314Y||[]).find(n=>n.id===id);
  if(!x)return;
  window.open(normSourceUrl(x),'_blank','noopener');
}
function normCard(x,full=false){
  return `<div class="${full?'ny-entry':'ny-result'}" id="ny-${esc(x.id)}" role="link" tabindex="0" onclick="openNormSource('${esc(x.id)}')" onkeydown="if(event.key==='Enter'||event.key===' '){event.preventDefault();openNormSource('${esc(x.id)}')}" title="Otevřít přesné místo ve zdroji"><div class="ny-entry-top"><div><h3>${esc(x.title)}</h3><div class="ny-meta">${esc(x.source)} · ${esc(x.section||'')}</div>${x.value?`<div class="ny-value">${esc(x.value)}</div>`:''}</div></div><div class="ny-badges"><span class="ny-badge ${badgeType(x)}">${esc(x.type)}</span><span class="ny-badge">${esc(NCATS[x.cat]?.[0]||x.cat)}</span></div><p class="ny-note">${esc(x.summary)}</p></div>`;
}'''
e=e[:old_start]+replacement+e[old_end:]
# Make full cards visibly clickable as one control.
e=e.replace('.ny-entry,.iy-card{border:1px solid var(--border);background:#fff;border-radius:9px;padding:12px;margin:8px 0;scroll-margin-top:16px;transition:.3s}', '.ny-entry,.iy-card{border:1px solid var(--border);background:#fff;border-radius:9px;padding:12px;margin:8px 0;scroll-margin-top:16px;transition:.3s}.ny-entry{cursor:pointer}.ny-entry:hover{border-color:#a1a1aa;background:#fafafa}',1)
ENGINE.write_text(e,encoding='utf-8')

# safety checks
s=INDEX.read_text(encoding='utf-8')
e=ENGINE.read_text(encoding='utf-8')
assert 'V3.15b' in s
assert "const VERSION='V3.15b'" in s
assert 'norms_engine_v314y.js?v=315b' in s
assert "#p'+p[1]+(p[2]?'-'+p[2]:'')" in e
assert 'Otevřít zdroj ↗' not in e
assert 'title="Otevřít přesné místo ve zdroji"' in e
print('V3.15b deep links + changelog applied')
