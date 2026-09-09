(()=>{
  const RBZ='https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/SketchUpExtension/20-20-Toolbox-Print.rbz';
  function inject(){
    if(document.getElementById('print3d-sketchup-extension-box')) return;
    const status=document.getElementById('print3d-prusa-bridge-status');
    if(!status) return;
    const host=status.closest('.print3d-box') || status.parentElement;
    if(!host || !host.parentElement) return;
    const box=document.createElement('div');
    box.id='print3d-sketchup-extension-box';
    box.className='print3d-box';
    box.innerHTML=`
      <h3>SKETCHUP EXTENSION</h3>
      <div class="print3d-estimate-note" style="margin-bottom:10px">Po instalaci můžeš ve SketchUpu jedním kliknutím poslat aktuální model přímo do aplikace 3D tisk.</div>
      <div class="print3d-actions">
        <a class="action" href="${RBZ}" download="20-20-Toolbox-Print.rbz" style="margin:0;text-decoration:none;display:inline-flex;align-items:center;justify-content:center">↓ Stáhnout SketchUp extension</a>
      </div>`;
    host.parentElement.insertBefore(box,host.nextSibling);
  }
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',inject,{once:true}); else inject();
  const obs=new MutationObserver(inject);
  obs.observe(document.documentElement,{childList:true,subtree:true});
})();
