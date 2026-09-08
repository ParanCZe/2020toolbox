(()=>{
  const VERSION='V3.15b';
  const WHATSNEW_KEY='20-20-toolbox-whatsnew-seen';

  function css(){
    if(document.getElementById('norms-v315b-style')) return;
    const st=document.createElement('style');
    st.id='norms-v315b-style';
    st.textContent=`
      /* V3.15b — celé normové karty jsou odkazy na přesný zdroj */
      #tool-norms .ny-entry,#tool-norms .ny-result{cursor:pointer;position:relative;transition:.15s}
      #tool-norms .ny-entry:hover,#tool-norms .ny-result:hover{border-color:#a1a1aa;background:#fffef3;box-shadow:0 2px 7px rgba(0,0,0,.05)}
      #tool-norms .ny-link{display:none!important}
      #tool-norms .ny-note,#tool-norms .ny-entry p,#tool-norms .ny-result p{font-size:12px!important;line-height:1.65!important;color:#27272a!important;margin-top:7px!important}
      #tool-norms .ny-meta{font-size:10px!important;line-height:1.45!important}
      #tool-norms .ny-value{font-size:13px!important;line-height:1.45!important}
      #tool-norms .ny-entry::after,#tool-norms .ny-result::after{content:'Kliknutím otevřít přesný zdroj ↗';display:block;margin-top:9px;font-size:9px;color:#71717a}
      #tool-norms .ny-entry:focus-visible,#tool-norms .ny-result:focus-visible{outline:2px solid #18181b;outline-offset:2px}
    `;
    document.head.appendChild(st);
  }

  function itemFromCard(card){
    const raw=(card.id||'').replace(/^ny-/,'');
    return (window.TOOLBOX_NORMS_V314Y||[]).find(x=>String(x.id)===raw)||null;
  }

  function sectionAnchor(section){
    const s=String(section||'').trim();
    if(!s) return '';
    // ZakonyProlidi používají např. #p29, #p29-3, #p39-3-a.
    const par=s.match(/§\s*(\d+)\s*(?:odst\.\s*(\d+))?\s*(?:písm\.\s*([a-z]))?/i);
    if(par){
      let a='#p'+par[1];
      if(par[2]) a+='-'+par[2];
      if(par[3]) a+='-'+par[3].toLowerCase();
      return a;
    }
    return '';
  }

  function exactSourceUrl(item){
    if(!item||!item.url) return '';
    let url=String(item.url);
    if(/zakonyprolidi\.cz\/cs\//i.test(url)){
      const anchor=sectionAnchor(item.section);
      if(anchor){
        url=url.split('#')[0]+anchor;
      }
    }
    return url;
  }

  function openCard(card){
    const item=itemFromCard(card);
    const url=exactSourceUrl(item);
    if(!url) return;
    window.open(url,'_blank','noopener');
  }

  function enhanceCards(root=document){
    root.querySelectorAll?.('#tool-norms .ny-entry,#tool-norms .ny-result').forEach(card=>{
      if(card.dataset.v315bReady) return;
      card.dataset.v315bReady='1';
      card.setAttribute('role','link');
      card.setAttribute('tabindex','0');
      card.setAttribute('title','Otevřít konkrétní část zdroje');
      card.addEventListener('click',e=>{
        e.preventDefault();
        e.stopImmediatePropagation();
        openCard(card);
      },true);
      card.addEventListener('keydown',e=>{
        if(e.key==='Enter'||e.key===' '){e.preventDefault();openCard(card)}
      });
    });
  }

  function observeNorms(){
    const host=document.getElementById('tool-norms');
    if(!host) return;
    enhanceCards(document);
    const mo=new MutationObserver(()=>enhanceCards(host));
    mo.observe(host,{childList:true,subtree:true});
  }

  function setupWhatsNew(){
    const modal=document.getElementById('toolbox-whatsnew');
    if(!modal) return;
    const ver=modal.querySelector('.whatsnew-ver');
    if(ver) ver.textContent=VERSION;
    const body=modal.querySelector('.whatsnew-body');
    if(body) body.innerHTML=`
      <div class="whatsnew-item"><strong>Normy — přesné odkazy na zdroj</strong><span>Celá karta normy je nyní klikací. U právních předpisů se otevírá přímo konkrétní paragraf / odstavec, ne začátek celé vyhlášky.</span></div>
      <div class="whatsnew-item"><strong>Normy — čitelnější obsah</strong><span>Zvětšeno znění a vysvětlení pod jednotlivými normovými položkami.</span></div>
      <div class="whatsnew-item"><strong>Interiérové standardy</strong><span>Rozšířená databáze a chytré vyhledávání rozměrů, odstupů, výšek a ergonomických doporučení.</span></div>
      <div class="whatsnew-item"><strong>Opravy aktualizací</strong><span>Opraveno zobrazování čísla verze a spouštění okna „Co je nového“ po nové aktualizaci.</span></div>`;

    window.closeToolboxWhatsNew=function(){
      modal.classList.remove('active');
      try{localStorage.setItem(WHATSNEW_KEY,VERSION)}catch(e){}
    };
    let seen='';
    try{seen=localStorage.getItem(WHATSNEW_KEY)||''}catch(e){}
    if(seen!==VERSION){setTimeout(()=>modal.classList.add('active'),300)}
  }

  function init(){css();observeNorms();setupWhatsNew();}
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',init,{once:true}); else init();
})();
