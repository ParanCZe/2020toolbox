(()=>{
  const RELEASE='V3.45';
  const SEEN_KEY='toolbox.whatsnew.seen.'+RELEASE;

  function setVersion(){
    const el=document.getElementById('app-version');
    if(el&&el.textContent!==RELEASE)el.textContent=RELEASE;
    document.querySelectorAll('[data-app-version]').forEach(x=>{if(x.textContent!==RELEASE)x.textContent=RELEASE});
  }

  function removeLegacyWhatsNew(){
    const buttons=[...document.querySelectorAll('button,input[type="button"],input[type="submit"]')];
    buttons.forEach(btn=>{
      if(btn.closest('#toolbox-release-overlay'))return;
      const label=(btn.textContent||btn.value||'').trim().toLowerCase();
      if(label!=='rozumím'&&label!=='rozumim')return;
      let n=btn.parentElement;
      for(let i=0;i<7&&n&&n!==document.body;i++,n=n.parentElement){
        if(n.id==='toolbox-release-overlay'||n.id==='toolbox-release-window')return;
        const t=(n.textContent||'');
        if(/co je nového/i.test(t)&&t.length<7000){n.remove();return}
      }
    });
  }

  function injectStyle(){
    if(document.getElementById('release-ui-v341-style'))return;
    const s=document.createElement('style');s.id='release-ui-v341-style';s.textContent=`
      #toolbox-release-overlay{position:fixed;inset:0;z-index:2147483000;background:rgba(15,23,42,.38);display:flex;align-items:center;justify-content:center;padding:24px}
      #toolbox-release-window{width:min(620px,calc(100vw - 32px));max-height:min(78vh,760px);overflow:auto;background:#fff;border:1px solid #d4d4d8;border-radius:14px;box-shadow:0 24px 80px rgba(0,0,0,.28);padding:22px 24px;color:#111}
      #toolbox-release-window h2{margin:0 0 12px;font-size:18px;line-height:1.2}
      #toolbox-release-window p{margin:0 0 10px;font-size:12px;line-height:1.55}
      #toolbox-release-window ul{margin:8px 0 18px;padding-left:18px;font-size:12px;line-height:1.55}
      #toolbox-release-window button{border:1px solid #111;background:#fff;border-radius:7px;padding:7px 12px;font-size:12px;cursor:pointer}
      #toolbox-release-window button:hover{background:#f4f4f5}
      @media print{#toolbox-release-overlay,[data-no-export="1"]{display:none!important}}
    `;document.head.appendChild(s);
  }

  function closeWhatsNew(){localStorage.setItem(SEEN_KEY,'1');document.getElementById('toolbox-release-overlay')?.remove()}
  function showWhatsNew(){
    if(localStorage.getItem(SEEN_KEY)==='1'||document.getElementById('toolbox-release-overlay'))return;
    const overlay=document.createElement('div');overlay.id='toolbox-release-overlay';overlay.dataset.noExport='1';
    overlay.innerHTML=`<div id="toolbox-release-window" role="dialog" aria-modal="true" aria-labelledby="toolbox-release-title"><h2 id="toolbox-release-title">Co je nového — ${RELEASE}</h2><p>Aktualizace 20-20 TOOLBOX.</p><ul><li>Nová aplikace „Cenová nabídka“ podle zaslané šablony nacenění projektu.</li><li>Volitelné řádky, hodinové sazby pro fáze a pevné ceny profesí/inženýringu.</li><li>Automatické součty za fáze i celková suma a export přes Tisk / PDF.</li><li>Rozpracovaná nabídka se ukládá lokálně v prohlížeči.</li></ul><button type="button" id="toolbox-release-ok">Rozumím</button></div>`;
    overlay.addEventListener('click',e=>{if(e.target===overlay)closeWhatsNew()});
    overlay.querySelector('#toolbox-release-ok').addEventListener('click',closeWhatsNew);
    document.body.appendChild(overlay);
  }

  function init(){injectStyle();removeLegacyWhatsNew();setVersion();showWhatsNew();setTimeout(()=>setVersion(),300);setTimeout(()=>setVersion(),1200)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();