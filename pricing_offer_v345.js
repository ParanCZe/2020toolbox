(()=>{
  const LEGACY_STORE='toolbox.pricingOffer.v345';
  const PROJECTS_STORE='toolbox.pricingOffer.projects.v346';
  const ACTIVE_STORE='toolbox.pricingOffer.active.v346';
  const template=[
    {name:'STUDIE',mode:'hours',rate:1400,items:[['zaměření, průzkumy, dokumentace, zadání',16],['dispoziční řešení, varianty, zázemí a výdej, konzum.',40],['vizualizace, tvorba modelu',40]]},
    {name:'DSP',mode:'hours',rate:1200,items:[['gastro projekt, spolupráce na tvorbě',16],['revize a zpracování návrhu technologií TZB',10],['PBŘ a koordinace',10],['tvorba dokumentace pro DSP, PDF…',80],['koordinace profesí',10]]},
    {name:'PROVÁDĚČKA',mode:'hours',rate:1000,items:[['řešení interiéru - materiály, barevnost, detaily, vzorky',16],['povrchy',20],['vývodový plán',10],['rozkres prvků interiéru',80],['výběr mobiliáře, uměleckých děl…',10],['exteriér - označení, stínění',10]]},
    {name:'AD',mode:'hours',rate:1600,items:[['čas na kontrolních dnech po dobu realizace',40],['čas na úpravě výkresů po dobu realizace',40]]},
    {name:'PROFESE',mode:'fixed',items:[['ZTI',60000],['VZT',60000],['CHL, VYTÁP',60000],['ELE SILNO',60000],['ELE SLABO',60000],['EPS',60000],['PBŘ',60000],['STATIKA',60000],['SHZ',60000],['GASTRO',60000],['TECHNOLOGICKÉ CHLAZENÍ',60000]]},
    {name:'INŽENÝRING',mode:'fixed',items:[['DSP',20000],['KOLAUDACE',40000]]}
  ];
  let state=null,activeId=null,projects=[];
  const money=n=>new Intl.NumberFormat('cs-CZ',{style:'currency',currency:'CZK',maximumFractionDigits:0}).format(Number(n)||0);
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const clone=x=>JSON.parse(JSON.stringify(x));
  function fresh(){return {project:'',client:'',note:'',groups:template.map((g,gi)=>({id:'g'+gi,name:g.name,mode:g.mode,rate:g.rate||0,items:g.items.map((x,i)=>({id:`g${gi}i${i}`,on:true,name:x[0],qty:g.mode==='hours'?x[1]:1,price:g.mode==='hours'?0:x[1]}))}))}}
  function now(){return Date.now()}
  function loadProjects(){
    try{projects=JSON.parse(localStorage.getItem(PROJECTS_STORE)||'[]')||[]}catch(_){projects=[]}
    if(!projects.length){
      let legacy=null;try{legacy=JSON.parse(localStorage.getItem(LEGACY_STORE)||'null')}catch(_){legacy=null}
      if(legacy){projects=[{id:'p'+now(),name:(legacy.project||'Rozpracovaná nabídka').trim()||'Rozpracovaná nabídka',createdAt:now(),updatedAt:now(),data:legacy}];localStorage.setItem(PROJECTS_STORE,JSON.stringify(projects))}
    }
    activeId=localStorage.getItem(ACTIVE_STORE)||null;
    if(activeId&&!projects.some(p=>p.id===activeId))activeId=null;
  }
  function persistProjects(){localStorage.setItem(PROJECTS_STORE,JSON.stringify(projects))}
  function save(){
    if(!activeId||!state)return;
    const p=projects.find(x=>x.id===activeId);if(!p)return;
    p.data=clone(state);p.name=(state.project||p.name||'Bez názvu').trim()||'Bez názvu';p.updatedAt=now();persistProjects();
  }
  function openProject(id){const p=projects.find(x=>x.id===id);if(!p)return;activeId=id;localStorage.setItem(ACTIVE_STORE,id);state=clone(p.data||fresh());renderEditor()}
  function createProject(){
    const name=(prompt('Název projektu / cenové nabídky:','Nová cenová nabídka')||'').trim();if(!name)return;
    const id='p'+now()+Math.random().toString(36).slice(2,6),data=fresh();data.project=name;
    projects.unshift({id,name,createdAt:now(),updatedAt:now(),data});persistProjects();openProject(id)
  }
  function duplicateProject(id){const p=projects.find(x=>x.id===id);if(!p)return;const nid='p'+now()+Math.random().toString(36).slice(2,6);const data=clone(p.data);data.project=(data.project||p.name||'Nabídka')+' – kopie';projects.unshift({id:nid,name:data.project,createdAt:now(),updatedAt:now(),data});persistProjects();renderProjects()}
  function deleteProject(id){const p=projects.find(x=>x.id===id);if(!p||!confirm(`Smazat cenovou nabídku „${p.name}“?`))return;projects=projects.filter(x=>x.id!==id);if(activeId===id){activeId=null;state=null;localStorage.removeItem(ACTIVE_STORE)}persistProjects();renderProjects()}
  function totalItem(g,it){return !it.on?0:(g.mode==='hours'?(Number(it.qty)||0)*(Number(g.rate)||0):(Number(it.price)||0))}
  function totalGroup(g){return g.items.reduce((s,it)=>s+totalItem(g,it),0)}
  function totalAll(s=state){return (s?.groups||[]).reduce((sum,g)=>sum+g.items.reduce((a,it)=>a+(!it.on?0:(g.mode==='hours'?(Number(it.qty)||0)*(Number(g.rate)||0):(Number(it.price)||0))),0),0)}
  function css(){if(document.getElementById('pricing-v345-style'))return;const s=document.createElement('style');s.id='pricing-v345-style';s.textContent=`
    #tool-pricing .pricing-project-toolbar{display:flex;justify-content:space-between;gap:10px;align-items:center;margin:14px 0}
    #tool-pricing .pricing-project-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:12px;margin-top:14px}
    #tool-pricing .pricing-project-card{border:1px solid var(--border);border-radius:10px;background:#fff;padding:14px;cursor:pointer;transition:.15s}
    #tool-pricing .pricing-project-card:hover{border-color:#d4cc5d;background:#fffef3;transform:translateY(-1px)}
    #tool-pricing .pricing-project-card h3{margin:0 0 5px;font:normal 14px 'Antarctican Mono',monospace}.pricing-project-card .meta{font-size:10px;color:var(--muted);margin-bottom:10px}.pricing-project-card .price{font-size:18px;font-weight:700}.pricing-project-card .card-actions{display:flex;gap:6px;margin-top:12px}.pricing-project-card .card-actions button{font-size:10px;padding:5px 8px}
    #tool-pricing .pricing-head{display:grid;grid-template-columns:1.2fr 1fr 1fr;gap:10px;margin:12px 0 16px}
    #tool-pricing .pricing-head label,#tool-pricing .pricing-rate{display:flex;flex-direction:column;gap:5px;font-size:11px;color:var(--muted)}
    #tool-pricing input,#tool-pricing textarea{border:1px solid var(--border);border-radius:7px;padding:8px;background:#fff;color:var(--text);font:inherit}
    #tool-pricing .pricing-group{border:1px solid var(--border);border-radius:10px;overflow:hidden;margin:12px 0;background:#fff}
    #tool-pricing .pricing-group-head{display:grid;grid-template-columns:1fr auto auto;gap:12px;align-items:center;padding:10px 12px;background:#fafafa;border-bottom:1px solid var(--border)}
    #tool-pricing .pricing-group-head b{font-family:'Antarctican Mono',monospace;font-size:13px}
    #tool-pricing .pricing-rate{flex-direction:row;align-items:center}.pricing-rate input{width:100px}
    #tool-pricing .pricing-row{display:grid;grid-template-columns:26px minmax(260px,1fr) 110px 130px 34px;gap:8px;align-items:center;padding:7px 10px;border-bottom:1px solid #f0f0f1}
    #tool-pricing .pricing-row:last-child{border-bottom:0}.pricing-row input[type=checkbox]{width:auto}
    #tool-pricing .pricing-row .sum{text-align:right;font-weight:600;font-size:12px}.pricing-row .del{border:0;background:transparent;cursor:pointer;font-size:16px}
    #tool-pricing .pricing-actions{display:flex;gap:8px;flex-wrap:wrap;margin:14px 0}.pricing-summary{margin-top:16px;padding:14px;border:1px solid var(--border);border-radius:10px;background:#fafafa}
    #tool-pricing .pricing-summary-row{display:flex;justify-content:space-between;gap:18px;padding:4px 0}.pricing-summary-row.total{font-size:18px;font-weight:700;border-top:1px solid var(--border);margin-top:6px;padding-top:10px}
    @media(max-width:800px){#tool-pricing .pricing-head{grid-template-columns:1fr}.pricing-row{grid-template-columns:24px 1fr 90px 110px 30px}}
  `;document.head.appendChild(s)}
  function inject(){if(document.getElementById('tool-pricing'))return;css();
    const beta=document.querySelector('#menu-view .menu-app-row.beta');if(beta&&!document.getElementById('pricing-menu-tile')){const t=document.createElement('div');t.id='pricing-menu-tile';t.className='tile';t.innerHTML='<b>Cenová nabídka <small class="menu-status">BETA</small></b><span>Projekty cenových nabídek, sazby, profese a export do PDF</span>';t.onclick=()=>window.openPricingOffer();beta.appendChild(t)}
    const host=document.querySelector('.wrap')||document.body;const v=document.createElement('div');v.id='tool-pricing';v.className='tool-view';v.innerHTML=`<button class="back-btn" onclick="closeTool()">← Zpět do menu</button><h1>Cenová nabídka</h1><div class="muted">Zakládej samostatné projekty cenových nabídek. Každý projekt se průběžně ukládá lokálně v prohlížeči.</div><div id="pricing-app"></div>`;host.appendChild(v);renderProjects()}
  function renderProjects(){const root=document.getElementById('pricing-app');if(!root)return;state=null;activeId=null;localStorage.removeItem(ACTIVE_STORE);root.innerHTML=`<div class="pricing-project-toolbar"><div><b>Uložené nabídky</b><div style="font-size:10px;color:var(--muted);margin-top:3px">${projects.length} ${projects.length===1?'projekt':'projektů'} v tomto prohlížeči</div></div><button class="action" id="pr-new-project">+ Nová cenová nabídka</button></div>${projects.length?`<div class="pricing-project-grid">${projects.map(projectCard).join('')}</div>`:'<div class="docs-empty" style="margin-top:16px">Zatím nemáš žádnou uloženou cenovou nabídku.</div>'}`;root.querySelector('#pr-new-project').onclick=createProject;root.querySelectorAll('.pricing-project-card').forEach(card=>{card.onclick=e=>{if(e.target.closest('button'))return;openProject(card.dataset.id)};card.querySelector('.pr-open').onclick=()=>openProject(card.dataset.id);card.querySelector('.pr-copy').onclick=()=>duplicateProject(card.dataset.id);card.querySelector('.pr-delete').onclick=()=>deleteProject(card.dataset.id)})}
  function projectCard(p){const d=p.data||fresh();const dt=new Date(p.updatedAt||p.createdAt||now()).toLocaleString('cs-CZ',{dateStyle:'short',timeStyle:'short'});return `<div class="pricing-project-card" data-id="${p.id}"><h3>${esc(p.name||'Bez názvu')}</h3><div class="meta">${d.client?esc(d.client)+' · ':''}upraveno ${esc(dt)}</div><div class="price">${money(totalAll(d))}</div><div class="card-actions"><button class="action pr-open">Otevřít</button><button class="back-btn pr-copy" style="margin:0">Duplikovat</button><button class="back-btn pr-delete" style="margin:0;color:#b91c1c">Smazat</button></div></div>`}
  function renderEditor(){const root=document.getElementById('pricing-app');if(!root||!state)return;root.innerHTML=`<div class="pricing-project-toolbar"><button class="back-btn" id="pr-back-projects" style="margin:0">← Projekty</button><div style="font-size:10px;color:var(--muted)">Ukládá se automaticky</div></div>
    <div class="pricing-head"><label>Název projektu<input id="pr-project" value="${esc(state.project)}" placeholder="např. Rekonstrukce restaurace"></label><label>Klient<input id="pr-client" value="${esc(state.client)}" placeholder="Název klienta"></label><label>Poznámka<textarea id="pr-note" rows="1" placeholder="volitelná poznámka">${esc(state.note)}</textarea></label></div>
    <div id="pricing-groups">${state.groups.map(groupHtml).join('')}</div>
    <div class="pricing-actions"><button class="action" id="pr-add-group">+ Přidat fázi</button><button class="back-btn" id="pr-reset" style="margin:0">Obnovit šablonu</button><button class="action" id="pr-print">Tisk / PDF</button></div>
    <div class="pricing-summary">${state.groups.map(g=>`<div class="pricing-summary-row"><span>${esc(g.name)}</span><b>${money(totalGroup(g))}</b></div>`).join('')}<div class="pricing-summary-row total"><span>CELKOVÁ SUMA</span><b>${money(totalAll())}</b></div></div>`;bind(root)}
  function groupHtml(g){return `<section class="pricing-group" data-g="${g.id}"><div class="pricing-group-head"><b>${esc(g.name)}</b>${g.mode==='hours'?`<label class="pricing-rate">Hodinovka <input class="pr-rate" type="number" min="0" step="50" value="${Number(g.rate)||0}"> Kč/h</label>`:'<span>Pevné ceny</span>'}<strong>${money(totalGroup(g))}</strong></div>${g.items.map(it=>rowHtml(g,it)).join('')}<div style="padding:8px 10px"><button class="back-btn pr-add-row" style="margin:0">+ Přidat řádek</button></div></section>`}
  function rowHtml(g,it){return `<div class="pricing-row" data-i="${it.id}"><input class="pr-on" type="checkbox" ${it.on?'checked':''}><input class="pr-name" value="${esc(it.name)}">${g.mode==='hours'?`<input class="pr-qty" type="number" min="0" step="1" value="${Number(it.qty)||0}" title="Hodiny">`:`<span></span>`}${g.mode==='hours'?`<div class="sum">${money(totalItem(g,it))}</div>`:`<input class="pr-price" type="number" min="0" step="1000" value="${Number(it.price)||0}">`}<button class="del" title="Smazat">×</button></div>`}
  function bind(root){
    root.querySelector('#pr-back-projects').onclick=()=>{save();renderProjects()};
    root.querySelector('#pr-project').oninput=e=>{state.project=e.target.value;save()};root.querySelector('#pr-client').oninput=e=>{state.client=e.target.value;save()};root.querySelector('#pr-note').oninput=e=>{state.note=e.target.value;save()};
    root.querySelectorAll('.pricing-group').forEach(sec=>{const g=state.groups.find(x=>x.id===sec.dataset.g);if(!g)return;const rate=sec.querySelector('.pr-rate');if(rate)rate.onchange=e=>{g.rate=Number(e.target.value)||0;save();renderEditor()};sec.querySelector('.pr-add-row').onclick=()=>{g.items.push({id:'i'+now()+Math.random(),on:true,name:'Nová položka',qty:1,price:0});save();renderEditor()};sec.querySelectorAll('.pricing-row').forEach(row=>{const it=g.items.find(x=>x.id===row.dataset.i);if(!it)return;row.querySelector('.pr-on').onchange=e=>{it.on=e.target.checked;save();renderEditor()};row.querySelector('.pr-name').onchange=e=>{it.name=e.target.value;save()};row.querySelector('.pr-qty')&&(row.querySelector('.pr-qty').onchange=e=>{it.qty=Number(e.target.value)||0;save();renderEditor()});row.querySelector('.pr-price')&&(row.querySelector('.pr-price').onchange=e=>{it.price=Number(e.target.value)||0;save();renderEditor()});row.querySelector('.del').onclick=()=>{g.items=g.items.filter(x=>x.id!==it.id);save();renderEditor()}})});
    root.querySelector('#pr-add-group').onclick=()=>{const name=(prompt('Název nové fáze:','NOVÁ FÁZE')||'').trim();if(!name)return;state.groups.push({id:'g'+now(),name,mode:'fixed',rate:0,items:[]});save();renderEditor()};
    root.querySelector('#pr-reset').onclick=()=>{if(confirm('Obnovit původní šablonu? Název projektu, klient a poznámka zůstanou zachované.')){const meta={project:state.project,client:state.client,note:state.note};state=fresh();Object.assign(state,meta);save();renderEditor()}};
    root.querySelector('#pr-print').onclick=printOffer;
  }
  function printOffer(){const groups=state.groups.map(g=>({g,items:g.items.filter(i=>i.on)})).filter(x=>x.items.length);const w=window.open('','_blank');if(!w){alert('Povolte vyskakovací okna pro tisk/PDF.');return}let body='';for(const {g,items} of groups){body+=`<h2>${esc(g.name)} <span>${money(totalGroup(g))}</span></h2>`;for(const it of items)body+=`<div class="r"><span>${esc(it.name)}</span><span>${g.mode==='hours'?`${Number(it.qty)||0} h × ${money(g.rate)}`:''}</span><b>${money(totalItem(g,it))}</b></div>`}w.document.write(`<!doctype html><html><head><meta charset="utf-8"><title>Cenová nabídka</title><style>body{font-family:Arial,sans-serif;color:#111;margin:18mm}h1{font-size:24px;margin:0 0 4px}.meta{color:#555;margin-bottom:22px}.note{margin:8px 0 20px}.offer{max-width:760px}h2{font-size:14px;border-bottom:1px solid #aaa;padding:12px 0 5px;margin:0;display:flex;justify-content:space-between}.r{display:grid;grid-template-columns:1fr 180px 120px;gap:12px;padding:5px 0;font-size:11px}.r b{text-align:right}.total{border-top:2px solid #111;margin-top:20px;padding-top:10px;display:flex;justify-content:space-between;font-size:20px;font-weight:700}@media print{body{margin:15mm}}</style></head><body><div class="offer"><h1>Cenová nabídka</h1><div class="meta">${esc(state.project||'Projekt')}${state.client?` · ${esc(state.client)}`:''}</div>${state.note?`<div class="note">${esc(state.note)}</div>`:''}${body}<div class="total"><span>CELKOVÁ SUMA</span><span>${money(totalAll())}</span></div></div><script>window.onload=()=>window.print()<\/script></body></html>`);w.document.close()}
  window.openPricingOffer=function(){document.getElementById('menu-view').style.display='none';document.querySelectorAll('.tool-view').forEach(el=>el.classList.remove('active'));document.getElementById('tool-pricing').classList.add('active');loadProjects();renderProjects()};
  function init(){loadProjects();inject()}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();