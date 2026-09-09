(()=>{
  const APP_VERSION='V3.24';
  const normalize=s=>String(s||'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/\s+/g,' ').trim();
  function forceVersion(){const el=document.getElementById('app-version');if(el)el.textContent=APP_VERSION;}
  function ensureFilter(){
    const sec=document.getElementById('docs-textcheck');if(!sec||document.getElementById('textcheck-filter-wrap'))return;
    const results=document.getElementById('textcheck-results');if(!results)return;
    const box=document.createElement('div');box.id='textcheck-filter-wrap';box.className='textcheck-filter-wrap';
    box.innerHTML=`<label for="textcheck-filter"><b>HLEDAT VE ZMĚNÁCH</b><span>Zobrazí jen nálezy, kde se výraz objevuje ve starém nebo novém textu.</span></label><div class="textcheck-filter-row"><input id="textcheck-filter" type="search" placeholder="např. schodiště, zábradlí, 1,5 m…" autocomplete="off"><button class="back-btn" id="textcheck-filter-clear" type="button">Vymazat</button><span id="textcheck-filter-count" class="muted" style="margin:0"></span></div>`;
    results.parentNode.insertBefore(box,results);
    const input=document.getElementById('textcheck-filter'),clear=document.getElementById('textcheck-filter-clear');
    input.addEventListener('input',applyFilter);clear.addEventListener('click',()=>{input.value='';applyFilter();input.focus();});
    const mo=new MutationObserver(()=>applyFilter());mo.observe(results,{childList:true,subtree:false});
    applyFilter();
  }
  function cardText(card){
    const cols=card.querySelectorAll('.textcheck-cols p'),vals=card.querySelector('.textcheck-values');
    return normalize([...cols].map(x=>x.textContent||'').join(' ')+' '+(vals?.textContent||''));
  }
  function applyFilter(){
    const input=document.getElementById('textcheck-filter'),host=document.getElementById('textcheck-results'),count=document.getElementById('textcheck-filter-count');if(!input||!host)return;
    const q=normalize(input.value),cards=[...host.querySelectorAll('.textcheck-card')];let shown=0;
    for(const c of cards){const ok=!q||cardText(c).includes(q);c.style.display=ok?'':'none';if(ok)shown++;}
    const summary=host.querySelector('.textcheck-summary');if(summary)summary.style.display=q?'none':'';
    let empty=host.querySelector('.textcheck-filter-empty');
    if(q&&cards.length&&shown===0){if(!empty){empty=document.createElement('div');empty.className='docs-empty textcheck-filter-empty';host.appendChild(empty);}empty.textContent=`Pro „${input.value.trim()}“ nebyla mezi nalezenými změnami žádná shoda.`;empty.style.display='';}
    else if(empty)empty.style.display='none';
    if(count)count.textContent=cards.length?(q?`Zobrazeno ${shown} z ${cards.length} nálezů`:`Celkem ${cards.length} nálezů`):'';
  }
  function css(){if(document.getElementById('textcheck-filter-v324-style'))return;const s=document.createElement('style');s.id='textcheck-filter-v324-style';s.textContent=`#tool-docs .textcheck-filter-wrap{margin:16px 0 10px;padding:12px;border:1px solid var(--border);border-radius:9px;background:#fffef3}.textcheck-filter-wrap>label{display:flex;justify-content:space-between;gap:10px;align-items:flex-end;flex-wrap:wrap;margin-bottom:8px}.textcheck-filter-wrap>label b{font:normal 12px 'Antarctican Mono',monospace}.textcheck-filter-wrap>label span{font-size:9px;color:var(--muted)}.textcheck-filter-row{display:flex;gap:8px;align-items:center;flex-wrap:wrap}.textcheck-filter-row input{flex:1;min-width:260px;min-height:38px;font-size:12px}.textcheck-filter-row .back-btn{margin:0}.textcheck-filter-row .muted{font-size:10px}@media(max-width:650px){.textcheck-filter-row input{min-width:100%;width:100%}}`;document.head.appendChild(s);}
  function init(){forceVersion();css();ensureFilter();setTimeout(()=>{forceVersion();ensureFilter();},400);setTimeout(forceVersion,1600);}
  window.textcheckApplyFilter=applyFilter;
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();