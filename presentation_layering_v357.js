(()=>{
  const STYLE_ID='presentation-layering-v357-style';
  const OVERLAY_ID='presentation-info-overlay-v357';
  let renderWrapped=false, runWrapped=false, fontBytesPromise=null;

  function css(){
    if(document.getElementById(STYLE_ID))return;
    const s=document.createElement('style');s.id=STYLE_ID;s.textContent=`
      #canvas-container{isolation:isolate!important}
      .moodboard-cell{z-index:25!important}
      .presentation-media-item{z-index:34!important}
      #${OVERLAY_ID}{position:absolute;z-index:90;pointer-events:none;display:block}
      #boxes-layer{z-index:120!important}
      #boxes-layer .custom-text-box{z-index:121!important}
    `;document.head.appendChild(s);
  }

  function pageNo(){return Number((typeof currentPreviewPage!=='undefined'&&currentPreviewPage)||1)}
  function currentInfo(){try{return typeof getPreviewPageInfo==='function'?getPreviewPageInfo():null}catch(_){return null}}
  function hasInfoBar(p=pageNo()){
    const info=currentInfo();
    if(info?.isCover)return false;
    try{if(typeof customBlankPages!=='undefined'&&customBlankPages.has(p)&&typeof blankPageInfoBars!=='undefined'&&blankPageInfoBars[p]===false)return false}catch(_){ }
    return true;
  }
  function reservedBarPt(){return document.getElementById('infoBarVariant')?.value==='architect'?(12/25.4)*72:(14.17+28.35)}

  function syncEditorOverlay(){
    css();
    const canvas=document.getElementById('preview-canvas'),container=document.getElementById('canvas-container');
    if(!canvas||!container)return;
    let ov=document.getElementById(OVERLAY_ID);
    if(!hasInfoBar()){
      ov?.remove();return;
    }
    if(!ov){ov=document.createElement('canvas');ov.id=OVERLAY_ID;container.appendChild(ov)}
    const info=window.__previewInfo;if(!info?.height||!canvas.width||!canvas.height)return;
    const cr=canvas.getBoundingClientRect(),pr=container.getBoundingClientRect();
    const barPt=Math.min(info.height,reservedBarPt());
    const srcH=Math.max(1,Math.round(canvas.height*(barPt/info.height)));
    ov.width=canvas.width;ov.height=srcH;
    ov.style.left=(cr.left-pr.left)+'px';
    ov.style.top=(cr.top-pr.top+cr.height-(cr.height*barPt/info.height))+'px';
    ov.style.width=cr.width+'px';
    ov.style.height=(cr.height*barPt/info.height)+'px';
    const ctx=ov.getContext('2d');ctx.clearRect(0,0,ov.width,ov.height);
    ctx.drawImage(canvas,0,canvas.height-srcH,canvas.width,srcH,0,0,ov.width,ov.height);
  }

  function wrapRender(){
    if(renderWrapped||typeof window.renderCurrentPagePreview!=='function')return;
    const orig=window.renderCurrentPagePreview;
    window.renderCurrentPagePreview=async function(){
      const r=await orig.apply(this,arguments);
      requestAnimationFrame(()=>requestAnimationFrame(syncEditorOverlay));
      return r;
    };
    renderWrapped=true;
  }

  function fontBytes(){
    if(!fontBytesPromise)fontBytesPromise=fetch('font/Dunwich%20Type%20Founders%20-%20Antarctican%20Mono%20Book.otf').then(r=>{if(!r.ok)throw new Error('Antarctican Mono se nepodařilo načíst');return r.arrayBuffer()});
    return fontBytesPromise;
  }

  function textSize(tb){return Math.max(6,Math.min(144,Number(tb?.size)||16))}
  async function redrawTexts(pdf,font){
    if(typeof allPagesTexts==='undefined')return;
    const pages=pdf.getPages?.()||[];
    const black=PDFLib.rgb(24/255,24/255,27/255);
    for(let p=1;p<=pages.length;p++){
      const items=allPagesTexts[p];if(!Array.isArray(items))continue;
      const pg=pages[p-1];
      for(const tb of items){
        if(tb?.type==='line'){
          const len=Number(tb.height)||0, x=Number(tb.x)||0, y=Number(tb.y)||0;
          if((tb.orientation||'vertical')==='horizontal')pg.drawLine({start:{x,y:y+len/2},end:{x:x+len,y:y+len/2},thickness:1,color:black});
          else pg.drawLine({start:{x:x+len/2,y},end:{x:x+len/2,y:y+len},thickness:1,color:black});
          continue;
        }
        if(!tb?.text)continue;
        const size=textSize(tb),lines=String(tb.text).split(/\r?\n/),lh=size*1.2;
        lines.forEach((line,idx)=>{const yy=(Number(tb.y)||0)+(lines.length-1-idx)*lh;pg.drawText(line,{x:Number(tb.x)||0,y:yy,size,font,color:black})});
      }
    }
  }

  function pageHasBar(p){
    try{
      const coverOn=document.getElementById('createCover')?.checked;
      if(coverOn&&p===1)return false;
      if(typeof customBlankPages!=='undefined'&&customBlankPages.has(p)&&typeof blankPageInfoBars!=='undefined'&&blankPageInfoBars[p]===false)return false;
    }catch(_){ }
    return true;
  }

  async function redrawBars(pdf){
    if(typeof drawInfoBar!=='function')return;
    const pages=pdf.getPages?.()||[];
    for(let p=1;p<=pages.length;p++){
      if(!pageHasBar(p))continue;
      const pg=pages[p-1],sz=pg.getSize(),barPt=Math.min(sz.height,reservedBarPt());
      const scale=3;
      const c=document.createElement('canvas');c.width=Math.max(1,Math.round(sz.width*scale));c.height=Math.max(1,Math.round(sz.height*scale));
      const ctx=c.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,c.width,c.height);
      try{await drawInfoBar(ctx,sz.width,sz.height,scale,p)}catch(e){console.warn('Překreslení spodního pruhu',e);continue}
      const cropH=Math.max(1,Math.round(barPt*scale)),crop=document.createElement('canvas');crop.width=c.width;crop.height=cropH;
      crop.getContext('2d').drawImage(c,0,c.height-cropH,c.width,cropH,0,0,crop.width,crop.height);
      const bytes=await fetch(crop.toDataURL('image/png')).then(r=>r.arrayBuffer()),img=await pdf.embedPng(bytes);
      pg.drawImage(img,{x:0,y:0,width:sz.width,height:barPt});
    }
  }

  async function redrawTop(pdf){
    if(pdf.__presentationTopLayerV357)return;pdf.__presentationTopLayerV357=true;
    try{await redrawBars(pdf)}catch(e){console.warn('Spodní pruh nad médiem',e)}
    try{
      if(window.fontkit&&pdf.registerFontkit){pdf.registerFontkit(window.fontkit);const font=await pdf.embedFont(await fontBytes());await redrawTexts(pdf,font)}
    }catch(e){console.warn('Text nad vloženým médiem',e)}
  }

  function wrapRunPanel(){
    if(runWrapped||typeof window.runPanel!=='function'||!window.PDFLib?.PDFDocument)return;
    if(window.presentationMediaState&&!window.presentationMediaState.runWrapped)return;
    const orig=window.runPanel;
    window.runPanel=async function(){
      const proto=PDFLib.PDFDocument.prototype,previous=proto.save;
      proto.save=async function(){
        if(this.__pmDecorated)await redrawTop(this);
        return previous.apply(this,arguments);
      };
      try{return await orig.apply(this,arguments)}finally{proto.save=previous}
    };
    runWrapped=true;
  }

  function init(){
    css();wrapRender();wrapRunPanel();syncEditorOverlay();
    setTimeout(()=>{wrapRender();wrapRunPanel();syncEditorOverlay()},400);
    setTimeout(()=>{wrapRender();wrapRunPanel();syncEditorOverlay()},1400);
    window.addEventListener('resize',syncEditorOverlay,{passive:true});
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();