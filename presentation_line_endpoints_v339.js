(()=>{
  function pageNo(){return Number((typeof currentPreviewPage!=='undefined'&&currentPreviewPage)||1)}
  function items(){const d=(typeof allPagesTexts!=='undefined'&&allPagesTexts[pageNo()])||[];return Array.isArray(d)?d:[]}
  function getLine(el){return items().find(x=>x.type==='line'&&String(x.id)===String(el.dataset.id))}
  function persistLine(b){
    try{
      const list=items(),stored=list.find(x=>x.type==='line'&&String(x.id)===String(b.id));
      if(stored&&stored!==b)Object.assign(stored,b);
      if(typeof saveCurrentPageBoxes==='function')saveCurrentPageBoxes();
      if(typeof scheduleAutosave==='function')scheduleAutosave();
      if(typeof persistProjectStructureNow==='function')Promise.resolve(persistProjectStructureNow()).catch(e=>console.warn('Uložení délky čáry selhalo',e));
    }catch(e){console.warn('Uložení délky čáry selhalo',e)}
  }
  function css(){if(document.getElementById('presentation-line-endpoints-v339-style'))return;const s=document.createElement('style');s.id='presentation-line-endpoints-v339-style';s.textContent=`
    .line-end-handle-v339{position:absolute;width:12px;height:12px;border:2px solid #2563eb;background:#fff;border-radius:50%;z-index:45;display:none;box-sizing:border-box;touch-action:none}
    .custom-text-box.selected .line-end-handle-v339{display:block}
    .line-end-handle-v339.top{left:5px;top:0;transform:translate(-50%,-50%);cursor:ns-resize}
    .line-end-handle-v339.left{left:0;top:5px;transform:translate(-50%,-50%);cursor:ew-resize}
  `;document.head.appendChild(s)}
  function decorate(){
    const canvas=document.getElementById('preview-canvas'),info=window.__previewInfo;if(!canvas||!info)return;
    const cr=canvas.getBoundingClientRect(),sx=cr.width/info.width,sy=cr.height/info.height;
    document.querySelectorAll('#boxes-layer .custom-text-box').forEach(el=>{
      const b=getLine(el);if(!b||el.querySelector('.line-end-handle-v339'))return;
      const h=document.createElement('span');h.className='line-end-handle-v339 '+(b.orientation==='horizontal'?'left':'top');h.title=b.orientation==='horizontal'?'Táhni levý konec čáry':'Táhni horní konec čáry';el.appendChild(h);
      h.onpointerdown=e=>{
        e.preventDefault();e.stopPropagation();try{pushTextHistory?.()}catch(_){ }
        h.setPointerCapture(e.pointerId);
        const startHeight=Number(b.height)||100,startY=Number(b.y)||0,startX=Number(b.x)||0;
        const startClientX=e.clientX,startClientY=e.clientY;
        h.onpointermove=ev=>{
          if(b.orientation==='horizontal'){
            const dx=(ev.clientX-startClientX)/sx;
            const newLen=Math.max(10,startHeight-dx);
            const right=startX+startHeight;b.x=right-newLen;b.height=newLen;
            el.style.left=(b.x*sx)+'px';el.style.width=(b.height*sy)+'px';
          }else{
            const dy=(ev.clientY-startClientY)/sy;
            const newLen=Math.max(10,startHeight-dy);
            b.height=newLen;
            el.style.height=(b.height*sy)+'px';
            el.style.top=((info.height-startY-b.height)*sy)+'px';
          }
          const inp=el.querySelector('.tb-controls input');if(inp)inp.value=String(Math.round(b.height));
          if(typeof scheduleAutosave==='function')scheduleAutosave();
        };
        const end=()=>{
          h.onpointermove=null;h.onpointerup=null;h.onpointercancel=null;
          const inp=el.querySelector('.tb-controls input');if(inp)inp.value=String(Math.round(b.height));
          persistLine(b);
        };
        h.onpointerup=end;h.onpointercancel=end;
      };
    })
  }
  function init(){css();decorate();const layer=document.getElementById('boxes-layer');if(layer)new MutationObserver(decorate).observe(layer,{childList:true,subtree:true});document.addEventListener('presentation-canvas-fitted',decorate);document.addEventListener('presentation-zoom-resynced',decorate);setInterval(decorate,700)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();