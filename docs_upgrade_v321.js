(()=>{
  const APP_VERSION='V3.25';

  function forceVersion(){
    const el=document.getElementById('app-version');
    if(el&&el.textContent!==APP_VERSION) el.textContent=APP_VERSION;
  }

  function lockVersion(){
    forceVersion();
    const el=document.getElementById('app-version');
    if(!el||el.dataset.v321Locked)return;
    el.dataset.v321Locked='1';
    new MutationObserver(forceVersion).observe(el,{childList:true,characterData:true,subtree:true});
  }

  function injectCss(){
    if(document.getElementById('docs-v321-style'))return;
    const s=document.createElement('style');s.id='docs-v321-style';s.textContent=`
      #tool-docs .docs-v321-overview{margin:14px 0 16px;padding:14px;border:1px solid var(--border);border-radius:10px;background:#fafafa}
      #tool-docs .docs-v321-overview h2{font:normal 14px 'Antarctican Mono',monospace;margin:0 0 4px}
      #tool-docs .docs-v321-overview>p{font-size:11px;color:var(--muted);margin:0 0 10px;line-height:1.5}
      #tool-docs .docs-v321-grid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:8px}
      #tool-docs .docs-v321-card{border:1px solid var(--border);background:#fff;border-radius:8px;padding:10px;text-align:left;cursor:pointer;min-height:88px}
      #tool-docs .docs-v321-card:hover{background:#fffef3;border-color:#d4cc5d}
      #tool-docs .docs-v321-card b{display:block;font-size:11px;margin-bottom:4px}.docs-v321-card span{font-size:9px;color:var(--muted);line-height:1.4;display:block}
      #tool-docs .docs-v321-badge{display:inline-flex!important;width:auto;margin-top:6px;border:1px solid #d4d4d8;border-radius:999px;padding:2px 6px;font-size:8px!important;color:#52525b!important;background:#f4f4f5}
      @media(max-width:1000px){#tool-docs .docs-v321-grid{grid-template-columns:repeat(3,1fr)}}
      @media(max-width:650px){#tool-docs .docs-v321-grid{grid-template-columns:1fr 1fr}}
    `;document.head.appendChild(s);
  }

  function removeLegacyOperations(){
    document.querySelector('#tool-docs [data-doc-tab="operations"]')?.remove();
    document.getElementById('docs-operations')?.remove();
    document.querySelector('#docs-v321-overview [data-go="operations"]')?.remove();
  }

  function addOverview(){
    const host=document.getElementById('tool-docs');if(!host||document.getElementById('docs-v321-overview')){removeLegacyOperations();return;}
    const tabs=host.querySelector('.docs-tabs');if(!tabs)return;
    const box=document.createElement('div');box.id='docs-v321-overview';box.className='docs-v321-overview';
    box.innerHTML=`<h2>DOKUMENTAČNÍ NÁSTROJE — PŘEHLED</h2><p>Workflow: technická kontrola PDF → seznam výkresů → názvy souborů → porovnání revizí → kontrola textových změn.</p>
    <div class="docs-v321-grid">
      <button class="docs-v321-card" data-go="preflight"><b>1 · Pre-flight PDF</b><span>Formát, velikost, PDF/A deklarace, prázdné strany, duplicity, čísla výkresů a konzistence.</span><span class="docs-v321-badge">KONTROLA</span></button>
      <button class="docs-v321-card" data-go="drawinglist"><b>2 · Seznam výkresů</b><span>Čtení rozpisky, číslo, název, měřítko a stupeň dokumentace s ruční opravou.</span><span class="docs-v321-badge">EVIDENCE</span></button>
      <button class="docs-v321-card" data-go="renamer"><b>3 · Přejmenování</b><span>Bezpečné názvy kopií podle prefixu a čísla výkresu, originály zůstávají beze změny.</span><span class="docs-v321-badge">POŘÁDEK</span></button>
      <button class="docs-v321-card" data-go="compare"><b>4 · Porovnání PDF</b><span>Kontrola změn mezi starou a novou revizí ve stejném měřítku.</span><span class="docs-v321-badge">REVIZE</span></button>
    </div>`;
    tabs.parentNode.insertBefore(box,tabs);
    box.querySelectorAll('[data-go]').forEach(b=>b.onclick=()=>window.openDocsSection?.(b.dataset.go));
    removeLegacyOperations();
  }

  function improveLabels(){
    const pre=document.querySelector('#docs-preflight>.muted');if(pre)pre.textContent='Hromadná technická předkontrola PDF: formát a orientace stran, počet stran, velikost souboru, podezřele prázdné stránky, deklarace PDF/A, duplicity a konzistence čísel výkresů/revizí.';
    const ren=document.querySelector('#docs-renamer>.muted');if(ren)ren.textContent='Připraví bezpečné nové názvy kopií podle jednotného vzoru a stáhne je v ZIPu. Originály se nikdy nepřejmenovávají ani nemažou.';
    const cmp=document.querySelector('#docs-compare>.muted');if(cmp)cmp.textContent='Nahraj starší a novější revizi. Nástroj je zarovná do stejného měřítka a zobrazí rozdíly; vhodné pro rychlou kontrolu změn výkresu, ne jako náhrada autorské kontroly.';
  }

  function init(){lockVersion();injectCss();addOverview();removeLegacyOperations();improveLabels();setTimeout(()=>{lockVersion();removeLegacyOperations()},300);setTimeout(()=>{lockVersion();removeLegacyOperations()},1500)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();