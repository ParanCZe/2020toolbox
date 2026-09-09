(()=>{
  const VERSION='V3.25';
  const WHATSNEW_KEY='20-20-toolbox-whatsnew-seen';

  function css(){
    if(document.getElementById('norms-v315b-style')) return;
    const st=document.createElement('style');
    st.id='norms-v315b-style';
    st.textContent=`
      #tool-norms .ny-entry,#tool-norms .ny-result{cursor:pointer;position:relative;transition:.15s}
      #tool-norms .ny-entry:hover,#tool-norms .ny-result:hover{border-color:#a1a1aa;background:#fffef3;box-shadow:0 2px 7px rgba(0,0,0,.05)}
      #tool-norms .ny-link{display:none!important}
      #tool-norms .ny-note,#tool-norms .ny-entry p,#tool-norms .ny-result p{font-size:14px!important;line-height:1.65!important;color:#27272a!important;margin-top:7px!important}
      #tool-norms .ny-meta{font-size:10px!important;line-height:1.45!important}
      #tool-norms .ny-value{font-size:13px!important;line-height:1.45!important}
      #tool-norms .ny-entry::after,#tool-norms .ny-result::after{content:'Kliknutím otevřít přesný zdroj ↗';display:block;margin-top:9px;font-size:9px;color:#71717a}
      #tool-norms .ny-entry:focus-visible,#tool-norms .ny-result:focus-visible{outline:2px solid #18181b;outline-offset:2px}
      #tool-norms .ny-sources{margin:12px 0 14px;padding:13px 14px;border:1px solid var(--border);border-radius:10px;background:#fafafa}
      #tool-norms .ny-sources-head{display:flex;align-items:flex-end;justify-content:space-between;gap:12px;margin-bottom:9px;flex-wrap:wrap}
      #tool-norms .ny-sources-title{font:normal 12px 'Antarctican Mono',monospace;letter-spacing:.2px}
      #tool-norms .ny-sources-note{font-size:9px;color:var(--muted);line-height:1.45}
      #tool-norms .ny-sources-links{display:flex;gap:7px;flex-wrap:wrap}
      #tool-norms .ny-source-btn{display:inline-flex;align-items:center;gap:6px;text-decoration:none;border:1px solid #d4d4d8;background:#fff;color:var(--text);border-radius:7px;padding:8px 10px;font-size:10px;line-height:1.2;transition:.15s}
      #tool-norms .ny-source-btn:hover{background:#fffef3;border-color:#d4cc5d;transform:translateY(-1px)}
      #tool-norms .ny-source-btn strong{font-weight:600}
      #tool-norms .ny-source-btn span{color:var(--muted);font-size:9px}
      @media(max-width:620px){#tool-norms .ny-source-btn{width:100%;justify-content:space-between}}
    `;
    document.head.appendChild(st);
  }

  function loadScript(src,flag,done){
    if(window[flag]){done?.();return;}
    const s=document.createElement('script');
    s.src=src;
    s.onload=()=>{window[flag]=true;done?.()};
    s.onerror=()=>{console.warn('Databázový balík se nepodařilo načíst:',src);done?.()};
    document.head.appendChild(s);
  }

  function loadNormExtras(done){
    loadScript('norms_extra_v316.js?v=316','__TOOLBOX_NORMS_EXTRA_316',()=>{
      loadScript('norms_extra_v317.js?v=317','__TOOLBOX_NORMS_EXTRA_317',()=>{
        loadScript('interior_extra_v318.js?v=318','__TOOLBOX_INTERIOR_EXTRA_318',()=>{
          loadScript('interior_extra_v319.js?v=319','__TOOLBOX_INTERIOR_EXTRA_319',()=>{
            loadScript('interior_extra_v320.js?v=320','__TOOLBOX_INTERIOR_EXTRA_320',done);
          });
        });
      });
    });
  }

  function itemFromCard(card){
    const raw=(card.id||'').replace(/^ny-/,'');
    return (window.TOOLBOX_NORMS_V314Y||[]).find(x=>String(x.id)===raw)||null;
  }

  function sectionTarget(section){
    const s=String(section||'').trim();
    if(!s) return null;
    const par=s.match(/§\s*(\d+)\s*(?:odst\.\s*(\d+))?\s*(?:písm\.\s*([a-z]))?/i);
    if(!par) return null;
    return {paragraph:par[1],subsection:par[2]||'',letter:(par[3]||'').toLowerCase()};
  }

  function textFragment(target){
    if(!target) return '';
    if(target.subsection && target.letter){
      const start=`(${target.subsection})`;
      const end=`${target.letter})`;
      return `:~:text=${encodeURIComponent(start)},${encodeURIComponent(end)}`;
    }
    if(target.subsection) return `:~:text=${encodeURIComponent(`(${target.subsection})`)}`;
    return '';
  }

  function exactSourceUrl(item){
    if(!item||!item.url) return '';
    let url=String(item.url);
    if(/zakonyprolidi\.cz\/cs\//i.test(url)){
      const target=sectionTarget(item.section);
      if(target){
        const base=url.split('#')[0];
        url=base+'#p'+target.paragraph+textFragment(target);
      }
    }
    return url;
  }

  function openCard(card){
    const item=itemFromCard(card);
    const url=exactSourceUrl(item);
    if(url) window.open(url,'_blank','noopener');
  }

  function enhanceCards(root=document){
    root.querySelectorAll?.('#tool-norms .ny-entry,#tool-norms .ny-result').forEach(card=>{
      if(card.dataset.v315bReady) return;
      card.dataset.v315bReady='1';
      card.setAttribute('role','link');
      card.setAttribute('tabindex','0');
      card.setAttribute('title','Otevřít konkrétní část zdroje');
      card.addEventListener('click',e=>{e.preventDefault();e.stopImmediatePropagation();openCard(card)},true);
      card.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();openCard(card)}});
    });
  }

  function addNormSources(){
    const host=document.getElementById('tool-norms');
    if(!host||document.getElementById('ny-sources')) return;
    const panel=document.createElement('div');
    panel.id='ny-sources';
    panel.className='ny-sources';
    panel.innerHTML=`
      <div class="ny-sources-head">
        <div class="ny-sources-title">ZDROJE</div>
        <div class="ny-sources-note">Jednotlivé karty níže otevírají konkrétní paragraf nebo odstavec, pokud je dostupný.</div>
      </div>
      <div class="ny-sources-links">
        <a class="ny-source-btn" href="https://www.zakonyprolidi.cz/cs/2024-146" target="_blank" rel="noopener"><strong>Vyhláška 146/2024 Sb.</strong><span>Zákony pro lidi ↗</span></a>
        <a class="ny-source-btn" href="https://www.zakonyprolidi.cz/cs/2024-131" target="_blank" rel="noopener"><strong>Vyhláška 131/2024 Sb.</strong><span>Zákony pro lidi ↗</span></a>
        <a class="ny-source-btn" href="https://csnonline.agentura-cas.cz/" target="_blank" rel="noopener"><strong>ČSN Online</strong><span>Agentura ČAS ↗</span></a>
      </div>`;
    const anchor=host.querySelector('.ny-hero')||host.firstElementChild;
    if(anchor) host.insertBefore(panel,anchor); else host.prepend(panel);
  }

  function observeNorms(){
    const host=document.getElementById('tool-norms');
    if(!host) return;
    addNormSources();
    enhanceCards(document);
    const mo=new MutationObserver(()=>{addNormSources();enhanceCards(host)});
    mo.observe(host,{childList:true,subtree:true});
  }

  function addMaterialLibraryLauncher(){
    const menu=document.querySelector('.menu-app-groups')||document.querySelector('.menu-app-row')||document.querySelector('.grid');
    if(!menu||document.getElementById('material-library-launcher')) return;
    const btn=document.createElement('button');
    btn.id='material-library-launcher';
    btn.className='tile';
    btn.type='button';
    btn.innerHTML='<b>Knihovna materiálů <span class="menu-status">ONLINE</span></b><span>Chytré hledání detailů, textur a materiálových referencí pro AI.</span>';
    btn.addEventListener('click',()=>{window.location.href='material_library_v4.html'});
    const beta=menu.querySelector?.('.menu-app-row.beta');
    if(beta) beta.appendChild(btn); else menu.appendChild(btn);
  }

  function setupWhatsNew(){
    const modal=document.getElementById('toolbox-whatsnew');
    if(!modal) return;
    const ver=modal.querySelector('.whatsnew-ver');
    if(ver) ver.textContent=VERSION;
    const body=modal.querySelector('.whatsnew-body');
    if(body) body.innerHTML=`
      <div class="whatsnew-item"><strong>Interiérové standardy — +224 dalších položek</strong><span>Knihovna je výrazně hustší: další rozměry a ergonomie pro kuchyně, koupelny, šatny, předsíně, ložnice, obýváky, pracovny, jídelny, gastro, retail, hotely, děti, školy a obecné interiérové situace.</span></div>
      <div class="whatsnew-item"><strong>Interiérové standardy — doporučení vs. předpis</strong><span>Nové ergonomické karty jsou jasně vedené jako doporučení nebo běžný rozměr, aby se nepletly se závaznými předpisy.</span></div>
      <div class="whatsnew-item"><strong>Normy — rozšířená databáze</strong><span>Projektantská databáze NORMY zůstává načtená současně.</span></div>`;

    window.closeToolboxWhatsNew=function(){modal.classList.remove('active');try{localStorage.setItem(WHATSNEW_KEY,VERSION)}catch(e){}};
    let seen='';try{seen=localStorage.getItem(WHATSNEW_KEY)||''}catch(e){}
    if(seen!==VERSION){setTimeout(()=>modal.classList.add('active'),300)}
  }

  function afterExtras(){
    css();
    observeNorms();
    addMaterialLibraryLauncher();
    setupWhatsNew();
  }

  function init(){loadNormExtras(afterExtras)}
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',init,{once:true}); else init();
})();