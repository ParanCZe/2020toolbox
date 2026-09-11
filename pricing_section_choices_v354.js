(()=>{
  const PROJECTS_STORE='toolbox.pricingOffer.projects.v346';
  const ACTIVE_STORE='toolbox.pricingOffer.active.v346';
  const uid=p=>p+Date.now()+Math.random().toString(36).slice(2,6);
  const PRESETS={
    STUDIE:{mode:'hours',rate:1400,items:['zaměření, průzkumy, dokumentace, zadání','dispoziční řešení, varianty, zázemí a výdej, konzum.','vizualizace, tvorba modelu']},
    DUR:{mode:'hours',rate:1200,items:['podklady a průzkumy','koordinační situace','zpracování dokumentace DUR','koordinace profesí','zapracování připomínek']},
    DSP:{mode:'hours',rate:1200,items:['gastro projekt, spolupráce na tvorbě','revize a zpracování návrhu technologií TZB','PBŘ a koordinace','tvorba dokumentace pro DSP, PDF…','koordinace profesí']},
    DPS:{mode:'hours',rate:1000,items:['řešení interiéru - materiály, barevnost, detaily, vzorky','povrchy','vývodový plán','rozkres prvků interiéru','výběr mobiliáře, uměleckých děl…','exteriér - označení, stínění']},
    AD:{mode:'hours',rate:1600,items:['čas na kontrolních dnech po dobu realizace','čas na úpravě výkresů po dobu realizace','konzultace se zhotovitelem','kontrola vzorků a detailů','řešení změn během realizace']},
    PROFESE:{mode:'fixed',rate:0,items:['ZTI','VZT','CHL, VYTÁP','ELE SILNO','ELE SLABO','EPS','PBŘ','STATIKA','SHZ','GASTRO','TECHNOLOGICKÉ CHLAZENÍ']},
    INŽENÝRING:{mode:'fixed',rate:0,items:['DUR','DSP','KOLAUDACE','vyjádření DOSS','správci sítí','stavební úřad']}
  };
  const GENERIC_HOURS=['zaměření a podklady','návrh a konzultace','koordinace','zpracování dokumentace','revize a úpravy','jednání / kontrolní den'];
  const GENERIC_FIXED=['externí profese','správní poplatek','inženýring','autorský / technický dozor'];
  const read=()=>{try{return JSON.parse(localStorage.getItem(PROJECTS_STORE)||'[]')||[]}catch(_){return[]}};
  const write=x=>localStorage.setItem(PROJECTS_STORE,JSON.stringify(x));
  function active(){const id=localStorage.getItem(ACTIVE_STORE),ps=read();return{id,ps,p:ps.find(x=>x.id===id)||null}}
  function normName(n){n=String(n||'').trim().toUpperCase();if(n==='PROVÁDĚČKA'||n==='PROVÁDĚCÍ DOKUMENTACE')return'DPS';if(n==='INZENYRING')return'INŽENÝRING';return n}
  function presetFor(g){return PRESETS[normName(g?.name)]||null}
  function sectionExists(p,name){const n=normName(name);return (p?.data?.groups||[]).some(g=>normName(g.name)===n)}
  function saveAndReopen(ps,id){write(ps);if(window.openPricingOffer){window.openPricingOffer();setTimeout(()=>{document.querySelector(`.pricing-project-card[data-id="${CSS.escape(id)}"] .pr-open`)?.click()},30)}}
  function addSection(type){
    const {id,ps,p}=active();if(!id||!p)return;
    let def=PRESETS[type],name=type,mode=def?.mode||'hours',rate=def?.rate||Number(p.data?.defaultRate)||0,items=[];
    if(type==='CUSTOM'){
      name=(prompt('Název vlastní sekce:','VLASTNÍ SEKCE')||'').trim();if(!name)return;
      if(sectionExists(p,name)){alert(`Sekce „${name}“ už v nabídce je.`);return}
      mode=confirm('OK = hodinová sekce, Zrušit = pevné ceny')?'hours':'fixed';rate=mode==='hours'?(Number(p.data?.defaultRate)||0):0;
    }else{
      if(sectionExists(p,name)){alert(`Sekce „${name}“ už v nabídce je.`);return}
      items=(def.items||[]).map(name=>({id:uid('i'),on:true,name,description:'',qty:0,price:0}));
    }
    p.data.groups=p.data.groups||[];p.data.groups.push({id:uid('g'),name,mode,rate,items});p.updatedAt=Date.now();saveAndReopen(ps,id)
  }
  function syncSectionMenu(){
    const {p}=active();if(!p)return;
    document.querySelectorAll('#tool-pricing .pr-section-menu [data-section]').forEach(b=>{
      if(b.dataset.section==='CUSTOM')return;
      const used=sectionExists(p,b.dataset.section);b.disabled=used;b.title=used?'Tato sekce už je v nabídce.':'';
    })
  }
  function installSectionButton(){
    const actions=document.querySelector('#tool-pricing .pricing-actions');if(!actions)return;
    if(actions.querySelector('.pr-add-section-v354')){syncSectionMenu();return}
    ['#pr-add-arch','#pr-add-prof','#pr-add-custom'].forEach(sel=>actions.querySelector(sel)?.remove());
    const wrap=document.createElement('div');wrap.className='pr-add-section-wrap';wrap.innerHTML=`<button type="button" class="action pr-add-section-v354">+ Přidat sekci</button><div class="pr-section-menu" hidden>${['STUDIE','DUR','DSP','DPS','AD','PROFESE','INŽENÝRING'].map(x=>`<button type="button" data-section="${x}">${x}</button>`).join('')}<button type="button" data-section="CUSTOM">Vlastní…</button></div>`;
    actions.prepend(wrap);
    const btn=wrap.querySelector('.pr-add-section-v354'),menu=wrap.querySelector('.pr-section-menu');
    btn.onclick=e=>{e.stopPropagation();syncSectionMenu();menu.hidden=!menu.hidden};
    menu.querySelectorAll('[data-section]').forEach(b=>b.onclick=e=>{e.stopPropagation();if(b.disabled)return;menu.hidden=true;addSection(b.dataset.section)});
    document.addEventListener('click',()=>{menu.hidden=true},{once:true});syncSectionMenu();
  }
  function setRowName(row,value){const input=row.querySelector('.pr-name');if(!input)return;input.value=value;input.dispatchEvent(new Event('change',{bubbles:true}))}
  function installRowChoices(){
    const {p}=active();if(!p)return;
    document.querySelectorAll('#tool-pricing .pricing-group').forEach(sec=>{
      const g=p.data?.groups?.find(x=>String(x.id)===String(sec.dataset.g));if(!g)return;
      const preset=presetFor(g),opts=preset?.items||(g.mode==='fixed'?GENERIC_FIXED:GENERIC_HOURS);
      sec.querySelectorAll('.pricing-row').forEach(row=>{
        if(row.querySelector('.pr-row-choice-v354'))return;
        const input=row.querySelector('.pr-name');if(!input)return;
        const current=input.value.trim(),wrap=document.createElement('div');wrap.className='pr-row-choice-wrap';
        const select=document.createElement('select');select.className='pr-row-choice-v354';
        select.innerHTML='<option value="">— vyber položku —</option>'+opts.map(x=>`<option value="${x.replace(/&/g,'&amp;').replace(/"/g,'&quot;')}">${x}</option>`).join('')+'<option value="__custom__">Vlastní…</option>';
        const known=opts.includes(current);select.value=known?current:(current?'__custom__':'');
        input.parentNode.insertBefore(wrap,input);wrap.append(select,input);input.classList.add('pr-custom-row-v354');input.style.display=select.value==='__custom__'?'block':'none';input.placeholder='Vlastní položka';
        select.onchange=()=>{if(select.value==='__custom__'){input.style.display='block';input.focus();if(known)setRowName(row,'')}else{input.style.display='none';setRowName(row,select.value)}};
      })
    })
  }
  function style(){if(document.getElementById('pricing-section-choices-v354-style'))return;const s=document.createElement('style');s.id='pricing-section-choices-v354-style';s.textContent=`
    #tool-pricing .pr-add-section-wrap{position:relative;display:inline-flex}
    #tool-pricing .pr-section-menu{position:absolute;left:0;bottom:calc(100% + 6px);z-index:1000;min-width:190px;background:#fff;border:1px solid var(--border);border-radius:9px;box-shadow:0 12px 30px rgba(0,0,0,.14);padding:6px}
    #tool-pricing .pr-section-menu button{display:block;width:100%;text-align:left;border:0;background:#fff;padding:8px 9px;border-radius:6px;cursor:pointer;font:inherit}
    #tool-pricing .pr-section-menu button:hover:not(:disabled){background:#fffef3}
    #tool-pricing .pr-section-menu button:disabled{opacity:.35;cursor:not-allowed;text-decoration:line-through}
    #tool-pricing .pr-row-choice-wrap{display:flex;flex-direction:column;gap:5px;min-width:0;width:100%}
    #tool-pricing .pr-row-choice-wrap select,#tool-pricing .pr-row-choice-wrap input{width:100%;min-width:0}
  `;document.head.appendChild(s)}
  function apply(){style();installSectionButton();installRowChoices();syncSectionMenu()}
  function init(){apply();const root=document.getElementById('tool-pricing');if(root)new MutationObserver(()=>requestAnimationFrame(apply)).observe(root,{childList:true,subtree:true})}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();