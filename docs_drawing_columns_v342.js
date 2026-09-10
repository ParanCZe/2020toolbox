(()=>{
  const PREF='toolbox.drawinglist.columns.v342';
  const LABELS=['Poř.','List','Číslo výkresu','Název výkresu','Měřítko','Stupeň dokumentace','Formát'];
  let state={};
  try{state=JSON.parse(localStorage.getItem(PREF)||'{}')||{}}catch(_){state={}}
  for(const l of LABELS)if(typeof state[l]!=='boolean')state[l]=true;

  const norm=s=>String(s||'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/\s+/g,' ').trim();
  const keyFor=s=>{
    const n=norm(s);
    if(/^por\.?$/.test(n)||n==='poradi')return'Poř.';
    if(n==='list')return'List';
    if(n.includes('cislo vykresu'))return'Číslo výkresu';
    if(n.includes('nazev vykresu'))return'Název výkresu';
    if(n.includes('meritko'))return'Měřítko';
    if(n.includes('stupen dokumentace'))return'Stupeň dokumentace';
    if(n==='format')return'Formát';
    return null;
  };

  function section(){return document.getElementById('docs-drawinglist')||document.querySelector('[data-doc-section="drawinglist"]')||document.querySelector('#tool-docs .docs-section.active')}
  function tables(){const s=section();if(!s)return[];return [...s.querySelectorAll('table')].filter(t=>[...t.querySelectorAll('th')].some(th=>keyFor(th.textContent)))}
  function save(){localStorage.setItem(PREF,JSON.stringify(state))}

  function applyTable(t){
    const heads=[...t.querySelectorAll('tr:first-child th')];
    if(!heads.length)return;
    const map=heads.map(h=>keyFor(h.textContent));
    const visible=map.reduce((n,k)=>n+(k&&state[k]!==false?1:0),0)||1;
    [...t.rows].forEach((tr,ri)=>{
      const cells=[...tr.cells];
      if(cells.length===1&&Number(cells[0].colSpan)>1){cells[0].colSpan=visible;return}
      cells.forEach((cell,i)=>{
        const k=map[i];
        if(!k)return;
        const show=state[k]!==false;
        cell.style.display=show?'':'none';
        cell.dataset.drawingColumn=k;
      });
    });
  }

  function apply(){tables().forEach(applyTable)}

  function installUI(){
    const s=section();if(!s||document.getElementById('drawing-columns-v342'))return;
    const anchor=s.querySelector('table');if(!anchor)return;
    const box=document.createElement('div');box.id='drawing-columns-v342';box.dataset.noExport='1';
    box.style.cssText='margin:10px 0 12px;padding:10px 12px;border:1px solid #d4d4d8;border-radius:8px;background:#fafafa;font-size:11px';
    box.innerHTML='<b style="display:block;margin-bottom:7px">Sloupce v PDF</b><div style="display:flex;gap:12px;flex-wrap:wrap"></div><div style="margin-top:6px;color:#71717a;font-size:9px">Odškrtnuté sloupce se nezobrazí v seznamu ani v exportovaném PDF.</div>';
    const row=box.querySelector('div');
    LABELS.forEach(l=>{
      const lab=document.createElement('label');lab.style.cssText='display:inline-flex;align-items:center;gap:5px;cursor:pointer;white-space:nowrap';
      const inp=document.createElement('input');inp.type='checkbox';inp.checked=state[l]!==false;inp.dataset.column=l;
      inp.addEventListener('change',()=>{state[l]=inp.checked;save();apply()});
      lab.append(inp,document.createTextNode(l));row.appendChild(lab);
    });
    anchor.parentNode.insertBefore(box,anchor);
  }

  function installPrintCss(){
    if(document.getElementById('drawing-columns-v342-style'))return;
    const st=document.createElement('style');st.id='drawing-columns-v342-style';st.textContent='@media print{#drawing-columns-v342,[data-no-export="1"]{display:none!important}}';document.head.appendChild(st);
  }

  function sync(){installPrintCss();installUI();apply()}
  function init(){sync();new MutationObserver(()=>sync()).observe(document.body,{childList:true,subtree:true});setInterval(sync,900)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();