(()=>{
  function pageNo(){return Number((typeof currentPreviewPage!=='undefined'&&currentPreviewPage)||1)}
  function currentItems(){const d=(typeof allPagesTexts!=='undefined'&&allPagesTexts[pageNo()])||[];return Array.isArray(d)?d:[]}
  function isCover(){return !!window.__previewInfo?.isCover}
  function syncCoverText(){
    if(!isCover())return;
    const canvas=document.getElementById('preview-canvas'),info=window.__previewInfo;if(!canvas||!info)return;
    const r=canvas.getBoundingClientRect(),sx=r.width/info.width,sy=r.height/info.height;
    const map=new Map(currentItems().map(x=>[String(x.id),x]));
    document.querySelectorAll('#boxes-layer .custom-text-box').forEach(el=>{
      const b=map.get(String(el.dataset.id));if(!b||b.type==='line')return;
      const ta=el.querySelector('.tb-main');if(!ta)return;
      const lines=(b.text||'').split(/\r?\n/).length;
      const visualH=b.size+Math.max(0,lines-1)*b.size*1.2;
      // Canvas export uses textBaseline='bottom'. CSS line-height 1.2 adds half-leading above/below,
      // therefore move the DOM editor up by 0.1 em so the visible glyph baseline matches export.
      const top=(info.height-b.y-visualH-b.size*0.10)*sy;
      el.style.left=(b.x*sx)+'px';el.style.top=top+'px';
      el.style.fontSize=(b.size*sx)+'px';ta.style.fontSize=(b.size*sx)+'px';ta.style.lineHeight='1.2';
    });
  }
  function queue(){requestAnimationFrame(()=>requestAnimationFrame(syncCoverText))}
  function init(){
    const layer=document.getElementById('boxes-layer');if(layer)new MutationObserver(queue).observe(layer,{childList:true,subtree:true});
    document.addEventListener('presentation-canvas-fitted',queue);document.addEventListener('presentation-zoom-resynced',queue);addEventListener('resize',queue,{passive:true});
    setInterval(()=>{if(isCover())syncCoverText()},500);queue();
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();