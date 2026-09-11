(()=>{
  const PROJECTS_STORE='toolbox.pricingOffer.projects.v346';
  const ACTIVE_STORE='toolbox.pricingOffer.active.v346';
  const LEGACY_RATE_STORE='toolbox.pricingOffer.rowRates.v350';
  const money=n=>new Intl.NumberFormat('cs-CZ',{style:'currency',currency:'CZK',maximumFractionDigits:0}).format(Number(n)||0);
  function readProjects(){try{return JSON.parse(localStorage.getItem(PROJECTS_STORE)||'[]')||[]}catch(_){return[]}}
  function writeProjects(ps){localStorage.setItem(PROJECTS_STORE,JSON.stringify(ps))}
  function active(){const id=localStorage.getItem(ACTIVE_STORE);const ps=readProjects();return {id,ps,p:ps.find(x=>x.id===id)||null}}
  function legacyRates(){try{return JSON.parse(localStorage.getItem(LEGACY_RATE_STORE)||'{}')||{}}catch(_){return{}}}
  function legacyKey(pid,gid,iid){return `${pid}|${gid}|${iid}`}
  function effectiveRate(g,it){const own=Number(it?.rateOverride);return Number.isFinite(own)&&own>=0?own:(Number(g?.rate)||0)}
  function migrateLegacy(){
    const map=legacyRates();if(!Object.keys(map).length)return;
    const {ps}=active();let changed=false;
    for(const p of ps){for(const g of p?.data?.groups||[]){if(g.mode!=='hours')continue;for(const it of g.items||[]){const k=legacyKey(p.id,g.id,it.id);if(Object.prototype.hasOwnProperty.call(map,k)&&it.rateOverride==null){const v=Number(map[k]);if(Number.isFinite(v)&&v>=0){it.rateOverride=v;changed=true}}}}}
    if(changed)writeProjects(ps);
  }
  function calcProject(p){let arch=0,prof=0,hours=0;for(const g of p?.data?.groups||[]){for(const it of g.items||[]){if(it.on===false)continue;if(g.mode==='hours'){const q=Number(it.qty)||0;hours+=q;arch+=q*effectiveRate(g,it)}else prof+=Number(it.price)||0}}const net=arch+prof,vat=net*(Number(p?.data?.vat)||0)/100;return {arch,prof,hours,net,vat,gross:net+vat}}
  function persistRate(pid,gid,iid,value,groupRate){const ps=readProjects(),p=ps.find(x=>x.id===pid),g=p?.data?.groups?.find(x=>String(x.id)===String(gid)),it=g?.items?.find(x=>String(x.id)===String(iid));if(!it)return;const v=Number(value);if(!Number.isFinite(v)||v<0||v===Number(groupRate||0))delete it.rateOverride;else it.rateOverride=v;p.updatedAt=Date.now();writeProjects(ps)}
  function enhanceRows(){
    const {id,p}=active();if(!id||!p)return;
    document.querySelectorAll('#tool-pricing .pricing-group').forEach(sec=>{
      const g=p.data?.groups?.find(x=>String(x.id)===String(sec.dataset.g));if(!g||g.mode!=='hours')return;
      sec.querySelectorAll('.pricing-row').forEach(row=>{
        const it=g.items?.find(x=>String(x.id)===String(row.dataset.i));if(!it||row.querySelector('.pr-row-rate-v351'))return;
        const qty=row.querySelector('.pr-qty');if(!qty)return;
        let rateCell=qty.nextElementSibling;if(!rateCell)return;
        const wrap=document.createElement('label');wrap.className='pr-row-rate-wrap';wrap.title='Individuální sazba pro tento řádek. Když ji vrátíš na sazbu sekce, řádek zase používá sazbu sekce.';
        const input=document.createElement('input');input.type='number';input.min='0';input.step='50';input.className='pr-row-rate pr-row-rate-v351';input.value=effectiveRate(g,it);
        const hint=document.createElement('small');hint.textContent='Kč/h';wrap.append(input,hint);rateCell.replaceWith(wrap);
        const commit=()=>{persistRate(id,g.id,it.id,input.value,g.rate);refreshAll()};input.addEventListener('change',commit);input.addEventListener('blur',commit);qty.addEventListener('change',()=>setTimeout(refreshAll,0));
      })
    })
  }
  function refreshAll(){
    const {id,p}=active();if(!id||!p)return;const fresh=readProjects().find(x=>x.id===id)||p,s=calcProject(fresh);
    document.querySelectorAll('#tool-pricing .pricing-group').forEach(sec=>{
      const g=fresh.data?.groups?.find(x=>String(x.id)===String(sec.dataset.g));if(!g)return;let gt=0;
      sec.querySelectorAll('.pricing-row').forEach(row=>{const it=g.items?.find(x=>String(x.id)===String(row.dataset.i));if(!it||it.on===false)return;if(g.mode==='hours'){const q=Number(row.querySelector('.pr-qty')?.value??it.qty)||0;const r=Number(row.querySelector('.pr-row-rate-v351')?.value);const rr=Number.isFinite(r)?r:effectiveRate(g,it);const total=q*rr;gt+=total;const sum=row.querySelector('.sum');if(sum)sum.textContent=money(total)}else gt+=Number(row.querySelector('.pr-price')?.value??it.price)||0});
      const strong=sec.querySelector('.pricing-group-head strong');if(strong)strong.textContent=money(gt)
    });
    const boxes=[...document.querySelectorAll('#tool-pricing .pricing-key b')];if(boxes[0])boxes[0].textContent=`${s.hours} h`;if(boxes[1])boxes[1].textContent=money(s.arch);if(boxes[2])boxes[2].textContent=money(s.prof);if(boxes[3])boxes[3].textContent=money(s.net);if(boxes[4])boxes[4].textContent=money(s.gross);
    const rows=[...document.querySelectorAll('#tool-pricing .pricing-summary-row')];if(rows[0]?.querySelector('b'))rows[0].querySelector('b').textContent=money(s.arch);if(rows[1]?.querySelector('b'))rows[1].querySelector('b').textContent=money(s.prof);if(rows[2]?.querySelector('b'))rows[2].querySelector('b').textContent=money(s.net);if(rows[3]?.querySelector('b'))rows[3].querySelector('b').textContent=money(s.vat);if(rows[4]?.querySelector('b'))rows[4].querySelector('b').textContent=money(s.gross)
  }
  function refreshCards(){document.querySelectorAll('#tool-pricing .pricing-project-card').forEach(card=>{const p=readProjects().find(x=>x.id===card.dataset.id),price=card.querySelector('.price');if(p&&price)price.textContent=money(calcProject(p).net)})}
  function style(){if(document.getElementById('pricing-row-rate-v351-style'))return;const s=document.createElement('style');s.id='pricing-row-rate-v351-style';s.textContent=`
    #tool-pricing .pr-row-rate-wrap{display:flex;align-items:center;gap:4px;min-width:0;background:#fffef3;border:1px solid #d4cc5d;border-radius:7px;padding:2px 5px}
    #tool-pricing .pr-row-rate-wrap input{width:100%;min-width:0;border:0!important;background:transparent!important;padding:5px 2px!important;text-align:right;font-weight:700}
    #tool-pricing .pr-row-rate-wrap small{font-size:8px;color:#71717a;white-space:nowrap}
    #tool-pricing .pr-row-rate-wrap:focus-within{outline:2px solid #d4cc5d;outline-offset:1px}
  `;document.head.appendChild(s)}
  function enhance(){style();migrateLegacy();enhanceRows();refreshAll();refreshCards()}
  function init(){enhance();const root=document.getElementById('tool-pricing');if(root)new MutationObserver(()=>requestAnimationFrame(enhance)).observe(root,{childList:true,subtree:true})}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();