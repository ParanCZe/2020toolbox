(()=>{
  const PREF='toolbox.drawinglist.columns.v342';
  const LABELS=['Poř.','List','Číslo výkresu','Název výkresu','Měřítko','Stupeň dokumentace','Formát'];
  let state={};try{state=JSON.parse(localStorage.getItem(PREF)||'{}')||{}}catch(_){state={}};for(const l of LABELS)if(typeof state[l]!=='boolean')state[l]=true;
  const norm=s=>String(s||'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/\s+/g,' ').trim();
  const keyFor=s=>{const n=norm(s);if(/^por\.?$/.test(n)||n==='poradi')return'Poř.';if(n==='list')return'List';if(n.includes('cislo vykresu'))return'Číslo výkresu';if(n.includes('nazev vykresu'))return'Název výkresu';if(n.includes('meritko'))return'Měřítko';if(n.includes('stupen dokumentace'))return'Stupeň dokumentace';if(n==='format')return'Formát';return null};
  function section(){return document.getElementById('docs-drawinglist')||document.querySelector('[data-doc-section="drawinglist"]')||document.querySelector('#tool-docs .docs-section.active')}
  function tables(){const s=section();if(!s)return[];return [...s.querySelectorAll('table')].filter(t=>[...t.querySelectorAll('th')].some(th=>keyFor(th.textContent)))}
  function save(){localStorage.setItem(PREF,JSON.stringify(state))}
  function esc(v){return typeof window.escapeHtml==='function'?window.escapeHtml(String(v??'')):String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
  function applyTable(t){const heads=[...t.querySelectorAll('tr:first-child th')];if(!heads.length)return;const map=heads.map(h=>keyFor(h.textContent));const visible=map.reduce((n,k)=>n+(k&&state[k]!==false?1:0),0)||1;[...t.rows].forEach(tr=>{const cells=[...tr.cells];if(cells.length===1&&Number(cells[0].colSpan)>1){cells[0].colSpan=visible;return}cells.forEach((cell,i)=>{const k=map[i];if(!k)return;const show=state[k]!==false;const next=show?'':'none';if(cell.style.display!==next)cell.style.display=next;cell.dataset.drawingColumn=k})})}
  function apply(){tables().forEach(applyTable)}
  function installUI(){const s=section();if(!s||document.getElementById('drawing-columns-v342'))return;const anchor=s.querySelector('table');if(!anchor)return;const box=document.createElement('div');box.id='drawing-columns-v342';box.dataset.noExport='1';box.style.cssText='margin:10px 0 12px;padding:10px 12px;border:1px solid #d4d4d8;border-radius:8px;background:#fafafa;font-size:11px';box.innerHTML='<b style="display:block;margin-bottom:7px">Sloupce v PDF</b><div style="display:flex;gap:12px;flex-wrap:wrap"></div><div style="margin-top:6px;color:#71717a;font-size:9px">Odškrtnuté sloupce se nezobrazí v seznamu ani v exportovaném PDF.</div>';const row=box.querySelector('div');LABELS.forEach(l=>{const lab=document.createElement('label');lab.style.cssText='display:inline-flex;align-items:center;gap:5px;cursor:pointer;white-space:nowrap';const inp=document.createElement('input');inp.type='checkbox';inp.checked=state[l]!==false;inp.dataset.column=l;inp.addEventListener('change',()=>{state[l]=inp.checked;save();apply()});lab.append(inp,document.createTextNode(l));row.appendChild(lab)});anchor.parentNode.insertBefore(box,anchor)}
  function installPrintCss(){if(document.getElementById('drawing-columns-v342-style'))return;const st=document.createElement('style');st.id='drawing-columns-v342-style';st.textContent='@media print{#drawing-columns-v342,[data-no-export="1"]{display:none!important}}';document.head.appendChild(st)}
  function installPdfExport(){
    window.printDrawingList=function(){
      const defs=[['Poř.',(x,n)=>n],['List',x=>x.pageCount>1?`${x.page}/${x.pageCount}`:'1'],['Číslo výkresu',x=>x.number],['Název výkresu',x=>x.title],['Měřítko',x=>x.scale],['Stupeň dokumentace',x=>x.documentationStage||''],['Formát',x=>x.format]].filter(([label])=>state[label]!==false);
      if(!defs.length){alert('Vyberte alespoň jeden sloupec pro PDF.');return}
      let order=0,rows='';const groups=typeof window.drawingGroupsWithIndices==='function'?window.drawingGroupsWithIndices():new Map();
      for(const [group,entries] of groups){rows+=`<tr class="section"><td colspan="${defs.length}">${esc(group)}</td></tr>`;for(const {row:x} of entries){order++;rows+='<tr>'+defs.map(([,get])=>`<td>${esc(get(x,order))}</td>`).join('')+'</tr>'}}
      const w=window.open('','_blank');if(!w){alert('Prohlížeč zablokoval nové okno. Povolte vyskakovací okna pro tisk.');return}
      const head=defs.map(([label])=>`<th>${esc(label)}</th>`).join('');
      w.document.write(`<!doctype html><html><head><meta charset="utf-8"><title>Seznam výkresů</title><style>
        body{font-family:Arial,sans-serif;margin:24px;color:#111}
        .sheet{width:74%;max-width:620px;margin:0 auto}
        h1{font-size:20px;margin:0 0 14px}
        table{width:100%;border:0!important;border-collapse:separate;border-spacing:0;font-size:11px}
        table,thead,tbody,tr,th,td{border:none!important;outline:none!important;box-shadow:none!important;background:transparent!important}
        th,td{padding:3px 7px;text-align:left;vertical-align:top}
        th{font-weight:700;padding-bottom:8px}
        .section td{font-weight:700;font-size:12px;padding-top:12px;padding-bottom:5px}
        @media print{body{margin:10mm}.sheet{width:74%;max-width:none}}
      </style></head><body><div class="sheet"><h1>Seznam výkresů</h1><table><thead><tr>${head}</tr></thead><tbody>${rows}</tbody></table></div><script>window.onload=()=>window.print()<\/script></body></html>`);w.document.close();
    };
  }
  function sync(){installPrintCss();installUI();apply();installPdfExport()}
  function installRenderHook(){const fn=window.renderDrawingList;if(typeof fn!=='function'||fn.__drawingColumnsHooked)return;const wrapped=function(...args){const result=fn.apply(this,args);setTimeout(sync,0);return result};wrapped.__drawingColumnsHooked=true;window.renderDrawingList=wrapped}
  function init(){sync();installRenderHook();setTimeout(()=>{sync();installRenderHook()},350);setTimeout(()=>{sync();installRenderHook()},1200);document.addEventListener('click',e=>{if(e.target.closest?.('[data-doc-tab="drawinglist"],[data-go="drawinglist"]'))setTimeout(sync,80)},true)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();