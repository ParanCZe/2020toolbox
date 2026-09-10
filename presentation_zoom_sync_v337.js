(()=>{
  let busy=false,timer=0,lastKey='';
  function visible(){const m=document.getElementById('preview-modal');return !!m&&getComputedStyle(m).display!=='none'}
  function metric(){const c=document.getElementById('preview-canvas');if(!c)return'';const r=c.getBoundingClientRect();return [window.devicePixelRatio||1,window.visualViewport?.scale||1,window.innerWidth,window.innerHeight,Math.round(r.width*10)/10,Math.round(r.height*10)/10].join('|')}
  function rebuildPageOverlays(){
    const layer=document.getElementById('boxes-layer');if(!layer)return;
    document.querySelectorAll('.custom-text-box,.moodboard-cell').forEach(el=>el.remove());
    const p=Number((typeof currentPreviewPage!=='undefined'&&currentPreviewPage)||1);
    const data=(typeof allPagesTexts!=='undefined'&&allPagesTexts[p])||null;
    if(data&&data.type==='moodboard'){
      if(typeof renderMoodboardOverlay==='function')renderMoodboardOverlay(p,data.cells||[]);
      return;
    }
    if(Array.isArray(data)){
      data.forEach(b=>{try{if(b.type==='line')createLineElement?.(b);else createBoxElement?.(b)}catch(e){console.warn('Overlay rebuild',e)}});
    }
  }
  async function resync(){
    if(busy||!visible())return;busy=true;
    try{
      // First fit only the sheet. Do NOT rerender the whole page here: that used to
      // recreate overlays using the pre-fit canvas dimensions and caused zoom drift.
      window.fitPresentationCanvas?.();
      await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
      rebuildPageOverlays();
      document.dispatchEvent(new CustomEvent('presentation-zoom-resynced'));
    }catch(e){console.warn('Presentation zoom resync',e)}finally{busy=false;lastKey=metric()}
  }
  function queue(){clearTimeout(timer);timer=setTimeout(resync,90)}
  function poll(){const k=metric();if(visible()&&k&&k!==lastKey){lastKey=k;queue()}}
  function init(){
    lastKey=metric();
    addEventListener('resize',queue,{passive:true});
    window.visualViewport?.addEventListener('resize',queue,{passive:true});
    const c=document.getElementById('canvas-container');if(c)new ResizeObserver(queue).observe(c);
    const main=document.getElementById('preview-main');if(main)new ResizeObserver(queue).observe(main);
    document.addEventListener('presentation-canvas-fitted',queue);
    setInterval(poll,250);
    setTimeout(queue,250);setTimeout(queue,900);
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();