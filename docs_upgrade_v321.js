(()=>{
  const APP_VERSION='V3.23';

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
      #tool-docs .docs-v321-operations{border-top:1px solid var(--border);padding-top:12px}
      #tool-docs .docs-v321-box{border:1px solid var(--border);border-radius:9px;background:#fafafa;padding:12px;margin:10px 0}
      #tool-docs .docs-v321-box h3{font:normal 13px 'Antarctican Mono',monospace;margin:0 0 5px}
      #tool-docs .docs-v321-box p{font-size:10px;color:var(--muted);line-height:1.45;margin:0 0 10px}
      #tool-docs .docs-v321-row{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
      #tool-docs .docs-v321-row input[type=file]{max-width:100%}
      #tool-docs .docs-v321-row input[type=text]{min-width:230px}
      #tool-docs .docs-v321-status{margin-top:8px;font-size:10px;color:var(--muted)}
      @media(max-width:1000px){#tool-docs .docs-v321-grid{grid-template-columns:repeat(3,1fr)}}
      @media(max-width:650px){#tool-docs .docs-v321-grid{grid-template-columns:1fr 1fr}}
    `;document.head.appendChild(s);
  }

  function addOverview(){
    const host=document.getElementById('tool-docs');if(!host||document.getElementById('docs-v321-overview'))return;
    const tabs=host.querySelector('.docs-tabs');if(!tabs)return;
    const box=document.createElement('div');box.id='docs-v321-overview';box.className='docs-v321-overview';
    box.innerHTML=`<h2>DOKUMENTAČNÍ NÁSTROJE — PŘEHLED</h2><p>Prošel jsem workflow jako jeden celek: kontrola PDF → seznam výkresů → názvy souborů → porovnání revizí → finální PDF operace.</p>
    <div class="docs-v321-grid">
      <button class="docs-v321-card" data-go="preflight"><b>1 · Pre-flight PDF</b><span>Formát, velikost, PDF/A deklarace, prázdné strany, duplicity, čísla výkresů a konzistence.</span><span class="docs-v321-badge">KONTROLA</span></button>
      <button class="docs-v321-card" data-go="drawinglist"><b>2 · Seznam výkresů</b><span>Čtení rozpisky, číslo, název, měřítko a stupeň dokumentace s ruční opravou.</span><span class="docs-v321-badge">EVIDENCE</span></button>
      <button class="docs-v321-card" data-go="renamer"><b>3 · Přejmenování</b><span>Bezpečné názvy kopií podle prefixu a čísla výkresu, originály zůstávají beze změny.</span><span class="docs-v321-badge">POŘÁDEK</span></button>
      <button class="docs-v321-card" data-go="compare"><b>4 · Porovnání PDF</b><span>Kontrola změn mezi starou a novou revizí ve stejném měřítku.</span><span class="docs-v321-badge">REVIZE</span></button>
      <button class="docs-v321-card" data-go="operations"><b>5 · PDF operace</b><span>Chybějící produkční krok: spojení PDF a vytažení vybraných stran bez rasterizace.</span><span class="docs-v321-badge">NOVÉ</span></button>
    </div>`;
    tabs.parentNode.insertBefore(box,tabs);
    box.querySelectorAll('[data-go]').forEach(b=>b.onclick=()=>window.openDocsSection?.(b.dataset.go));
  }

  function addOperationsTab(){
    const host=document.getElementById('tool-docs');if(!host||document.getElementById('docs-operations'))return;
    const tabs=host.querySelector('.docs-tabs');if(!tabs)return;
    const tab=document.createElement('button');tab.className='docs-tab';tab.dataset.docTab='operations';tab.textContent='PDF operace';tab.onclick=()=>window.openDocsSection?.('operations');tabs.appendChild(tab);
    const sec=document.createElement('div');sec.id='docs-operations';sec.className='docs-section docs-v321-operations';
    sec.innerHTML=`<h1 style="font-size:18px">PDF operace</h1><div class="muted">Praktické operace, které v dokumentačním workflow chyběly. Stránky zůstávají vektorové; nic se nerasterizuje.</div>
      <div class="docs-v321-box"><h3>Spojit více PDF</h3><p>Sloučí vybraná PDF v pořadí, v jakém je nahraješ. Zachová původní stránky a jejich rozměry.</p><div class="docs-v321-row"><input id="docsMergeFiles" type="file" accept=".pdf,application/pdf" multiple><button class="action" id="docsMergeBtn">Spojit a stáhnout</button></div><div id="docsMergeStatus" class="docs-v321-status">Připraveno.</div></div>
      <div class="docs-v321-box"><h3>Vyjmout vybrané strany</h3><p>Z jednoho PDF vytvoří nové PDF jen z vybraných stran. Zadání např. <b>1-3, 5, 8-10</b>.</p><div class="docs-v321-row"><input id="docsExtractFile" type="file" accept=".pdf,application/pdf"><input id="docsExtractPages" type="text" placeholder="1-3, 5, 8-10"><button class="action" id="docsExtractBtn">Vyjmout a stáhnout</button></div><div id="docsExtractStatus" class="docs-v321-status">Připraveno.</div></div>
      <div class="docs-note">PDF operace používají PDF-lib už načtený v Toolboxu. Neprovádějí OCR, kompresi ani převod do PDF/A.</div>`;
    host.appendChild(sec);
    document.getElementById('docsMergeBtn').onclick=mergePdfs;
    document.getElementById('docsExtractBtn').onclick=extractPages;
  }

  function patchOpenDocsSection(){
    if(window.__docsV321Patched)return;window.__docsV321Patched=true;
    const original=window.openDocsSection;
    window.openDocsSection=function(name){
      if(name==='operations'){
        document.querySelectorAll('#tool-docs .docs-section').forEach(x=>x.classList.remove('active'));
        document.querySelectorAll('#tool-docs .docs-tab').forEach(x=>x.classList.toggle('active',x.dataset.docTab==='operations'));
        document.getElementById('docs-operations')?.classList.add('active');return;
      }
      return original?.(name);
    };
  }

  function downloadBytes(bytes,name){
    const blob=new Blob([bytes],{type:'application/pdf'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1500);
  }

  async function mergePdfs(){
    const st=document.getElementById('docsMergeStatus'),files=[...(document.getElementById('docsMergeFiles')?.files||[])];
    if(!files.length){st.textContent='Vyber alespoň jedno PDF.';return}
    if(!window.PDFLib?.PDFDocument){st.textContent='PDF-lib není dostupný.';return}
    try{st.textContent='Spojuji…';const out=await PDFLib.PDFDocument.create();let pages=0;
      for(const f of files){const src=await PDFLib.PDFDocument.load(await f.arrayBuffer(),{ignoreEncryption:true});const idx=Array.from({length:src.getPageCount()},(_,i)=>i);const copied=await out.copyPages(src,idx);copied.forEach(p=>out.addPage(p));pages+=copied.length}
      const bytes=await out.save();downloadBytes(bytes,'SPOJENA_DOKUMENTACE.pdf');st.textContent=`Hotovo: ${files.length} PDF · ${pages} stran.`;
    }catch(e){st.textContent='Chyba: '+(e.message||e)}
  }

  function parseRanges(s,max){
    const out=[];for(const raw of String(s||'').split(',')){const p=raw.trim();if(!p)continue;const m=p.match(/^(\d+)\s*-\s*(\d+)$/);if(m){let a=+m[1],b=+m[2];if(a>b)[a,b]=[b,a];for(let i=a;i<=b;i++)if(i>=1&&i<=max)out.push(i-1)}else if(/^\d+$/.test(p)){const n=+p;if(n>=1&&n<=max)out.push(n-1)}}return [...new Set(out)];
  }

  async function extractPages(){
    const st=document.getElementById('docsExtractStatus'),f=document.getElementById('docsExtractFile')?.files?.[0],range=document.getElementById('docsExtractPages')?.value||'';
    if(!f){st.textContent='Vyber PDF.';return}if(!window.PDFLib?.PDFDocument){st.textContent='PDF-lib není dostupný.';return}
    try{st.textContent='Zpracovávám…';const src=await PDFLib.PDFDocument.load(await f.arrayBuffer(),{ignoreEncryption:true}),idx=parseRanges(range,src.getPageCount());if(!idx.length){st.textContent=`Neplatný rozsah. PDF má ${src.getPageCount()} stran.`;return}const out=await PDFLib.PDFDocument.create(),copied=await out.copyPages(src,idx);copied.forEach(p=>out.addPage(p));const bytes=await out.save();downloadBytes(bytes,(f.name.replace(/\.pdf$/i,'')||'PDF')+'_VYBRANE_STRANY.pdf');st.textContent=`Hotovo: ${copied.length} stran z ${src.getPageCount()}.`;
    }catch(e){st.textContent='Chyba: '+(e.message||e)}
  }

  function improveLabels(){
    const pre=document.querySelector('#docs-preflight>.muted');if(pre)pre.textContent='Hromadná technická předkontrola PDF: formát a orientace stran, počet stran, velikost souboru, podezřele prázdné stránky, deklarace PDF/A, duplicity a konzistence čísel výkresů/revizí.';
    const ren=document.querySelector('#docs-renamer>.muted');if(ren)ren.textContent='Připraví bezpečné nové názvy kopií podle jednotného vzoru a stáhne je v ZIPu. Originály se nikdy nepřejmenovávají ani nemažou.';
    const cmp=document.querySelector('#docs-compare>.muted');if(cmp)cmp.textContent='Nahraj starší a novější revizi. Nástroj je zarovná do stejného měřítka a zobrazí rozdíly; vhodné pro rychlou kontrolu změn výkresu, ne jako náhrada autorské kontroly.';
  }

  function init(){lockVersion();injectCss();addOverview();addOperationsTab();patchOpenDocsSection();improveLabels();setTimeout(lockVersion,300);setTimeout(lockVersion,1500)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();