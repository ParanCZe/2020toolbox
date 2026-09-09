(()=>{
  const RBZ='https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/SketchUpExtension/20-20-Toolbox-Print.rbz';
  function inject(){
    const old=document.getElementById('print3d-sketchup-extension-box');
    if(old) old.remove();
    if(document.getElementById('print3d-sketchup-extension-top')) return;

    const tool=document.getElementById('tool-3dprint') || document.querySelector('[data-tool="3dprint"]') || document.querySelector('.tool-3dprint');
    if(!tool) return;

    const firstCard=tool.querySelector('.card');
    const firstContent=firstCard || tool.firstElementChild;
    if(!firstContent) return;

    const bar=document.createElement('div');
    bar.id='print3d-sketchup-extension-top';
    bar.style.cssText='display:flex;align-items:center;justify-content:space-between;gap:14px;flex-wrap:wrap;margin:0 0 14px;padding:12px 14px;border:1px solid var(--border,#e4e4e7);border-radius:10px;background:#fffef3';
    bar.innerHTML=`
      <div style="min-width:220px;flex:1">
        <div style="font:normal 12px 'Antarctican Mono',monospace;margin-bottom:3px">SKETCHUP → 3D TISK</div>
        <div style="font-size:10px;color:var(--muted,#71717a);line-height:1.4">Nainstaluj extension a posílej model ze SketchUpu rovnou sem jedním kliknutím.</div>
      </div>
      <a class="action" href="${RBZ}" download="20-20-Toolbox-Print.rbz" style="margin:0;text-decoration:none;display:inline-flex;align-items:center;justify-content:center;white-space:nowrap">↓ Stáhnout SketchUp extension</a>`;

    firstContent.insertBefore(bar, firstContent.firstChild);
  }

  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',inject,{once:true}); else inject();
  const obs=new MutationObserver(inject);
  obs.observe(document.documentElement,{childList:true,subtree:true});
})();
