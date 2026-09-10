(()=>{
  function pageNo(){return Number((typeof currentPreviewPage!=='undefined'&&currentPreviewPage)||1)}
  function cfg(p=pageNo()){
    if(typeof getInfoBarPageConfig!=='function')return null;
    const c=getInfoBarPageConfig(p);if(c.northUseGlobal===undefined)c.northUseGlobal=true;if(c.northAngle===undefined)c.northAngle=0;return c;
  }
  window.getInfoBarNorthAngle=function(p){const c=cfg(p);if(!c||c.northUseGlobal!==false)return Number(document.getElementById('northAngle')?.value)||0;return Number(c.northAngle)||0};

  function css(){if(document.getElementById('presentation-editor-v332-style'))return;const s=document.createElement('style');s.id='presentation-editor-v332-style';s.textContent=`
    #preview-modal{padding:0!important}
    #preview-content{width:100vw!important;height:100vh!important;border-radius:0!important;max-width:none!important;max-height:none!important}
    #preview-header{padding:9px 14px!important;min-height:42px}
    #preview-footer{padding:8px 14px!important;min-height:46px}
    #preview-body{padding:10px!important;gap:10px!important;overflow:hidden!important;align-items:stretch!important}
    #thumbs-sidebar{width:126px!important;max-height:none!important;height:100%!important;position:relative!important;overflow-y:auto!important}
    #preview-main{gap:8px!important;min-height:0!important;overflow:hidden!important;justify-content:flex-start!important}
    #preview-main .preview-tools{flex-wrap:wrap!important;gap:6px!important;width:100%!important;padding:0!important}
    #preview-main .preview-tools .action,#preview-main .preview-tools .back-btn{padding:6px 9px!important;font-size:11px!important}
    #info-bar-page-tools{width:100%!important;gap:7px!important;flex-wrap:wrap!important;padding:7px 9px!important}
    #style-variant-row{gap:10px!important;overflow-x:auto!important}
    #canvas-container{max-width:100%!important;max-height:calc(100vh - 225px)!important}
    #preview-canvas{display:block!important;max-width:calc(100vw - 175px)!important;max-height:calc(100vh - 225px)!important;width:auto!important;height:auto!important}
    .page-north-local{display:inline-flex;align-items:center;gap:8px;padding:4px 7px;border:1px solid var(--border);border-radius:7px;background:#fff;flex-shrink:0}
    .page-north-local label{display:inline-flex;align-items:center;gap:5px;font-size:11px;white-space:nowrap}
    .page-north-dial{width:48px;height:48px;border:1px solid #18181b;border-radius:50%;position:relative;cursor:crosshair;flex:0 0 48px;background:#fafafa}
    .page-north-dial:after{content:'';position:absolute;left:50%;top:50%;width:4px;height:4px;border-radius:50%;background:#18181b;transform:translate(-50%,-50%)}
    .page-north-point{position:absolute;width:9px;height:9px;border-radius:50%;background:#18181b;transform:translate(-50%,-50%);pointer-events:none}
    .page-north-local.global .page-north-dial{opacity:.35;pointer-events:none}
    @media(max-width:900px){#thumbs-sidebar{width:104px!important}#preview-canvas{max-width:calc(100vw - 145px)!important}.page-north-local{padding:3px 5px}}
  `;document.head.appendChild(s)}

  function ui(){const host=document.getElementById('style-variant-row')||document.getElementById('info-bar-page-tools');if(!host||document.getElementById('page-north-local'))return;const d=document.createElement('div');d.id='page-north-local';d.className='page-north-local';d.innerHTML=`<label><input id="pageNorthGlobal" type="checkbox" checked> Globální</label><div id="pageNorthDial" class="page-north-dial" title="Lokální natočení severky"><span id="pageNorthPoint" class="page-north-point"></span></div><span id="pageNorthValue" style="font-size:10px;min-width:34px">0°</span>`;host.appendChild(d);
    const cb=d.querySelector('#pageNorthGlobal'),dial=d.querySelector('#pageNorthDial');cb.onchange=()=>{const c=cfg();if(!c)return;c.northUseGlobal=cb.checked;sync();refresh();save()};let drag=false;const set=e=>{const c=cfg();if(!c||c.northUseGlobal!==false)return;const r=dial.getBoundingClientRect(),cx=r.left+r.width/2,cy=r.top+r.height/2;let a=Math.atan2(e.clientX-cx,-(e.clientY-cy))*180/Math.PI;if(a<0)a+=360;c.northAngle=Number(a.toFixed(1));sync();refresh();save()};dial.onpointerdown=e=>{drag=true;dial.setPointerCapture(e.pointerId);set(e)};dial.onpointermove=e=>{if(drag)set(e)};dial.onpointerup=()=>drag=false;dial.onpointercancel=()=>drag=false;sync()}
  function sync(){const c=cfg(),box=document.getElementById('page-north-local'),cb=document.getElementById('pageNorthGlobal'),pt=document.getElementById('pageNorthPoint'),dial=document.getElementById('pageNorthDial'),val=document.getElementById('pageNorthValue');if(!c||!box||!cb||!pt||!dial)return;cb.checked=c.northUseGlobal!==false;box.classList.toggle('global',cb.checked);const a=cb.checked?(Number(document.getElementById('northAngle')?.value)||0):(Number(c.northAngle)||0),rad=a*Math.PI/180,r=dial.clientWidth/2-5;pt.style.left=(dial.clientWidth/2+Math.sin(rad)*r)+'px';pt.style.top=(dial.clientHeight/2-Math.cos(rad)*r)+'px';if(val)val.textContent=Math.round(a)+'°'}
  function refresh(){try{renderCurrentPagePreview?.();renderThumbnails?.()}catch(e){console.warn(e)}}
  function save(){try{scheduleAutosave?.();persistProjectStructureNow?.()}catch(e){}}
  function wrapLoad(){if(typeof loadCurrentInfoBarControls!=='function'||loadCurrentInfoBarControls.__v332)return;const o=loadCurrentInfoBarControls;window.loadCurrentInfoBarControls=function(){const r=o.apply(this,arguments);setTimeout(sync,0);return r};window.loadCurrentInfoBarControls.__v332=true}
  function init(){css();ui();wrapLoad();sync();addEventListener('resize',sync);setTimeout(()=>{ui();wrapLoad();sync()},500);setTimeout(()=>{ui();wrapLoad();sync()},1600)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();
