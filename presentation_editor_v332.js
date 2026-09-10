(()=>{
  function pageNo(){return Number((typeof currentPreviewPage!=='undefined'&&currentPreviewPage)||1)}
  function cfg(p=pageNo()){
    if(typeof getInfoBarPageConfig!=='function')return null;
    const c=getInfoBarPageConfig(p);if(c.northUseGlobal===undefined)c.northUseGlobal=true;if(c.northAngle===undefined)c.northAngle=0;return c;
  }
  window.getInfoBarNorthAngle=function(p){const c=cfg(p);if(!c||c.northUseGlobal!==false)return Number(document.getElementById('northAngle')?.value)||0;return Number(c.northAngle)||0};

  function css(){if(document.getElementById('presentation-editor-v332-style'))return;const s=document.createElement('style');s.id='presentation-editor-v332-style';s.textContent=`
    #preview-modal{padding:0!important;overflow:hidden!important}
    #preview-content{width:100vw!important;height:100vh!important;border-radius:0!important;max-width:none!important;max-height:none!important;overflow:hidden!important}
    #preview-header{padding:8px 14px!important;min-height:40px!important;flex:0 0 auto!important}
    #preview-footer{padding:7px 14px!important;min-height:42px!important;flex:0 0 auto!important}
    #preview-body{padding:8px!important;gap:8px!important;overflow:hidden!important;align-items:stretch!important;min-height:0!important;flex:1 1 auto!important}
    #thumbs-sidebar{width:122px!important;max-height:none!important;height:100%!important;position:relative!important;overflow-y:auto!important;overflow-x:hidden!important;min-height:0!important}
    #preview-main{display:grid!important;grid-template-rows:auto auto minmax(0,1fr)!important;gap:6px!important;min-height:0!important;min-width:0!important;overflow:hidden!important;align-items:start!important;justify-items:stretch!important}
    #preview-main .preview-tools{display:flex!important;flex-wrap:wrap!important;gap:5px!important;width:100%!important;padding:0!important;margin:0!important;align-items:center!important}
    #preview-main .preview-tools .action,#preview-main .preview-tools .back-btn{padding:5px 8px!important;font-size:10px!important;min-height:28px!important}
    #info-bar-page-tools{width:100%!important;gap:6px!important;flex-wrap:wrap!important;padding:5px 7px!important;margin:0!important;max-height:96px!important;overflow:auto!important;align-items:center!important}
    #info-bar-page-tools label,#info-bar-page-tools b{font-size:10px!important}
    #info-bar-page-tools input,#info-bar-page-tools select{min-height:26px!important;padding:3px 5px!important;font-size:10px!important}
    #style-variant-row{gap:8px!important;overflow-x:auto!important;overflow-y:hidden!important;padding-top:1px!important}
    #style-variant-row .style-choice{height:34px!important;width:52px!important;padding:2px!important}
    #canvas-container{position:relative!important;align-self:center!important;justify-self:center!important;min-height:0!important;overflow:visible!important;max-width:none!important;max-height:none!important}
    #preview-canvas{display:block!important;max-width:none!important;max-height:none!important;object-fit:contain!important}
    .page-north-local{display:inline-flex;align-items:center;gap:7px;padding:3px 6px;border:1px solid var(--border);border-radius:7px;background:#fff;flex-shrink:0}
    .page-north-local label{display:inline-flex;align-items:center;gap:4px;font-size:10px;white-space:nowrap}
    .page-north-dial{width:42px;height:42px;border:1px solid #18181b;border-radius:50%;position:relative;cursor:crosshair;flex:0 0 42px;background:#fafafa}
    .page-north-dial:after{content:'';position:absolute;left:50%;top:50%;width:4px;height:4px;border-radius:50%;background:#18181b;transform:translate(-50%,-50%)}
    .page-north-point{position:absolute;width:8px;height:8px;border-radius:50%;background:#18181b;transform:translate(-50%,-50%);pointer-events:none}
    .page-north-local.global .page-north-dial{opacity:.35;pointer-events:none}
    @media(max-width:900px){#thumbs-sidebar{width:100px!important}.page-north-local{padding:3px 5px}}
  `;document.head.appendChild(s)}

  let fitRaf=0;
  function fitCanvas(){
    cancelAnimationFrame(fitRaf);fitRaf=requestAnimationFrame(()=>{
      const main=document.getElementById('preview-main'),canvas=document.getElementById('preview-canvas'),container=document.getElementById('canvas-container');
      if(!main||!canvas||!container||!canvas.width||!canvas.height)return;
      const mr=main.getBoundingClientRect();
      const tools=main.querySelector('.preview-tools');
      const info=document.getElementById('info-bar-page-tools');
      let contentTop=mr.top;
      if(tools){const r=tools.getBoundingClientRect();if(r.height>0)contentTop=Math.max(contentTop,r.bottom)}
      if(info){const r=info.getBoundingClientRect();if(r.height>0)contentTop=Math.max(contentTop,r.bottom)}
      contentTop+=8;
      const availH=Math.max(180,mr.bottom-contentTop-6);
      const availW=Math.max(320,mr.width-16);
      const sourceW=Number(canvas.width)||1,sourceH=Number(canvas.height)||1;
      const scale=Math.min(availW/sourceW,availH/sourceH);
      const cssW=Math.max(1,Math.floor(sourceW*scale));
      const cssH=Math.max(1,Math.floor(sourceH*scale));
      const oldW=parseFloat(canvas.style.width)||0,oldH=parseFloat(canvas.style.height)||0;
      canvas.style.width=cssW+'px';canvas.style.height=cssH+'px';
      container.style.width=cssW+'px';container.style.height=cssH+'px';
      container.style.maxWidth=cssW+'px';container.style.maxHeight=cssH+'px';
      if(Math.abs(oldW-cssW)>1||Math.abs(oldH-cssH)>1){document.dispatchEvent(new CustomEvent('presentation-canvas-fitted',{detail:{width:cssW,height:cssH}}))}
    });
  }
  window.fitPresentationCanvas=fitCanvas;

  function ui(){const host=document.getElementById('style-variant-row')||document.getElementById('info-bar-page-tools');if(!host||document.getElementById('page-north-local'))return;const d=document.createElement('div');d.id='page-north-local';d.className='page-north-local';d.innerHTML=`<label><input id="pageNorthGlobal" type="checkbox" checked> Globální</label><div id="pageNorthDial" class="page-north-dial" title="Lokální natočení severky"><span id="pageNorthPoint" class="page-north-point"></span></div><span id="pageNorthValue" style="font-size:10px;min-width:34px">0°</span>`;host.appendChild(d);
    const cb=d.querySelector('#pageNorthGlobal'),dial=d.querySelector('#pageNorthDial');cb.onchange=()=>{const c=cfg();if(!c)return;c.northUseGlobal=cb.checked;sync();refresh();save()};let drag=false;const set=e=>{const c=cfg();if(!c||c.northUseGlobal!==false)return;const r=dial.getBoundingClientRect(),cx=r.left+r.width/2,cy=r.top+r.height/2;let a=Math.atan2(e.clientX-cx,-(e.clientY-cy))*180/Math.PI;if(a<0)a+=360;c.northAngle=Number(a.toFixed(1));sync();refresh();save()};dial.onpointerdown=e=>{drag=true;dial.setPointerCapture(e.pointerId);set(e)};dial.onpointermove=e=>{if(drag)set(e)};dial.onpointerup=()=>drag=false;dial.onpointercancel=()=>drag=false;sync()}
  function sync(){const c=cfg(),box=document.getElementById('page-north-local'),cb=document.getElementById('pageNorthGlobal'),pt=document.getElementById('pageNorthPoint'),dial=document.getElementById('pageNorthDial'),val=document.getElementById('pageNorthValue');if(!c||!box||!cb||!pt||!dial)return;cb.checked=c.northUseGlobal!==false;box.classList.toggle('global',cb.checked);const a=cb.checked?(Number(document.getElementById('northAngle')?.value)||0):(Number(c.northAngle)||0),rad=a*Math.PI/180,r=dial.clientWidth/2-5;pt.style.left=(dial.clientWidth/2+Math.sin(rad)*r)+'px';pt.style.top=(dial.clientHeight/2-Math.cos(rad)*r)+'px';if(val)val.textContent=Math.round(a)+'°';setTimeout(fitCanvas,0)}
  function refresh(){try{renderCurrentPagePreview?.();renderThumbnails?.();setTimeout(fitCanvas,0);setTimeout(fitCanvas,80)}catch(e){console.warn(e)}}
  function save(){try{scheduleAutosave?.();persistProjectStructureNow?.()}catch(e){}}
  function wrapLoad(){if(typeof loadCurrentInfoBarControls!=='function'||loadCurrentInfoBarControls.__v332)return;const o=loadCurrentInfoBarControls;window.loadCurrentInfoBarControls=function(){const r=o.apply(this,arguments);setTimeout(sync,0);setTimeout(fitCanvas,0);setTimeout(fitCanvas,80);return r};window.loadCurrentInfoBarControls.__v332=true}
  function wrapRender(){if(typeof renderCurrentPagePreview!=='function'||renderCurrentPagePreview.__fitV332)return;const o=renderCurrentPagePreview;window.renderCurrentPagePreview=async function(){const r=await o.apply(this,arguments);fitCanvas();setTimeout(fitCanvas,40);return r};window.renderCurrentPagePreview.__fitV332=true}
  function init(){css();ui();wrapLoad();wrapRender();sync();fitCanvas();addEventListener('resize',()=>{sync();fitCanvas()});if(window.visualViewport)visualViewport.addEventListener('resize',fitCanvas);const target=document.getElementById('preview-main');if(target)new ResizeObserver(fitCanvas).observe(target);setTimeout(()=>{ui();wrapLoad();wrapRender();sync();fitCanvas()},400);setTimeout(()=>{ui();wrapLoad();wrapRender();sync();fitCanvas()},1400)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();
