(()=>{
  const PROJECTS_STORE='toolbox.pricingOffer.projects.v346';
  const ACTIVE_STORE='toolbox.pricingOffer.active.v346';
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const money=n=>new Intl.NumberFormat('cs-CZ',{style:'currency',currency:'CZK',maximumFractionDigits:0}).format(Number(n)||0);
  function state(){try{const ps=JSON.parse(localStorage.getItem(PROJECTS_STORE)||'[]')||[];const id=localStorage.getItem(ACTIVE_STORE);return ps.find(p=>p.id===id)?.data||null}catch(_){return null}}
  const rowRate=(g,it)=>{const r=Number(it?.rateOverride);return Number.isFinite(r)&&r>=0?r:(Number(g?.rate)||0)};
  const itemTotal=(g,it)=>it.on===false?0:(g.mode==='hours'?(Number(it.qty)||0)*rowRate(g,it):(Number(it.price)||0));
  const groupTotal=g=>(g.items||[]).reduce((s,it)=>s+itemTotal(g,it),0);
  const groupHours=g=>g.mode==='hours'?(g.items||[]).reduce((s,it)=>s+(it.on===false?0:Number(it.qty)||0),0):0;
  function summary(s){const gs=s?.groups||[];const arch=gs.filter(g=>g.mode==='hours').reduce((a,g)=>a+groupTotal(g),0);const prof=gs.filter(g=>g.mode==='fixed').reduce((a,g)=>a+groupTotal(g),0);const hours=gs.reduce((a,g)=>a+groupHours(g),0);const net=arch+prof,vat=net*(Number(s?.vat)||0)/100;return{arch,prof,hours,net,vat,gross:net+vat}}
  async function toDataUrl(url){
    try{
      const r=await fetch(url,{cache:'no-store'});if(!r.ok)throw new Error(String(r.status));
      const blob=await r.blob();
      return await new Promise((resolve,reject)=>{const fr=new FileReader();fr.onload=()=>resolve(fr.result);fr.onerror=reject;fr.readAsDataURL(blob)})
    }catch(e){console.warn('Nepodařilo se vložit font do exportu',e);return url}
  }
  async function exportOffer(){
    const s0=state();if(!s0)return alert('Nejdřív otevři cenovou nabídku.');
    const w=window.open('','_blank');if(!w)return alert('Povol vyskakovací okna pro Tisk / PDF.');
    w.document.write('<!doctype html><title>Připravuji cenovou nabídku…</title><body style="font-family:monospace;padding:24px">Připravuji export…</body>');w.document.close();
    const sum=summary(s0),groups=(s0.groups||[]).filter(g=>(g.items||[]).some(i=>i.on!==false));
    const rates=[];groups.filter(g=>g.mode==='hours').forEach(g=>(g.items||[]).filter(i=>i.on!==false).forEach(it=>{const r=rowRate(g,it);if(r>0)rates.push(r)}));
    const uniq=[...new Set(rates)],rateText=uniq.length===1?`${money(uniq[0]).replace(/Kč\s?$/,'')} Kč/h`:uniq.length>1?'individuálně dle položek':'—';
    let sections='';
    groups.forEach((g,gi)=>{
      const items=(g.items||[]).filter(i=>i.on!==false),fixed=g.mode==='fixed';
      sections+=`<section class="offer-section"><div class="section-title"><span>${String(gi+1).padStart(2,'0')}</span><span>${esc((g.name||'').toUpperCase())}</span></div>`;
      if(fixed){
        sections+=`<div class="thead fixed"><span>Č.</span><span>Profese</span><span>Cena bez DPH</span></div>`;
        items.forEach((it,ii)=>sections+=`<div class="tr fixed"><span>${String(gi+1).padStart(2,'0')}.${ii+1}</span><span>${esc(it.name||'')}</span><b>${money(itemTotal(g,it))}</b></div>`);
        sections+=`<div class="subtotal fixed"><span>${esc((g.name||'').toUpperCase())} CELKEM</span><b>${money(groupTotal(g))}</b></div>`;
      }else{
        sections+=`<div class="thead"><span>Č.</span><span>Pracovní balíček</span><span>Hodiny</span><span>Sazba Kč/h</span><span>Cena bez DPH</span></div>`;
        items.forEach((it,ii)=>{const r=rowRate(g,it);sections+=`<div class="tr"><span>${String(gi+1).padStart(2,'0')}.${ii+1}</span><span>${esc(it.name||'')}</span><span class="num">${Number(it.qty)||0} h</span><span class="num">${money(r).replace(/Kč\s?$/,'')} Kč/h</span><b>${money(itemTotal(g,it))}</b></div>`});
        sections+=`<div class="subtotal"><span>${esc((g.name||'').toUpperCase())} CELKEM</span><span>${groupHours(g)} h</span><b>${money(groupTotal(g))}</b></div>`;
      }
      sections+='</section>';
    });
    const bookUrl=new URL('font/Dunwich Type Founders - Antarctican Mono Book.otf',window.location.href).href;
    const boldUrl=new URL('font/Dunwich Type Founders - Antarctican Mono Bold.otf',window.location.href).href;
    const [fontBook,fontBold]=await Promise.all([toDataUrl(bookUrl),toDataUrl(boldUrl)]);
    w.document.open();
    w.document.write(`<!doctype html><html><head><meta charset="utf-8"><title>Cenová nabídka – ${esc(s0.project||'Projekt')}</title><style>
      @font-face{font-family:'Antarctican Mono';src:url('${fontBook}') format('opentype');font-weight:400;font-style:normal}@font-face{font-family:'Antarctican Mono';src:url('${fontBold}') format('opentype');font-weight:700;font-style:normal}
      @page{size:A4 portrait;margin:10mm 10mm 9mm}*{box-sizing:border-box}html,body{margin:0;background:#fff;color:#171717}html,body,.page,.page *{font-family:'Antarctican Mono',monospace!important}body{font-size:7.4pt;line-height:1.35;-webkit-print-color-adjust:exact;print-color-adjust:exact}.page{max-width:190mm;margin:auto}.brand-top{font-weight:700;margin:1mm 0 7mm}.title{font-size:15.4pt;margin:0 0 1mm}.subtitle{font-size:7.2pt;color:#6b6b6b;margin-bottom:4mm}.two-col-head,.info-wrap{display:grid;grid-template-columns:1fr 1fr}.yellow{background:#f4ee73;padding:1.7mm 1.4mm}.info-wrap{margin-bottom:3.5mm}.info-box{display:grid;grid-template-columns:27mm 1fr;row-gap:1.2mm;padding:2mm 1.4mm;font-size:6.8pt}.info-box.right{grid-template-columns:1fr 33mm}.info-box span{color:#777}.info-box.right b{text-align:right}.info-box b{font-weight:400}.offer-section{margin-top:2.2mm}.section-title{display:grid;grid-template-columns:8mm 1fr;background:#f4ee73;padding:1.6mm 1.2mm}.thead,.tr{display:grid;grid-template-columns:14mm minmax(70mm,1fr) 18mm 30mm 30mm;column-gap:4mm}.thead{background:#202023;color:#fff;font-size:6.5pt}.thead span,.tr span,.tr b{padding:1.7mm 1.2mm}.tr{min-height:9.5mm;align-items:center}.tr .num,.tr b{text-align:right;white-space:nowrap}.tr b{font-weight:400}.thead.fixed,.tr.fixed{grid-template-columns:14mm minmax(100mm,1fr) 36mm}.subtotal{display:grid;grid-template-columns:1fr 24mm 36mm;column-gap:4mm;background:#efefed;padding:1.6mm 1.2mm}.subtotal span:nth-last-child(2),.subtotal b{text-align:right}.subtotal b{font-weight:400}.subtotal.fixed{grid-template-columns:1fr 36mm}.recap-spacer{height:10mm}.recap{break-inside:avoid}.recap-head{background:#f4ee73;padding:1.6mm 1.2mm}.recap-row{display:grid;grid-template-columns:1fr 34mm;padding:.8mm 1.2mm}.recap-row b{text-align:right;font-weight:400}.recap-row.strong{background:#efefed}.recap-row.vat{grid-template-columns:1fr 16mm 34mm}.recap-row.total{background:#f4ee73;font-size:10.6pt;padding:1.9mm 1.2mm}.note{margin:3mm 0 4mm;font-size:6.4pt}.footer{height:4.7mm;background:#f4ee73;display:flex;align-items:center;justify-content:flex-end;padding:0 1.2mm;font-weight:700}@media print{.offer-section,.tr,.subtotal,.recap{break-inside:avoid}}
    </style></head><body><div class="page"><div class="brand-top">20-20-ARCHITEKTI</div><div class="title">CENOVÁ NABÍDKA – PROJEKT INTERIÉRU</div><div class="subtitle">${esc((s0.project||'').toUpperCase())}</div><div class="two-col-head"><div class="yellow">ÚDAJE NABÍDKY</div><div class="yellow">KLÍČOVÉ VSTUPY A VÝSTUPY</div></div><div class="info-wrap"><div class="info-box"><span>Projekt</span><b>${esc(s0.project||'—')}</b><span>Objednatel</span><b>${esc(s0.client||'—')}</b><span>Datum</span><b>${esc(s0.date?new Date(s0.date+'T12:00:00').toLocaleDateString('cs-CZ'):'—')}</b></div><div class="info-box right"><span>Hodinová sazba bez DPH</span><b>${rateText}</b><span>Celkový rozsah arch. prací</span><b>${sum.hours} h</b><span>Cena arch. prací bez DPH</span><b>${money(sum.arch)}</b><span>Profesní subdodávky bez DPH</span><b>${money(sum.prof)}</b><span>Cena projektu celkem bez DPH</span><b>${money(sum.net)}</b></div></div>${sections}<div class="recap-spacer"></div><div class="recap"><div class="recap-head">REKAPITULACE CENY</div><div class="recap-row"><span>Architektonické práce</span><b>${money(sum.arch)}</b></div><div class="recap-row"><span>Profesní subdodávky</span><b>${money(sum.prof)}</b></div><div class="recap-row strong"><span>CENA CELKEM BEZ DPH</span><b>${money(sum.net)}</b></div><div class="recap-row vat"><span>DPH</span><span>${Number(s0.vat)||0}%</span><b>${money(sum.vat)}</b></div><div class="recap-row total"><span>CENA CELKEM VČETNĚ DPH</span><b>${money(sum.gross)}</b></div></div>${s0.note?`<div class="note">${esc(s0.note)}</div>`:''}<div class="footer">20-20-ARCHITEKTI</div></div><script>window.onload=async()=>{try{await document.fonts.load("400 12px 'Antarctican Mono'");await document.fonts.load("700 12px 'Antarctican Mono'");await document.fonts.ready}catch(e){}setTimeout(()=>window.print(),500)}<\/script></body></html>`);w.document.close();
  }
  function bind(){const root=document.getElementById('tool-pricing'),b=root?.querySelector('#pr-print');if(!b||b.dataset.v353)return;b.dataset.v353='1';b.addEventListener('click',e=>{e.preventDefault();e.stopImmediatePropagation();exportOffer()},{capture:true})}
  function init(){bind();const root=document.getElementById('tool-pricing');if(root)new MutationObserver(()=>requestAnimationFrame(bind)).observe(root,{childList:true,subtree:true})}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();