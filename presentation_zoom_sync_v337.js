(()=>{
  let busy=false,timer=0,lastKey='';
  function visible(){const m=document.getElementById('preview-modal');return !!m&&getComputedStyle(m).display!=='none'}
  function metric(){const c=document.getElementById('preview-canvas');if(!c)return'';const r=c.getBoundingClientRect();return [window.devicePixelRatio||1,window.visualViewport?.scale||1,window.innerWidth,window.innerHeight,Math.round(r.width*10)/10,Math.round(r.height*10)/10].join('|')}
  async function resync(){
    if(busy||!visible())return;busy=true;
    try{
      window.fitPresentationCanvas?.();
      await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
      if(typeof window.renderCurrentPagePreview==='function')await window.renderCurrentPagePreview();
      window.fitPresentationCanvas?.();
      await new Promise(r=>requestAnimationFrame(r));
      document.dispatchEvent(new CustomEvent('presentation-zoom-resynced'));
    }catch(e){console.warn('Presentation zoom resync',e)}finally{busy=false;lastKey=metric()}
  }
  function queue(){clearTimeout(timer);timer=setTimeout(resync,120)}
  function poll(){const k=metric();if(visible()&&k&&k!==lastKey){lastKey=k;queue()}}
  function init(){
    lastKey=metric();
    addEventListener('resize',queue,{passive:true});
    window.visualViewport?.addEventListener('resize',queue,{passive:true});
    window.visualViewport?.addEventListener('scroll',queue,{passive:true});
    const c=document.getElementById('canvas-container');if(c)new ResizeObserver(queue).observe(c);
    const main=document.getElementById('preview-main');if(main)new ResizeObserver(queue).observe(main);
    setInterval(poll,350);
    setTimeout(queue,300);setTimeout(queue,1200);
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();