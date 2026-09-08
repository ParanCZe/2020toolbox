from pathlib import Path
import re

P=Path('index.html')
s=P.read_text(encoding='utf-8-sig')

# App version only. Bridge remains 3.14v.
s=s.replace('>V3.14w</div>', '>V3.14x</div>', 1)
s=s.replace('; 20-20-TOOLBOX V3.14w\\n;', '; 20-20-TOOLBOX V3.14x\\n;', 1)

css=r'''

/* NORMY — V3.14x BETA */
.norms-hero{margin:14px 0 16px;padding:16px;border:1px solid var(--border);border-radius:10px;background:#fafafa}
.norms-searchbar{display:grid;grid-template-columns:1fr auto;gap:8px}.norms-searchbar input{min-height:44px;width:100%;font-size:14px;background:#fff}.norms-searchbar button{min-width:110px}
.norms-search-hint{font-size:10px;color:var(--muted);margin-top:7px;line-height:1.45}
.norms-category-grid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:9px;margin:14px 0 18px}.norms-category{border:1px solid var(--border);background:#fff;border-radius:9px;padding:11px;text-align:left;cursor:pointer;min-height:76px;transition:.15s}.norms-category:hover,.norms-category.active{background:#fffef3;border-color:#d4cc5d}.norms-category b{display:block;font-size:11px;margin-bottom:4px}.norms-category span{font-size:9px;color:var(--muted);line-height:1.35}
.norms-toolbar{display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap;margin:8px 0 10px}.norms-toolbar b{font:normal 12px 'Antarctican Mono',monospace}.norms-toolbar span{font-size:10px;color:var(--muted)}
.norms-results{display:grid;gap:8px}.norms-result{border:1px solid var(--border);border-radius:9px;background:#fff;padding:11px 12px;cursor:pointer;text-align:left}.norms-result:hover{border-color:#a1a1aa;background:#fafafa}.norms-result strong{display:block;font-size:12px;margin-bottom:4px}.norms-result .meta{font-size:9px;color:var(--muted);margin-bottom:5px}.norms-result p{margin:0;font-size:10px;line-height:1.5}.norms-result mark{background:#f7f197;padding:0 1px}
.norms-browser{margin-top:18px;border-top:1px solid var(--border);padding-top:14px}.norms-section{margin:0 0 18px;scroll-margin-top:16px}.norms-section h2{font:normal 14px 'Antarctican Mono',monospace;margin:0 0 8px}.norms-entry{border:1px solid var(--border);border-radius:9px;background:#fff;padding:12px;margin:8px 0;scroll-margin-top:18px;transition:.35s}.norms-entry.flash{box-shadow:0 0 0 3px rgba(247,241,151,.9);background:#fffef3}.norms-entry-head{display:flex;align-items:flex-start;justify-content:space-between;gap:10px}.norms-entry h3{font-size:12px;margin:0 0 4px}.norms-entry .norms-source{font-size:9px;color:var(--muted);line-height:1.4}.norms-entry .norms-summary{font-size:10px;line-height:1.5;margin-top:7px}.norms-entry .norms-tags{display:flex;gap:4px;flex-wrap:wrap;margin-top:8px}.norms-tag{font-size:8px;border:1px solid #d4d4d8;background:#f4f4f5;color:#71717a;border-radius:999px;padding:2px 5px}.norms-link{font-size:9px;color:#18181b;text-decoration:none;border:1px solid var(--border);border-radius:6px;padding:5px 7px;background:#fafafa;white-space:nowrap}.norms-link:hover{background:#f7f197}.norms-empty{padding:18px;border:1px dashed #cbd5e1;border-radius:9px;color:var(--muted);font-size:11px;text-align:center}.norms-disclaimer{margin-top:14px;padding:10px 12px;border:1px solid #fde68a;background:#fffbeb;color:#92400e;border-radius:8px;font-size:10px;line-height:1.5}
@media(max-width:950px){.norms-category-grid{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:560px){.norms-searchbar{grid-template-columns:1fr}.norms-category-grid{grid-template-columns:1fr}}
'''
if '/* NORMY — V3.14x BETA */' not in s:
    s=s.replace('</style>',css+'\n</style>',1)

