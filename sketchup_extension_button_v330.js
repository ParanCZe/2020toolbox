(()=>{
  const RBZ='https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/SketchUpExtension/20-20-Toolbox-Print.rbz';

  function inject(){
    document.getElementById('print3d-sketchup-extension-box')?.remove();
    document.getElementById('print3d-sketchup-extension-top')?.remove();

    const tool=document.getElementById('tool-3dprint') || document.querySelector('[data-tool="3dprint"]') || document.querySelector('.tool-3dprint');
    if(!tool || document.getElementById('print3d-sketchup-extension-btn')) return;

    const back=[...tool.querySelectorAll('button.back-btn')].find(b=>String(b.getAttribute('onclick')||'').includes('closeTool'));
    if(!back) return;

    const btn=document.createElement('a');
    btn.id='print3d-sketchup-extension-btn';
    btn.className='back-btn';
    btn.href=RBZ;
    btn.download='20-20-Toolbox-Print.rbz';
    btn.textContent='↓ SketchUp extension';
    btn.title='Stáhnout 20-20 Toolbox extension pro odeslání modelu ze SketchUpu do 3D tisku';
    btn.style.cssText='margin:0 0 0 7px;text-decoration:none;display:inline-flex;align-items:center;justify-content:center;vertical-align:middle;white-space:nowrap';
    back.insertAdjacentElement('afterend',btn);
  }

  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',inject,{once:true}); else inject();
  const obs=new MutationObserver(inject);
  obs.observe(document.documentElement,{childList:true,subtree:true});
})();
