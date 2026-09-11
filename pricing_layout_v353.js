(()=>{
  function apply(){
    const root=document.getElementById('tool-pricing');
    if(!root)return;

    if(!document.getElementById('pricing-layout-v356-style')){
      const s=document.createElement('style');
      s.id='pricing-layout-v356-style';
      s.textContent=`
        #tool-pricing .pricing-settings{grid-template-columns:1.3fr 1fr .65fr .65fr .7fr!important}
        #tool-pricing .pricing-columns,#tool-pricing .pricing-row{
          grid-template-columns:34px 52px minmax(300px,1fr) 82px 112px 120px 64px 30px!important;
          gap:7px!important;align-items:center!important
        }
        #tool-pricing .pricing-row .pr-desc{display:none!important}
        #tool-pricing .pricing-row .pr-name,
        #tool-pricing .pricing-row .pr-row-choice-wrap,
        #tool-pricing .pricing-row .pr-qty,
        #tool-pricing .pricing-row .pr-row-rate-wrap,
        #tool-pricing .pricing-row .pr-price{width:100%!important;min-width:0!important}
        #tool-pricing .pricing-row .sum{text-align:right!important;white-space:nowrap!important}
        #tool-pricing .pricing-row .pr-row-rate-wrap{grid-column:auto!important}
        @media(max-width:1000px){
          #tool-pricing .pricing-settings{grid-template-columns:1fr 1fr!important}
          #tool-pricing .pricing-row{grid-template-columns:28px 46px minmax(190px,1fr) 72px 96px 105px 58px 28px!important}
        }
      `;
      document.head.appendChild(s);
    }

    root.querySelectorAll('.pricing-group').forEach(sec=>{
      const isHours=!!sec.querySelector('.pr-qty');
      const cols=sec.querySelector('.pricing-columns');
      if(cols){
        cols.innerHTML=isHours
          ?'<span></span><span>Č.</span><span>Pracovní balíček</span><span>Hodiny</span><span>Sazba Kč/h</span><span>Cena bez DPH</span><span></span><span></span>'
          :'<span></span><span>Č.</span><span>Profese</span><span></span><span></span><span>Cena bez DPH</span><span></span><span></span>';
        cols.dataset.v356='1';
      }

      sec.querySelectorAll('.pricing-row').forEach(row=>{
        row.querySelectorAll('.pr-desc').forEach(el=>el.remove());
      });
    });
  }

  let scheduled=false;
  function scheduleApply(){
    if(scheduled)return;
    scheduled=true;
    requestAnimationFrame(()=>{scheduled=false;apply()});
  }
  function init(){
    apply();
    const root=document.getElementById('tool-pricing');
    if(root)new MutationObserver(scheduleApply).observe(root,{childList:true,subtree:true});
    setTimeout(apply,150);
    setTimeout(apply,500);
    setTimeout(apply,1200);
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();