old_tile='<div class="tile" onclick="openTool(\'3dmodels\')"><b>3D knihovna výrobků <small class="menu-status">BETA</small></b><span>Reálné produkty, BIM/CAD odkazy a živé 3D náhledy</span></div>'
new_tile=old_tile+'\n        <div class="tile" onclick="openTool(\'norms\'); initNormsApp()"><b>Normy <small class="menu-status">BETA</small></b><span>Interiér, urbanismus, projektování, dokumentace a stavební požadavky</span></div>'
if 'openTool(\'norms\')' not in s:
    if old_tile not in s: raise SystemExit('3D models tile anchor not found')
    s=s.replace(old_tile,new_tile,1)
    # Mark beta row so it can have 4 columns without affecting stable row.
    beta_anchor='<div class="menu-app-row">\n        <div class="tile" onclick="openTool(\'docs\'); openDocsSection(\'preflight\')">'
    if beta_anchor in s:
        s=s.replace(beta_anchor,'<div class="menu-app-row beta">\n        <div class="tile" onclick="openTool(\'docs\'); openDocsSection(\'preflight\')">',1)
    s=s.replace('.menu-app-row{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px}', '.menu-app-row{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px}.menu-app-row.beta{grid-template-columns:repeat(4,minmax(0,1fr))}',1)

html=r'''

  <div id="tool-norms" class="tool-view">
    <button class="back-btn" onclick="closeTool()">← Zpět do menu</button>
    <h1>Normy <small class="menu-status">BETA</small></h1>
    <div class="muted">Rychlé hledání požadavků pro interiér, urbanismus, běžné projektování, dokumentaci a stavebnictví.</div>

    <div class="norms-hero">
      <div class="norms-searchbar">
        <input id="norms-smart-search" type="search" placeholder="Co hledáš? např. šířka komunikace, chodba, dveře, dokumentace…" onkeydown="if(event.key==='Enter')searchNorms()">
        <button class="action" type="button" onclick="searchNorms()">Hledat ve všem</button>
      </div>
      <div class="norms-search-hint">Hledání prochází názvy, témata, klíčová slova, zdroj i stručný obsah všech zařazených záznamů. Kliknutí na výsledek tě hodí přímo na konkrétní položku níže.</div>
    </div>

    <div class="norms-category-grid">
      <button class="norms-category" data-norm-cat="interier" onclick="openNormCategory('interier')"><b>Interiér</b><span>dispozice, dveře, chodby, schodiště, přístupnost</span></button>
      <button class="norms-category" data-norm-cat="urbanismus" onclick="openNormCategory('urbanismus')"><b>Urbanismus</b><span>veřejná prostranství, komunikace, odstupy, parkování</span></button>
      <button class="norms-category" data-norm-cat="projekt" onclick="openNormCategory('projekt')"><b>Běžné projektové normy</b><span>obecné technické a prostorové požadavky</span></button>
      <button class="norms-category" data-norm-cat="dokumentace" onclick="openNormCategory('dokumentace')"><b>Dokumentace</b><span>povolení, provádění, pasport, odstranění stavby</span></button>
      <button class="norms-category" data-norm-cat="stavebni" onclick="openNormCategory('stavebni')"><b>Stavební normy</b><span>bezpečnost, konstrukce, povrchy a technické požadavky</span></button>
    </div>

    <div class="norms-toolbar"><b id="norms-results-title">VŠECHNY ZAŘAZENÉ POŽADAVKY</b><span id="norms-results-count"></span></div>
    <div id="norms-search-results" class="norms-results"></div>
    <div id="norms-browser" class="norms-browser"></div>
    <div class="norms-disclaimer"><b>BETA:</b> Toolbox zde zobrazuje krátké pracovní výtahy a odkazy na zdroje. Nejde o náhradu úplného znění ČSN ani právního předpisu. Konkrétní požadavek před použitím v projektu vždy ověř v aktuálním znění zdroje.</div>
  </div>
'''
if 'id="tool-norms"' not in s:
    anchor='  <div id="tool-pdfa" class="tool-view">'
    if anchor not in s: raise SystemExit('PDF/A tool anchor not found')
    s=s.replace(anchor,html+'\n'+anchor,1)

