(()=>{
  const PROJECTS_STORE='toolbox.pricingOffer.projects.v346';
  const ACTIVE_STORE='toolbox.pricingOffer.active.v346';
  const RATE_STORE='toolbox.pricingOffer.rowRates.v352';
  const LEGACY_RATE_STORE='toolbox.pricingOffer.rowRates.v350';
  const money=n=>new Intl.NumberFormat('cs-CZ',{style:'currency',currency:'CZK',maximumFractionDigits:0}).format(Number(n)||0);
  let observer=null;
  function readProjects(){try{return JSON.parse(localStorage.getItem(PROJECTS_STORE)||'[]')||[]}catch(_){return[]}}
  function readRates(){try{const n=JSON.parse(localStorage.getItem(RATE_STORE)||'null');if(n&&typeof n==='object')return n;const old=JSON.parse(localStorage.getItem(LEGACY_RATE_STORE)||'{}')||{};localStorage.setItem(RATE_STORE,JSON.stringify(old));return old}catch(_){return{}}}
  function writeRates(x){localStorage.setItem(RATE_STORE,JSON.stringify(x))}
  function active(){const id=localStorage.getItem(ACTIVE_STORE);const ps=readProjects();return {id,p:ps.find(x=>x.id===id)||null}}
  function key(pid,gid,iid){return `${pid}|${gid}|${iid}`}
  function effectiveRate(pid,g,it,map){const k=key(pid,g.id,it.id);if(Object.prototype.hasOwnProperty.call(map,k)){const v=Number(map[k]);if(Number.isFinite(v)&&v>=0)return v}return Number(g.rate)||0}
  function calcProject(p,map){let arch=0,prof=0,hours=0;for(const g of p?.data?.groups||[]){for(const it of g.items||[]){if(it.on===false)continue;if(g.mode==='hours'){const q=Number(it.qty)||0;hours+=q;arch+=q*effectiveRate(p.id,g,it,map)}else prof+=Number(it.price)||0}}const net=arch+prof,vat=net*(Number(p?.data?.vat)||0)/100;return {arch,prof,hours,net,vat,gross:net+vat}}
  function style(){if(document.getElementById('pricing-row-rate-v352-style'))return;const s=document.createElement('style');s.id='pricing-row-rate-v352-style';s.textContent=`
    #tool-pricing .pr-row-rate-wrap-v352{display:flex;align-items:center;gap:5px;min-width:0;background:#fff;border:1px solid #d4cc5d;border-radius:7px;padding:2px 5px}
    #tool-pricing .pr-row-rate-wrap-v352 input{width:100%;min-width:0;border:0!important;background:transparent!important;padding:5px 2px!important;text-align:right;font-weight:700}
    #tool-pricing .pr-row-rate-wrap-v352 small{font-size:8px;color:#71717a;white-space:nowrap}
    #tool-pricing .pr-row-rate-wrap-v352:focus-within{outline:2px solid #d4cc5d;outline-offset:1px;background:#fffef3}
  `;document.head.appendChild(s)}
  function enhanceRows(){
    const {id,p}=active();if(!id||!p)return;const map=readRates();
    document.querySelectorAll('#tool-pricing .pricing-group').forEach(sec=>{
      const g=p.data?.groups?.find(x=>String(x.id)===String(sec.dataset.g));if(!g||g.mode!=='hours')return;
      sec.querySelectorAll('.pricing-row').forEach(row=>{
        const it=g.items?.find(x=>String(x.id)===String(row.dataset.i));if(!it)return;
        const qty=row.querySelector('.pr-qty');if(!qty)return;
        let wrap=row.querySelector('.pr-row-rate-wrap-v352');
        if(!wrap){
          const rateCell=qty.nextElementSibling;if(!rateCell)return;
          wrap=document.createElement('label');wrap.className='pr-row-rate-wrap-v352';wrap.title='Sazba pouze pro tento řádek. Výchozí sazba sekce zůstane pro ostatní položky.';
          const input=document.createElement('input');input.type='number';input.min='0';input.step='50';input.className='pr-row-rate-v352';
          const unit=document.createElement('small');unit.textContent='Kč/h';wrap.append(input,unit);rateCell.replaceWith(wrap);
          const commit=()=>{const rates=readRates(),v=Number(input.value),k=key(id,g.id,it.id);if(!Number.isFinite(v)||v<0||v===Number(g.rate||0))delete rates[k];else rates[k]=v;writeRates(rates);refreshAll()};
          input.addEventListener('input',()=>setTimeout(refreshAll,0));input.addEventListener('change',commit);input.addEventListener('blur',commit);
        }
        const input=wrap.querySelector('.pr-row-rate-v352');if(input&&document.activeElement!==input)input.value=effectiveRate(id,g,it,map);
      })
    })
  }
  function refreshAll(){
    const {id,p}=active();if(!id||!p)return;const map=readRates(),s=calcProject(p,map);
    document.querySelectorAll('#tool-pricing .pricing-group').forEach(sec=>{
      const g=p.data?.groups?.find(x=>String(x.id)===String(sec.dataset.g));if(!g)return;let gt=0;
      sec.querySelectorAll('.pricing-row').forEach(row=>{const it=g.items?.find(x=>String(x.id)===String(row.dataset.i));if(!it||it.on===false)return;if(g.mode==='hours'){const q=Number(row.querySelector('.pr-qty')?.value??it.qty)||0;const raw=row.querySelector('.pr-row-rate-v352')?.value;const r=raw===''?effectiveRate(id,g,it,map):Number(raw);const rr=Number.isFinite(r)?r:effectiveRate(id,g,it,map);const total=q*rr;gt+=total;const sum=row.querySelector('.sum');if(sum)sum.textContent=money(total)}else gt+=Number(row.querySelector('.pr-price')?.value??it.price)||0});const strong=sec.querySelector('.pricing-group-head strong');if(strong)strong.textContent=money(gt)
    });
    const b=[...document.querySelectorAll('#tool-pricing .pricing-key b')];if(b[0])b[0].textContent=`${s.hours} h`;if(b[1])b[1].textContent=money(s.arch);if(b[2])b[2].textContent=money(s.prof);if(b[3])b[3].textContent=money(s.net);if(b[4])b[4].textContent=money(s.gross);
    const r=[...document.querySelectorAll('#tool-pricing .pricing-summary-row')];if(r[0]?.querySelector('b'))r[0].querySelector('b').textContent=money(s.arch);if(r[1]?.querySelector('b'))r[1].querySelector('b').textContent=money(s.prof);if(r[2]?.querySelector('b'))r[2].querySelector('b').textContent=money(s.net);if(r[3]?.querySelector('b'))r[3].querySelector('b').textContent=money(s.vat);if(r[4]?.querySelector('b'))r[4].querySelector('b').textContent=money(s.gross)
  }
  function enhance(){const root=document.getElementById('tool-pricing');if(!root)return false;style();enhanceRows();refreshAll();if(!observer){observer=new MutationObserver(()=>requestAnimationFrame(()=>{enhanceRows();refreshAll()}));observer.observe(root,{childList:true,subtree:true})}return true}
  function boot(){if(enhance())return;let tries=0;const t=setInterval(()=>{tries++;if(enhance()||tries>40)clearInterval(t)},100)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();