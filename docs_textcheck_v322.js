(()=>{
  const state={oldFile:null,newFile:null,oldDoc:null,newDoc:null,results:[]};
  const STOP=new Set('a i ale nebo ani že se je jsou byl byla bylo byly být do od na v ve z ze s u o k ke pro při podle jako který která které jejich jeho její tento tato toto mezi nad pod před po bez také pak kde kdy co jak zda již jen nebo aby než tím této tohoto této těch ty'.split(' '));
  const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
  const norm=s=>String(s||'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9%°²³.,/+\- ]+/g,' ').replace(/\s+/g,' ').trim();
  function tokens(s){return [...new Set(norm(s).split(' ').filter(w=>w.length>2&&!STOP.has(w)))];}
  function sim(a,b){const A=new Set(tokens(a)),B=new Set(tokens(b));if(!A.size||!B.size)return 0;let hit=0;for(const x of A)if(B.has(x))hit++;return hit/Math.max(A.size,B.size);}
  function values(s){
    const rx=/(\d+(?:[.,]\d+)?)\s*(mm|cm|dm|m|km|m2|m²|m3|m³|%|°|kn|n|mpa|kpa|pa|lx|db|h|min|s|kg|t)?/gi,out=[];let m;
    while((m=rx.exec(String(s||'')))){const n=m[1].replace(',','.');const u=(m[2]||'').toLowerCase();out.push(n+(u?' '+u:''));}
    return out;
  }
  function valueDiff(a,b){const A=values(a),B=values(b);if(!A.length&&!B.length)return false;return A.join('|')!==B.join('|');}
  function splitSegments(text,page){
    const clean=String(text||'').replace(/\u00a0/g,' ').replace(/[ \t]+/g,' ').replace(/\n{3,}/g,'\n\n').trim();if(!clean)return[];
    let chunks=clean.split(/\n\s*\n|(?<=[.!?;:])\s+(?=[A-ZÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ0-9§])/).map(x=>x.trim()).filter(Boolean);
    const out=[];for(let c of chunks){if(c.length<55)continue;if(c.length<=700){out.push({page,text:c});continue;}const ss=c.split(/(?<=[.!?;])\s+/);let buf='';for(const s of ss){if((buf+' '+s).length>650&&buf.length>80){out.push({page,text:buf.trim()});buf='';}buf+=(buf?' ':'')+s;}if(buf.length>55)out.push({page,text:buf.trim()});}
    return out;
  }
  async function extractPdf(file,progress){
    const bytes=new Uint8Array(await file.arrayBuffer()),pdf=await pdfjsLib.getDocument({data:bytes}).promise,pages=[],segments=[];
    for(let p=1;p<=pdf.numPages;p++){progress?.(p,pdf.numPages);const pg=await pdf.getPage(p),tc=await pg.getTextContent();let txt='';for(const it of tc.items){txt+=String(it.str||'');txt+=it.hasEOL?'\n':' ';}txt=txt.replace(/[ \t]+\n/g,'\n').replace(/\n[ \t]+/g,'\n');pages.push(txt);segments.push(...splitSegments(txt,p));}
    return {name:file.name,pages,segments,numPages:pdf.numPages};
  }
  function bestMatch(seg,candidates,limitPage=null){
    const st=tokens(seg.text);if(st.length<3)return null;let best=null;
    for(const c of candidates){if(limitPage&&Math.abs(c.page-limitPage)>3)continue;const s=sim(seg.text,c.text);if(!best||s>best.score)best={seg:c,score:s};}
    return best;
  }
  function classify(oldSeg,newSeg,score){
    if(!newSeg)return {type:'ODSTRANĚNO',prio:3};
    if(valueDiff(oldSeg.text,newSeg.text)&&score>=.38)return {type:'ZMĚNA HODNOTY',prio:5};
    if(score>=.88)return oldSeg.page===newSeg.page?{type:'SHODNÝ TEXT',prio:1}:{type:'PŘESUNUTO / SHODNÝ TEXT',prio:2};
    if(score>=.5)return {type:'ZMĚNA FORMULACE',prio:4};
    return {type:'SLABÁ SHODA',prio:2};
  }
  function compareDocs(a,b){
    const res=[],usedNew=new Set();
    for(let i=0;i<a.segments.length;i++){
      const o=a.segments[i],m=bestMatch(o,b.segments);if(!m||m.score<.34){res.push({old:o,new:null,score:m?.score||0,...classify(o,null,0)});continue;}
      usedNew.add(m.seg);const cls=classify(o,m.seg,m.score);if(cls.type!=='SHODNÝ TEXT'||o.page!==m.seg.page||valueDiff(o.text,m.seg.text))res.push({old:o,new:m.seg,score:m.score,...cls});
    }
    for(const n of b.segments){if(usedNew.has(n))continue;const m=bestMatch(n,a.segments);if(!m||m.score<.34)res.push({old:null,new:n,score:m?.score||0,type:'NOVĚ PŘIDÁNO',prio:3});}
    return res.filter(r=>((r.old?.text||r.new?.text||'').length>=65)).sort((x,y)=>y.prio-x.prio||y.score-x.score).slice(0,400);
  }
  function badgeClass(t){return t==='ZMĚNA HODNOTY'?'error':(t==='ZMĚNA FORMULACE'||t==='ODSTRANĚNO'||t==='NOVĚ PŘIDÁNO'?'warn':'ok');}
  function render(){
    const host=document.getElementById('textcheck-results');if(!host)return;const rs=state.results;
    if(!rs.length){host.innerHTML='<div class="docs-empty">Nebyly nalezeny významné rozdíly nebo dokumenty nemají použitelnou textovou vrstvu.</div>';return;}
    const counts={};rs.forEach(r=>counts[r.type]=(counts[r.type]||0)+1);
    host.innerHTML=`<div class="textcheck-summary">${Object.entries(counts).map(([k,v])=>`<span><b>${v}</b> ${esc(k)}</span>`).join('')}</div>`+rs.map((r,i)=>`<article class="textcheck-card ${badgeClass(r.type)}" id="textcheck-${i}">
      <div class="textcheck-head"><span class="textcheck-type">${esc(r.type)}</span><span>podobnost ${Math.round((r.score||0)*100)} %</span></div>
      <div class="textcheck-pages"><b>Stará:</b> ${r.old?'str. '+r.old.page:'—'} &nbsp;→&nbsp; <b>Nová:</b> ${r.new?'str. '+r.new.page:'—'}</div>
      <div class="textcheck-cols"><div><b>STARÝ TEXT</b><p>${esc(r.old?.text||'—')}</p></div><div><b>NOVÝ TEXT</b><p>${esc(r.new?.text||'—')}</p></div></div>
      ${r.old&&r.new&&valueDiff(r.old.text,r.new.text)?`<div class="textcheck-values"><b>Hodnoty:</b> ${esc(values(r.old.text).join(', ')||'—')} → ${esc(values(r.new.text).join(', ')||'—')}</div>`:''}
      <div class="textcheck-actions"><button class="back-btn" onclick="window.textcheckRecheck(${i})">Projít znovu tento výsledek</button><button class="back-btn" onclick="window.textcheckCopy(${i})">Kopírovat nález</button></div>
    </article>`).join('');
  }
  window.textcheckCopy=async i=>{const r=state.results[i];if(!r)return;const t=`${r.type}\nStará strana: ${r.old?.page||'-'}\nNová strana: ${r.new?.page||'-'}\n\nSTARÝ TEXT:\n${r.old?.text||'-'}\n\nNOVÝ TEXT:\n${r.new?.text||'-'}`;try{await navigator.clipboard.writeText(t)}catch(e){prompt('Zkopíruj:',t)}};
  window.textcheckRecheck=i=>{
    const r=state.results[i];if(!r||!state.oldDoc||!state.newDoc)return;let best=null;
    if(r.old){best=bestMatch(r.old,state.newDoc.segments);if(best){r.new=best.seg;r.score=best.score;Object.assign(r,classify(r.old,r.new,r.score));}}
    else if(r.new){best=bestMatch(r.new,state.oldDoc.segments);if(best&&best.score>=.34){r.old=best.seg;r.score=best.score;Object.assign(r,classify(r.old,r.new,r.score));}}
    render();setTimeout(()=>document.getElementById('textcheck-'+i)?.scrollIntoView({behavior:'smooth',block:'center'}),30);
  };
  async function run(){
    const st=document.getElementById('textcheck-status'),btn=document.getElementById('textcheck-run');if(!state.oldFile||!state.newFile){st.textContent='Nahraj staré i nové PDF.';return;}
    try{btn.disabled=true;st.textContent='Čtu staré PDF…';state.oldDoc=await extractPdf(state.oldFile,(p,n)=>st.textContent=`Čtu staré PDF: ${p}/${n}`);st.textContent='Čtu nové PDF…';state.newDoc=await extractPdf(state.newFile,(p,n)=>st.textContent=`Čtu nové PDF: ${p}/${n}`);st.textContent='Porovnávám text a hledám přesunuté pasáže…';await new Promise(r=>setTimeout(r,20));state.results=compareDocs(state.oldDoc,state.newDoc);render();st.textContent=`Hotovo. Staré PDF: ${state.oldDoc.numPages} stran · nové PDF: ${state.newDoc.numPages} stran · ${state.results.length} nálezů k prověření.`;
    }catch(e){st.textContent='Chyba: '+(e.message||e)}finally{btn.disabled=false;}
  }
  function addUi(){
    const host=document.getElementById('tool-docs');if(!host||document.getElementById('docs-textcheck'))return;const tabs=host.querySelector('.docs-tabs');if(!tabs)return;
    const tab=document.createElement('button');tab.className='docs-tab';tab.dataset.docTab='textcheck';tab.textContent='Kontrola textu';tab.onclick=()=>window.openDocsSection?.('textcheck');tabs.appendChild(tab);
    const sec=document.createElement('div');sec.id='docs-textcheck';sec.className='docs-section';sec.innerHTML=`<h1 style="font-size:18px">Kontrola textu — stará vs. nová dokumentace</h1>
      <div class="muted">Porovná textovou vrstvu dvou PDF, hledá stejné nebo podobné pasáže i po přesunu na jinou stránku a zvýrazní změny hodnot, rozměrů, jednotek a formulací. Výsledky jsou určeny k lidské kontrole.</div>
      <div class="textcheck-files"><label><b>STARÁ VERZE</b><input id="textcheck-old" type="file" accept=".pdf,application/pdf"></label><label><b>NOVÁ VERZE</b><input id="textcheck-new" type="file" accept=".pdf,application/pdf"></label></div>
      <div class="row"><button class="action" id="textcheck-run" disabled>Porovnat text</button><span id="textcheck-status" class="muted" style="margin:0">Nahraj obě PDF.</span></div>
      <div class="docs-note">Nástroj pracuje s textovou vrstvou PDF. U čistých scanů bez textu nebude spolehlivý. „Změna hodnoty“ je prioritní upozornění, ne automatické právní posouzení.</div>
      <div id="textcheck-results"></div>`;host.appendChild(sec);
    const old=document.getElementById('textcheck-old'),neu=document.getElementById('textcheck-new'),btn=document.getElementById('textcheck-run');
    const sync=()=>{btn.disabled=!(state.oldFile&&state.newFile)};old.onchange=()=>{state.oldFile=old.files?.[0]||null;sync()};neu.onchange=()=>{state.newFile=neu.files?.[0]||null;sync()};btn.onclick=run;
    const overview=document.querySelector('#docs-v321-overview .docs-v321-grid');if(overview&&!document.getElementById('textcheck-overview-card')){const b=document.createElement('button');b.id='textcheck-overview-card';b.className='docs-v321-card';b.innerHTML='<b>6 · Kontrola textu</b><span>Stará vs. nová vyhláška, technická zpráva nebo jiný dokument. Najde přesuny i změny hodnot.</span><span class="docs-v321-badge">NOVÉ</span>';b.onclick=()=>window.openDocsSection?.('textcheck');overview.appendChild(b);}
  }
  function css(){if(document.getElementById('textcheck-v322-style'))return;const s=document.createElement('style');s.id='textcheck-v322-style';s.textContent=`
    #tool-docs .textcheck-files{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin:12px 0}.textcheck-files label{border:1px solid var(--border);border-radius:9px;background:#fafafa;padding:12px;display:flex;flex-direction:column;gap:8px}.textcheck-files label b{font:normal 12px 'Antarctican Mono',monospace}.textcheck-summary{display:flex;gap:7px;flex-wrap:wrap;margin:14px 0}.textcheck-summary span{border:1px solid var(--border);border-radius:999px;background:#fafafa;padding:5px 8px;font-size:10px}.textcheck-card{border:1px solid var(--border);border-left:4px solid #a1a1aa;border-radius:9px;background:#fff;padding:12px;margin:10px 0}.textcheck-card.error{border-left-color:#dc2626}.textcheck-card.warn{border-left-color:#d97706}.textcheck-card.ok{border-left-color:#16a34a}.textcheck-head{display:flex;justify-content:space-between;gap:10px;align-items:center;font-size:10px;color:var(--muted)}.textcheck-type{font:600 11px system-ui;color:var(--text)}.textcheck-pages{font-size:11px;margin:8px 0}.textcheck-cols{display:grid;grid-template-columns:1fr 1fr;gap:10px}.textcheck-cols>div{background:#fafafa;border:1px solid var(--border);border-radius:7px;padding:9px;min-width:0}.textcheck-cols b{font-size:9px}.textcheck-cols p{white-space:pre-wrap;font-size:11px;line-height:1.5;margin:5px 0 0;word-break:break-word}.textcheck-values{margin-top:8px;padding:7px 9px;background:#fff7ed;border:1px solid #fed7aa;border-radius:7px;font-size:10px}.textcheck-actions{display:flex;gap:7px;margin-top:9px;flex-wrap:wrap}.textcheck-actions .back-btn{margin:0;padding:6px 8px;font-size:9px}@media(max-width:700px){#tool-docs .textcheck-files,.textcheck-cols{grid-template-columns:1fr}}
  `;document.head.appendChild(s);}
  function patchOpen(){if(window.__textcheckV322Patched)return;window.__textcheckV322Patched=true;const prev=window.openDocsSection;window.openDocsSection=function(name){if(name==='textcheck'){document.querySelectorAll('#tool-docs .docs-section').forEach(x=>x.classList.remove('active'));document.querySelectorAll('#tool-docs .docs-tab').forEach(x=>x.classList.toggle('active',x.dataset.docTab==='textcheck'));document.getElementById('docs-textcheck')?.classList.add('active');return;}return prev?.(name);};}
  function init(){css();addUi();patchOpen();}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();