js=r'''

// NORMY V3.14x — vyhledávání + skok na konkrétní záznam.
const NORMS_DB=[
  {id:'u-verejne-prostranstvi-sirka',cat:'urbanismus',title:'Šířka veřejného prostranství s pozemní komunikací',source:'Vyhláška č. 146/2024 Sb.',section:'§ 9 odst. 1',summary:'Pro veřejné prostranství s komunikací vedoucí k bytovému domu vyhláška stanoví nejmenší šířku 12 m, při jednosměrném provozu 10,5 m. Pro nově vymezované veřejné prostranství s komunikací k rodinnému domu 8 m, při jednosměrném provozu 6,5 m.',keywords:['šířka komunikace','komunikace','veřejné prostranství','rodinný dům','bytový dům','jednosměrný provoz','ulice'],url:'https://www.zakonyprolidi.cz/cs/2024-146'},
  {id:'i-vnitrni-komunikace-dvere',cat:'interier',title:'Dveře a hlavní vnitřní komunikace',source:'Vyhláška č. 146/2024 Sb.',section:'§ 39',summary:'Hlavní vstupní dveře do bytů, pobytových místností a vnitřních komunikací mají mít světlou průchodnou šířku nejméně 0,8 m. Chodba společných prostor bytového domu má mít nejmenší průchodnou šířku 1,2 m; další požadavky se liší podle druhu stavby.',keywords:['dveře','šířka dveří','chodba','šířka chodby','vnitřní komunikace','průchodná šířka','interiér'],url:'https://www.zakonyprolidi.cz/cs/2024-146'},
  {id:'s-protiskluznost',cat:'stavebni',title:'Protiskluznost podlah a pochozích ploch',source:'Vyhláška č. 146/2024 Sb.',section:'§ 35 a příloha č. 5',summary:'Pochozí plochy musí mít protiskluzovou úpravu. Vyhláška odkazuje na konkrétní parametry v příloze č. 5 a zvláštní požadavky na přístupnost.',keywords:['protiskluznost','podlaha','pochozí plocha','rampa','povrch','bezpečnost'],url:'https://www.zakonyprolidi.cz/cs/2024-146'},
  {id:'p-mechanicka-odolnost',cat:'projekt',title:'Mechanická odolnost a stabilita stavby',source:'Vyhláška č. 146/2024 Sb.',section:'§ 16',summary:'Stavba a její konstrukce musí být navrženy a provedeny tak, aby odolaly předvídatelným vlivům; vyhláška zároveň odkazuje na normy uvedené ve své příloze č. 14.',keywords:['statika','stabilita','mechanická odolnost','konstrukce','zatížení','projektování'],url:'https://www.zakonyprolidi.cz/cs/2024-146'},
  {id:'d-obsah-dokumentace',cat:'dokumentace',title:'Obsah a druhy dokumentace staveb',source:'Vyhláška č. 131/2024 Sb.',section:'§ 1–10 a přílohy',summary:'Vyhláška upravuje obsah dokumentace pro povolení stavby, rámcové povolení, změnu využití území, provádění stavby, odstranění stavby, pasport stavby a stavební deník / jednoduchý záznam.',keywords:['dokumentace','povolení stavby','provádění stavby','DPS','pasport','odstranění stavby','stavební deník'],url:'https://www.zakonyprolidi.cz/cs/2024-131'}
];
const NORM_CAT_LABELS={interier:'Interiér',urbanismus:'Urbanismus',projekt:'Běžné projektové normy',dokumentace:'Dokumentace',stavebni:'Stavební normy'};
let normsActiveCategory='';
function normFold(v){return String(v||'').toLocaleLowerCase('cs-CZ').normalize('NFD').replace(/[\u0300-\u036f]/g,'')}
function normHay(n){return normFold([n.title,n.source,n.section,n.summary,...(n.keywords||[])].join(' '))}
function normEscape(v){return escapeHtml(String(v||''))}
function initNormsApp(){renderNormBrowser();renderNormResults(NORMS_DB,'VŠECHNY ZAŘAZENÉ POŽADAVKY');setTimeout(()=>document.getElementById('norms-smart-search')?.focus(),80)}
function openNormCategory(cat){
  normsActiveCategory=cat;
  document.querySelectorAll('.norms-category').forEach(x=>x.classList.toggle('active',x.dataset.normCat===cat));
  const list=NORMS_DB.filter(x=>x.cat===cat);renderNormResults(list,(NORM_CAT_LABELS[cat]||cat).toUpperCase());
  const sec=document.getElementById('norms-sec-'+cat);if(sec)sec.scrollIntoView({behavior:'smooth',block:'start'});
}
function searchNorms(){
  const input=document.getElementById('norms-smart-search'),q=(input?.value||'').trim(),fq=normFold(q);
  document.querySelectorAll('.norms-category').forEach(x=>x.classList.remove('active'));normsActiveCategory='';
  if(!fq){renderNormResults(NORMS_DB,'VŠECHNY ZAŘAZENÉ POŽADAVKY');return}
  const tokens=fq.split(/\s+/).filter(Boolean);
  const scored=NORMS_DB.map(n=>{const h=normHay(n),title=normFold(n.title),keys=normFold((n.keywords||[]).join(' '));let score=0;for(const t of tokens){if(title.includes(t))score+=5;if(keys.includes(t))score+=4;if(h.includes(t))score+=1}if(h.includes(fq))score+=8;return {n,score}}).filter(x=>x.score>0).sort((a,b)=>b.score-a.score).map(x=>x.n);
  renderNormResults(scored,`VÝSLEDKY PRO „${q.toUpperCase()}“`,q);
}
function normHighlight(text,q){let out=normEscape(text);if(!q)return out;for(const raw of String(q).split(/\s+/).filter(x=>x.length>1)){const safe=raw.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');try{out=out.replace(new RegExp('('+safe+')','ig'),'<mark>$1</mark>')}catch{}}return out}
function renderNormResults(list,title,q=''){
  const box=document.getElementById('norms-search-results'),tt=document.getElementById('norms-results-title'),ct=document.getElementById('norms-results-count');if(!box)return;
  if(tt)tt.textContent=title;if(ct)ct.textContent=`${list.length} výsledků`;
  if(!list.length){box.innerHTML='<div class="norms-empty">Nic jsem nenašel. Zkus kratší výraz nebo jiné slovo.</div>';return}
  box.innerHTML=list.map(n=>`<button class="norms-result" type="button" onclick="jumpToNorm('${n.id}')"><strong>${normHighlight(n.title,q)}</strong><div class="meta">${normEscape(NORM_CAT_LABELS[n.cat])} · ${normEscape(n.source)} · ${normEscape(n.section)}</div><p>${normHighlight(n.summary,q)}</p></button>`).join('');
}
function renderNormBrowser(){
  const box=document.getElementById('norms-browser');if(!box)return;
  box.innerHTML=Object.keys(NORM_CAT_LABELS).map(cat=>{const arr=NORMS_DB.filter(n=>n.cat===cat);return `<section class="norms-section" id="norms-sec-${cat}"><h2>${normEscape(NORM_CAT_LABELS[cat])}</h2>${arr.map(n=>`<article class="norms-entry" id="norm-${n.id}"><div class="norms-entry-head"><div><h3>${normEscape(n.title)}</h3><div class="norms-source">${normEscape(n.source)} · ${normEscape(n.section)}</div></div><a class="norms-link" href="${n.url}" target="_blank" rel="noopener noreferrer">Otevřít zdroj ↗</a></div><div class="norms-summary">${normEscape(n.summary)}</div><div class="norms-tags">${(n.keywords||[]).map(k=>`<span class="norms-tag">${normEscape(k)}</span>`).join('')}</div></article>`).join('')}</section>`}).join('');
}
function jumpToNorm(id){const el=document.getElementById('norm-'+id);if(!el)return;el.scrollIntoView({behavior:'smooth',block:'center'});el.classList.add('flash');setTimeout(()=>el.classList.remove('flash'),1800)}
'''
if '// NORMY V3.14x' not in s:
    anchor="document.addEventListener('DOMContentLoaded',()=>setTimeout(()=>check3DPrintPrusaBridge(true),700));"
    if anchor not in s: raise SystemExit('DOMContentLoaded anchor not found')
    s=s.replace(anchor,js+'\n\n'+anchor,1)

checks=['V3.14x','id="tool-norms"','openTool(\'norms\')','const NORMS_DB=','function searchNorms()','Šířka veřejného prostranství']
for c in checks:
    if c not in s: raise SystemExit('Missing '+c)
P.write_text(s,encoding='utf-8')
print('V3.14x norms app patch applied')
