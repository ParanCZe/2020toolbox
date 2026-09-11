(()=>{
  const PROJECTS_STORE='toolbox.pricingOffer.projects.v346';
  const ACTIVE_STORE='toolbox.pricingOffer.active.v346';
  const PROFESSIONS=['ZTI','VZT','CHL, VYTÁP','ELE SILNO','ELE SLABO','EPS','PBŘ','STATIKA','SHZ','GASTRO','TECHNOLOGICKÉ CHLAZENÍ'];
  let creating=false;
  const uid=p=>p+Date.now()+Math.random().toString(36).slice(2,6);
  const read=()=>{try{return JSON.parse(localStorage.getItem(PROJECTS_STORE)||'[]')||[]}catch(_){return[]}};
  const write=p=>localStorage.setItem(PROJECTS_STORE,JSON.stringify(p));
  function template(){return [
    {id:uid('g'),name:'STUDIE',mode:'hours',rate:1400,items:[
      {id:uid('i'),on:true,name:'zaměření, průzkumy, dokumentace, zadání',description:'',qty:0,price:0},
      {id:uid('i'),on:true,name:'dispoziční řešení, varianty, zázemí a výdej, konzum.',description:'',qty:0,price:0},
      {id:uid('i'),on:true,name:'vizualizace, tvorba modelu',description:'',qty:0,price:0}
    ]},
    {id:uid('g'),name:'DSP',mode:'hours',rate:1200,items:[
      {id:uid('i'),on:true,name:'gastro projekt, spolupráce na tvorbě',description:'',qty:0,price:0},
      {id:uid('i'),on:true,name:'revize a zpracování návrhu technologií TZB',description:'',qty:0,price:0},
      {id:uid('i'),on:true,name:'PBŘ a koordinace',description:'',qty:0,price:0},
      {id:uid('i'),on:true,name:'tvorba dokumentace pro DSP, PDF…',description:'',qty:0,price:0},
      {id:uid('i'),on:true,name:'koordinace profesí',description:'',qty:0,price:0}
    ]},
    {id:uid('g'),name:'PROVÁDĚČKA',mode:'hours',rate:1000,items:[
      {id:uid('i'),on:true,name:'řešení interiéru - materiály, barevnost, detaily, vzorky',description:'',qty:0,price:0},
      {id:uid('i'),on:true,name:'povrchy',description:'',qty:0,price:0},
      {id:uid('i'),on:true,name:'vývodový plán',description:'',qty:0,price:0},
      {id:uid('i'),on:true,name:'rozkres prvků interiéru',description:'',qty:0,price:0},
      {id:uid('i'),on:true,name:'výběr mobiliáře, uměleckých děl…',description:'',qty:0,price:0},
      {id:uid('i'),on:true,name:'exteriér - označení, stínění',description:'',qty:0,price:0}
    ]},
    {id:uid('g'),name:'AD',mode:'hours',rate:1600,items:[
      {id:uid('i'),on:true,name:'čas na kontrolních dnech po dobu realizace',description:'',qty:0,price:0},
      {id:uid('i'),on:true,name:'čas na úpravě výkresů po dobu realizace',description:'',qty:0,price:0}
    ]},
    {id:uid('g'),name:'PROFESE',mode:'fixed',rate:0,items:PROFESSIONS.map(name=>({id:uid('i'),on:true,name,description:'',qty:0,price:0}))},
    {id:uid('g'),name:'INŽENÝRING',mode:'fixed',rate:0,items:[
      {id:uid('i'),on:true,name:'DSP',description:'',qty:0,price:0},
      {id:uid('i'),on:true,name:'KOLAUDACE',description:'',qty:0,price:0}
    ]}
  ]}
  function seedNewProject(){
    if(!creating)return;
    const active=localStorage.getItem(ACTIVE_STORE);if(!active)return;
    const projects=read(),p=projects.find(x=>x.id===active);if(!p||!p.data||!Array.isArray(p.data.groups)||p.data.groups.length)return;
    p.data.groups=template();p.updatedAt=Date.now();write(projects);creating=false;
    if(window.openPricingOffer){const id=active;window.openPricingOffer();setTimeout(()=>{const card=document.querySelector(`.pricing-project-card[data-id="${CSS.escape(id)}"] .pr-open`);card?.click()},30)}
  }
  function setName(row,value){const input=row.querySelector('.pr-name');if(!input)return;input.value=value;input.dispatchEvent(new Event('change',{bubbles:true}))}
  function enhanceProfessions(){
    document.querySelectorAll('#tool-pricing .pricing-group').forEach(sec=>{
      const active=localStorage.getItem(ACTIVE_STORE),projects=read(),p=projects.find(x=>x.id===active),g=p?.data?.groups?.find(x=>String(x.id)===String(sec.dataset.g));
      if(!g||g.mode!=='fixed')return;
      sec.querySelectorAll('.pricing-row').forEach(row=>{
        if(row.querySelector('.pr-prof-choice'))return;
        const input=row.querySelector('.pr-name');if(!input)return;
        const current=input.value.trim();
        const wrap=document.createElement('div');wrap.className='pr-prof-wrap';
        const select=document.createElement('select');select.className='pr-prof-choice';
        select.innerHTML='<option value="">— vyber profesi —</option>'+PROFESSIONS.map(x=>`<option value="${x.replace(/"/g,'&quot;')}">${x}</option>`).join('')+'<option value="__custom__">Vlastní…</option>';
        const known=PROFESSIONS.includes(current);select.value=known?current:(current?'__custom__':'');
        input.parentNode.insertBefore(wrap,input);wrap.appendChild(select);wrap.appendChild(input);
        input.classList.add('pr-custom-prof');input.style.display=select.value==='__custom__'?'block':'none';input.placeholder='Vlastní profese';
        select.onchange=()=>{if(select.value==='__custom__'){input.style.display='block';input.focus();if(known)setName(row,'')}else{input.style.display='none';setName(row,select.value)}};
      })
    })
  }
  function style(){if(document.getElementById('pricing-prof-v349-style'))return;const s=document.createElement('style');s.id='pricing-prof-v349-style';s.textContent=`
    #tool-pricing .pr-prof-wrap{display:flex;flex-direction:column;gap:5px;min-width:0}
    #tool-pricing .pr-prof-wrap select,#tool-pricing .pr-prof-wrap input{width:100%;min-width:0}
  `;document.head.appendChild(s)}
  function init(){
    style();
    document.addEventListener('click',e=>{if(e.target.closest('#pr-new-project')){creating=true;setTimeout(seedNewProject,80);setTimeout(seedNewProject,250);setTimeout(seedNewProject,700)}},true);
    const root=document.getElementById('tool-pricing')||document.body;
    new MutationObserver(()=>requestAnimationFrame(()=>{seedNewProject();enhanceProfessions()})).observe(root,{childList:true,subtree:true});
    enhanceProfessions();
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();