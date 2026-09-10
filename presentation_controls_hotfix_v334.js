(()=>{
  function stopDragOnControls(root=document){
    root.querySelectorAll?.('.pm-mini-tools,.mb-mini-tools,.pm-crop-confirm,.mb-crop-confirm').forEach(el=>{
      if(el.dataset.v334Stop)return;
      el.dataset.v334Stop='1';
      el.addEventListener('pointerdown',e=>e.stopPropagation());
      el.addEventListener('mousedown',e=>e.stopPropagation());
      el.addEventListener('touchstart',e=>e.stopPropagation(),{passive:true});
    });
    root.querySelectorAll?.('.presentation-media-item').forEach(el=>{
      if(el.dataset.v334Wrapped)return;
      const orig=el.onpointerdown;
      if(typeof orig==='function'){
        el.onpointerdown=function(e){
          if(e.target?.closest?.('.pm-mini-tools,.pm-crop-edit,.pm-crop-confirm'))return;
          return orig.call(this,e);
        };
      }
      el.dataset.v334Wrapped='1';
    });
    root.querySelectorAll?.('.pm-crop-edit,.mb-crop-edit').forEach(el=>{
      if(el.dataset.v334Crop)return;
      el.dataset.v334Crop='1';
      el.querySelectorAll('button').forEach(b=>{
        b.addEventListener('pointerdown',e=>e.stopPropagation());
        b.addEventListener('mousedown',e=>e.stopPropagation());
      });
    });
  }

  function init(){
    stopDragOnControls();
    const obs=new MutationObserver(muts=>{
      for(const m of muts) for(const n of m.addedNodes){
        if(n.nodeType===1) stopDragOnControls(n.matches?.('.presentation-media-item,.moodboard-cell,.pm-crop-edit,.mb-crop-edit')?n:n);
      }
    });
    obs.observe(document.documentElement,{childList:true,subtree:true});
    setInterval(stopDragOnControls,700);
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();
