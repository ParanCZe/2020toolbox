(()=>{
  const CORE=()=>window.presentationGeometryV358;
  const MM5_PT=5*(72/25.4);
  let mediaPersistTimer=null;

  function pageNo(){return Number((typeof currentPreviewPage!=='undefined'&&currentPreviewPage)||1)}
  function mediaItems(){return window.presentationMediaState?.byPage?.[pageNo()]||[]}
  function mediaObject(el){return mediaItems().find(o=>String(o.id)===String(el.dataset.id))}
  function canvasGeom(){
    const c=document.getElementById('preview-canvas');if(!c)return null;
    const par=c.parentElement,cr=c.getBoundingClientRect(),pr=par.getBoundingClientRect();
    return {c,par,cr,pr,left:cr.left-pr.left,top:cr.top-pr.top,w:cr.width,h:cr.height};
  }
  function schedulePersist(){
    clearTimeout(mediaPersistTimer);mediaPersistTimer=setTimeout(()=>{try{window.persistProjectStructureNow?.()}catch(e){console.warn(e)}},180);
  }

  function css(){
    if(document.getElementById('presentation-editor-geometry-v358-style'))return;
    const s=document.createElement('style');s.id='presentation-editor-geometry-v358-style';s.textContent=`
      #presentation-print-guide-v358{position:absolute;pointer-events:none;z-index:155;border:1px dashed rgba(24,24,27,.62);box-sizing:border-box;background:transparent}
      .presentation-text-scale-v358{position:absolute;right:-8px;bottom:-8px;width:15px;height:15px;border:2px solid #18181b;background:#fff;border-radius:50%;cursor:nwse-resize;z-index:260;box-shadow:0 1px 3px rgba(0,0,0,.18);touch-action:none;user-select:none}
      .custom-text-box{z-index:220!important}
    `;document.head.appendChild(s);
  }

  function ensureGuide(){
    const g=canvasGeom(),info=window.__previewInfo;if(!g||!info)return;
    let d=document.getElementById('presentation-print-guide-v358');
    if(!d){d=document.createElement('div');d.id='presentation-print-guide-v358';d.setAttribute('aria-hidden','true');g.par.appendChild(d)}
    if(d.parentElement!==g.par)g.par.appendChild(d);
    const core=CORE();
    const insetX=core?core.guideInsetPx({pageWidthPt:info.width,renderedWidthPx:g.w,insetMm:5}):MM5_PT*(g.w/info.width);
    const insetY=MM5_PT*(g.h/info.height);
    d.style.left=(g.left+insetX)+'px';d.style.top=(g.top+insetY)+'px';
    d.style.width=Math.max(0,g.w-2*insetX)+'px';d.style.height=Math.max(0,g.h-2*insetY)+'px';
  }

  function repairMediaAspect(el){
    const g=canvasGeom(),o=mediaObject(el),img=el.querySelector('img');if(!g||!o||!img)return;
    const apply=()=>{
      if(!img.naturalWidth||!img.naturalHeight)return;
      const aspect=img.naturalWidth/img.naturalHeight;
      if(!Number.isFinite(aspect)||aspect<=0)return;
      const core=CORE();
      const next=core?core.resizeMediaFromWidth({widthNorm:o.w,aspect,canvasW:g.w,canvasH:g.h}):{widthNorm:o.w,heightNorm:((o.w*g.w)/aspect)/g.h};
      const changed=Math.abs((Number(o.aspect)||0)-aspect)>.0001||Math.abs((Number(o.h)||0)-next.heightNorm)>.001;
      o.aspect=aspect;o.h=next.heightNorm;
      el.style.width=(o.w*g.w)+'px';el.style.height=(o.h*g.h)+'px';
      el.dataset.aspectLockedV358='1';
      if(changed)schedulePersist();
    };
    if(img.complete)apply();else img.addEventListener('load',apply,{once:true});
  }

  function textBacking(el){
    if(typeof allPagesTexts==='undefined')return null;
    const page=allPagesTexts[pageNo()];if(!Array.isArray(page))return null;
    return page.find(b=>String(b.id)===String(el.dataset.id)&&b.type!=='line')||null;
  }
  function decorateText(el){
    const b=textBacking(el);if(!b||el.querySelector('.presentation-text-scale-v358'))return;
    const h=document.createElement('span');h.className='presentation-text-scale-v358';h.title='Změnit velikost textu';el.appendChild(h);

    const stopMouse=e=>{e.preventDefault();e.stopPropagation();e.stopImmediatePropagation?.()};
    ['mousedown','mouseup','click','dblclick','touchstart','touchmove','touchend'].forEach(type=>h.addEventListener(type,stopMouse,{capture:true,passive:false}));

    h.addEventListener('pointerdown',e=>{
      e.preventDefault();e.stopPropagation();
      const info=window.__previewInfo,canvas=document.getElementById('preview-canvas');if(!info||!canvas)return;
      const rect=el.getBoundingClientRect(),cr=canvas.getBoundingClientRect(),sx=cr.width/info.width,sy=cr.height/info.height;
      const startDist=Math.max(12,Math.hypot(e.clientX-rect.left,e.clientY-rect.top));
      const startSize=Math.max(6,Number(b.size)||16);
      const startVisualHeight=typeof getTextVisualHeightPts==='function'?getTextVisualHeightPts(b.text,startSize):startSize;
      const fixedTopPt=info.height-(Number(b.y)||0)-startVisualHeight;

      try{if(typeof pushTextHistory==='function')pushTextHistory()}catch(err){console.warn('Historie změny velikosti textu',err)}

      h.setPointerCapture(e.pointerId);
      const move=ev=>{
        ev.preventDefault();ev.stopPropagation();
        const dist=Math.max(4,Math.hypot(ev.clientX-rect.left,ev.clientY-rect.top));
        const core=CORE(),size=core?core.scaledFontSize(startSize,dist/startDist):Math.max(6,Math.min(144,startSize*(dist/startDist)));
        const visualHeight=typeof getTextVisualHeightPts==='function'?getTextVisualHeightPts(b.text,size):size;
        b.size=size;
        b.y=core?.resizeTextKeepingTop?core.resizeTextKeepingTop({pageHeight:info.height,top:fixedTopPt,newVisualHeight:visualHeight}).y:info.height-fixedTopPt-visualHeight;
        el.style.fontSize=(size*sx)+'px';
        el.style.top=(fixedTopPt*sy)+'px';
      };
      const end=ev=>{
        ev?.preventDefault?.();ev?.stopPropagation?.();
        h.removeEventListener('pointermove',move);
        h.removeEventListener('pointerup',end);
        h.removeEventListener('pointercancel',end);
        try{scheduleAutosave?.()}catch(_){}
        try{window.persistProjectStructureNow?.()}catch(_){}
        try{updateUndoButton?.()}catch(_){}
      };
      h.addEventListener('pointermove',move);
      h.addEventListener('pointerup',end);
      h.addEventListener('pointercancel',end);
    });
  }

  function sync(){
    ensureGuide();
    document.querySelectorAll('.presentation-media-item').forEach(repairMediaAspect);
    document.querySelectorAll('.custom-text-box').forEach(decorateText);
  }

  function wrapRender(){
    const fn=window.renderCurrentPagePreview;if(typeof fn!=='function'||fn.__geometryV358)return;
    const wrapped=async function(){const r=await fn.apply(this,arguments);requestAnimationFrame(sync);return r};
    wrapped.__geometryV358=true;window.renderCurrentPagePreview=wrapped;
  }

  function init(){
    css();wrapRender();sync();
    const boxes=document.getElementById('boxes-layer');if(boxes)new MutationObserver(()=>requestAnimationFrame(sync)).observe(boxes,{childList:true,subtree:true});
    const container=document.getElementById('canvas-container');if(container)new MutationObserver(()=>requestAnimationFrame(sync)).observe(container,{childList:true,subtree:false});
    const canvas=document.getElementById('preview-canvas');if(canvas&&window.ResizeObserver)new ResizeObserver(()=>sync()).observe(canvas);
    document.addEventListener('presentation-canvas-fitted',sync);
    window.addEventListener('resize',sync);
    setTimeout(()=>{wrapRender();sync()},450);setTimeout(()=>{wrapRender();sync()},1600);
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();
