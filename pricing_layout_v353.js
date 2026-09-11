(()=>{
  function apply(){
    const root=document.getElementById('tool-pricing');
    if(!root)return;
    if(!document.getElementById('pricing-layout-v356fix-style')){
      const s=document.createElement('style');s.id='pricing-layout-v356fix-style';s.textContent=`
        #tool-pricing .pricing-settings{grid-template-columns:1.3fr 1fr .65fr .65fr .7fr!important}
        #tool-pricing .pricing-columns,#tool-pricing .pricing-row{grid-template-columns:34px 52px minmax(280px,1fr) 82px 112px 120px 64px 30px!important;gap:7px!important;align-items:center}
        #tool-pricing .pricing-row .pr-name{width:100%;min-width:0}
        #tool-pricing .pricing-row .pr-qty{width:100%;min-width:0}
        #tool-pricing .pricing-row .sum{text-align:right;white-space:nowrap}
        #tool-pricing .pricing-row .pr-row-rate-wrap{width:100%;min-width:0}
        #tool-pricing .pricing-row .pr-price{width:100%;min-width:0;text-align:right}
        #tool-pricing .pricing-row .pr-desc{display:none!important;visibility:hidden!important;width:0!important;min-width:0!important;max-width:0!important;padding:0!important;margin:0!important;border:0!important}
        @media(max-width:1000px){#tool-pricing .pricing-settings{grid-template-columns:1fr 1fr!important}#tool-pricing .pricing-row{grid-template-columns:28px 46px minmax(180px,1fr) 72px 96px 105px 58px 28px!important}}
      `;document.head.appendChild(s);
    }
    root.querySelectorAll('.pricing-group').forEach(sec=>{
      const cols=sec.querySelector('.pricing-columns');
      if(cols&&cols.dataset.v356fix!=='1'){
        const isHours=!!sec.querySelector('.pr-qty');
        cols.innerHTML=isHours
          ?'<span></span><span>Č.</span><span>Pracovní balíček</span><span>Hodiny</span><span>Sazba Kč/h</span><span>Cena bez DPH</span><span></span><span></span>'
          :'<span></span><span>Č.</span><span>Profese</span><span></span><span></span><span>Cena bez DPH</span><span></span><span></span>';
        cols.dataset.v356fix='1';
      }
    });
  }
  function init(){apply();const root=document.getElementById('tool-pricing');if(root)new MutationObserver(()=>requestAnimationFrame(apply)).observe(root,{childList:true,subtree:true})}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();