(()=>{
  const STATE={byPage:{},wrapped:false,runWrapped:false};
  window.presentationMediaState=STATE;

  function css(){
    if(document.getElementById('presentation-media-v331-style'))return;
    const s=document.createElement('style');s.id='presentation-media-v331-style';s.textContent=`
      .presentation-media-item{position:absolute;z-index:34;border:1px solid transparent;box-sizing:border-box;cursor:move;user-select:none}
      .presentation-media-item.selected{border:2px solid #18181b;box-shadow:0 0 0 1px rgba(255,255,255,.8)}
      .presentation-media-item img{width:100%;height:100%;display:block;object-fit:contain;pointer-events:none}
      .presentation-media-item .pm-resize{position:absolute;right:-7px;bottom:-7px;width:14px;height:14px;border:2px solid #18181b;background:#fff;border-radius:50%;cursor:nwse-resize;display:none}
      .presentation-media-item .pm-delete{position:absolute;right:-9px;top:-9px;width:20px;height:20px;border:0;border-radius:50%;background:#dc2626;color:#fff;font:14px/20px system-ui;cursor:pointer;display:none;padding:0}
      .presentation-media-item.selected .pm-resize,.presentation-media-item.selected .pm-delete{display:block}
      #presentation-media-modal{display:none;position:fixed;inset:0;background:rgba(0,0,0,.62);z-index:1700;align-items:center;justify-content:center;padding:20px}
      #presentation-media-modal .box{width:min(900px,96vw);max-height:88vh;overflow:auto;background:#fff;border-radius:12px;padding:20px}
      #presentation-media-modal h3{font:normal 16px 'Antarctican Mono',monospace;margin:0 0 6px}
      #presentation-media-pages{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:12px;margin-top:14px}
      .presentation-media-page{border:1px solid var(--border);border-radius:8px;background:#fafafa;padding:8px;cursor:pointer;text-align:center}
      .presentation-media-page:hover{border-color:#18181b;background:#fffef3}
      .presentation-media-page canvas{display:block;width:100%;height:auto;background:#fff;border:1px solid #e4e4e7;margin-bottom:6px}
      .presentation-media-page span{font-size:11px;color:#52525b}
    `;document.head.appendChild(s);
  }

  function toolbar(){
    const tools=document.querySelector('#preview-main .preview-tools');
    if(!tools||document.getElementById('presentation-media-add-btn'))return;
    const b=document.createElement('button');b.id='presentation-media-add-btn';b.className='action';b.style.background='#f59e0b';b.textContent='+ Vložit PDF / obrázek';b.onclick=pick;
    tools.insertBefore(b,tools.firstChild);
    const inp=document.createElement('input');inp.id='presentation-media-input';inp.type='file';inp.accept='application/pdf,image/png,image/jpeg,image/webp';inp.style.display='none';inp.onchange=onFile;tools.appendChild(inp);
  }

  function modal(){
    if(document.getElementById('presentation-media-modal'))return;
    const m=document.createElement('div');m.id='presentation-media-modal';m.innerHTML=`<div class="box"><div style="display:flex;justify-content:space-between;gap:16px;align-items:center"><div><h3>Vyber stránku PDF</h3><div class="muted" style="margin:0">Klikni na stránku, kterou chceš vložit do aktuální stránky prezentace. Ve finálním exportu zůstane PDF vektorové.</div></div><button class="back-btn" id="presentation-media-close">Zrušit</button></div><div id="presentation-media-pages"></div></div>`;
    document.body.appendChild(m);m.querySelector('#presentation-media-close').onclick=()=>{m.style.display='none';STATE.pendingPdf=null};
  }

  function pick(){document.getElementById('presentation-media-input')?.click()}
  function pageNo(){return Number((typeof currentPreviewPage!=='undefined'&&currentPreviewPage)||1)}
  function arr(p=pageNo()){return STATE.byPage[p]||(STATE.byPage[p]=[])}

  async function onFile(e){
    const f=e.target.files?.[0];e.target.value='';if(!f)return;
    if(f.type==='application/pdf'||/\.pdf$/i.test(f.name)) return handlePdf(f);
    if(!/^image\//.test(f.type))return;
    const data=await fileData(f),im=await imgInfo(data);await addMedia(data,im.w,im.h,f.name,{kind:'image'});
  }
  function fileData(f){return new Promise((res,rej)=>{const r=new FileReader();r.onload=()=>res(r.result);r.onerror=rej;r.readAsDataURL(f)})}
  function imgInfo(src){return new Promise((res,rej)=>{const i=new Image();i.onload=()=>res({w:i.naturalWidth,h:i.naturalHeight});i.onerror=rej;i.src=src})}

  async function handlePdf(file){
    if(!window.pdfjsLib){alert('PDF modul není načtený.');return}
    const sourceData=await fileData(file);
    const bytes=new Uint8Array(await file.arrayBuffer());const pdf=await pdfjsLib.getDocument({data:bytes}).promise;
    if(pdf.numPages===1){const p=await pdf.getPage(1),vp=p.getViewport({scale:1}),data=await renderPdfPage(pdf,1,1800);await addMedia(data,vp.width,vp.height,`${file.name} · strana 1`,{kind:'pdf',sourceData,sourcePage:1});return}
    modal();STATE.pendingPdf={pdf,file,sourceData};const grid=document.getElementById('presentation-media-pages');grid.innerHTML='';document.getElementById('presentation-media-modal').style.display='flex';
    for(let n=1;n<=pdf.numPages;n++){
      const page=await pdf.getPage(n),vp0=page.getViewport({scale:1}),scale=Math.min(1,145/vp0.width),vp=page.getViewport({scale}),c=document.createElement('canvas');c.width=Math.ceil(vp.width);c.height=Math.ceil(vp.height);await page.render({canvasContext:c.getContext('2d'),viewport:vp}).promise;
      const btn=document.createElement('button');btn.className='presentation-media-page';btn.append(c);const sp=document.createElement('span');sp.textContent=`Strana ${n}`;btn.append(sp);btn.onclick=async()=>{document.getElementById('presentation-media-modal').style.display='none';const data=await renderPdfPage(pdf,n,1800);await addMedia(data,vp0.width,vp0.height,`${file.name} · strana ${n}`,{kind:'pdf',sourceData,sourcePage:n});STATE.pendingPdf=null};grid.append(btn);
    }
  }
  async function renderPdfPage(pdf,n,target){const p=await pdf.getPage(n),v0=p.getViewport({scale:1}),sc=Math.max(1,Math.min(4,target/v0.width)),v=p.getViewport({scale:sc}),c=document.createElement('canvas');c.width=Math.ceil(v.width);c.height=Math.ceil(v.height);await p.render({canvasContext:c.getContext('2d'),viewport:v}).promise;return c.toDataURL('image/png')}

  function canvasGeom(){const c=document.getElementById('preview-canvas');if(!c)return null;const par=c.parentElement,cr=c.getBoundingClientRect(),pr=par.getBoundingClientRect();if(getComputedStyle(par).position==='static')par.style.position='relative';return{c,par,left:cr.left-pr.left,top:cr.top-pr.top,w:cr.width,h:cr.height}}
  function normalizedSizeForAspect(aspect,widthNorm=.42){const g=canvasGeom(),pageAspect=g?g.w/g.h:1.41421356237;let w=widthNorm,h=(w*pageAspect)/Math.max(.0001,aspect);if(h>.72){h=.72;w=(h*aspect)/pageAspect}return{w,h}}

  async function addMedia(dataUrl,w,h,name,meta={}){
    const p=pageNo(),aspect=w/Math.max(1,h),sz=normalizedSizeForAspect(aspect),obj={id:'pm_'+Date.now()+'_'+Math.random().toString(36).slice(2,7),x:(1-sz.w)/2,y:(1-sz.h)/2,w:sz.w,h:sz.h,aspect,name:name||'vložený soubor',kind:meta.kind||'image',sourcePage:meta.sourcePage||null,dataUrl,imageRef:null,sourceData:meta.sourceData||null,sourceRef:null};
    if(typeof window.saveImageToProject==='function'&&typeof currentProjectName!=='undefined'&&currentProjectName){
      try{obj.imageRef=await window.saveImageToProject(`presentation_media_preview_${Date.now()}.png`,dataUrl)}catch(e){console.warn(e)}
      if(obj.kind==='pdf'&&obj.sourceData){try{obj.sourceRef=await window.saveImageToProject(`presentation_media_source_${Date.now()}.pdf`,obj.sourceData)}catch(e){console.warn(e)}}
    }
    arr(p).push(obj);await persist();render();
  }

  function render(){
    document.querySelectorAll('.presentation-media-item').forEach(x=>x.remove());const g=canvasGeom();if(!g)return;const items=arr();
    items.forEach(o=>{if(!o.dataUrl)return;if(!o.aspect)o.aspect=(o.w*g.w)/Math.max(1,o.h*g.h);const d=document.createElement('div');d.className='presentation-media-item';d.dataset.id=o.id;d.style.left=(g.left+o.x*g.w)+'px';d.style.top=(g.top+o.y*g.h)+'px';d.style.width=(o.w*g.w)+'px';d.style.height=(o.h*g.h)+'px';d.innerHTML=`<img alt=""><button class="pm-delete" title="Smazat">×</button><span class="pm-resize" title="Změnit velikost"></span>`;d.querySelector('img').src=o.dataUrl;g.par.appendChild(d);wire(d,o,g)});
  }
  function wire(el,o,g){
    el.onpointerdown=e=>{if(e.target.closest('.pm-delete,.pm-resize'))return;select(el);const sx=e.clientX,sy=e.clientY,ox=o.x,oy=o.y;el.setPointerCapture(e.pointerId);el.onpointermove=ev=>{o.x=Math.max(0,Math.min(1-o.w,ox+(ev.clientX-sx)/g.w));o.y=Math.max(0,Math.min(1-o.h,oy+(ev.clientY-sy)/g.h));el.style.left=(g.left+o.x*g.w)+'px';el.style.top=(g.top+o.y*g.h)+'px'};el.onpointerup=()=>{el.onpointermove=null;persist()}};
    el.querySelector('.pm-resize').onpointerdown=e=>{e.stopPropagation();select(el);const sx=e.clientX,sy=e.clientY,ow=o.w,oh=o.h,owpx=ow*g.w,ohpx=oh*g.h,aspect=o.aspect||owpx/Math.max(1,ohpx),maxW=(1-o.x)*g.w,maxH=(1-o.y)*g.h;e.target.setPointerCapture(e.pointerId);e.target.onpointermove=ev=>{const dx=ev.clientX-sx,dy=ev.clientY-sy;let scale=Math.max(.08,(owpx+dx)/Math.max(1,owpx),(ohpx+dy)/Math.max(1,ohpx));scale=Math.min(scale,maxW/owpx,maxH/ohpx);const wpx=owpx*scale,hpx=wpx/aspect;o.w=wpx/g.w;o.h=hpx/g.h;el.style.width=wpx+'px';el.style.height=hpx+'px'};e.target.onpointerup=()=>{e.target.onpointermove=null;persist()}};
    el.querySelector('.pm-delete').onclick=e=>{e.stopPropagation();STATE.byPage[pageNo()]=arr().filter(x=>x.id!==o.id);persist();render()};
  }
  function select(el){document.querySelectorAll('.presentation-media-item').forEach(x=>x.classList.remove('selected'));el.classList.add('selected')}

  async function hydrate(){for(const list of Object.values(STATE.byPage))for(const o of list||[]){if(!o.dataUrl&&o.imageRef&&typeof window.loadImageFromProject==='function'){try{o.dataUrl=await window.loadImageFromProject(o.imageRef)}catch(e){}}if(o.kind==='pdf'&&!o.sourceData&&o.sourceRef&&typeof window.loadImageFromProject==='function'){try{o.sourceData=await window.loadImageFromProject(o.sourceRef)}catch(e){}}}render()}
  async function persist(){try{if(typeof window.persistProjectStructureNow==='function')await window.persistProjectStructureNow()}catch(e){console.warn('Uložení vloženého souboru',e)}}

  function wrapStructure(){
    if(STATE.wrapped)return;const build=window.buildPageRecords,apply=window.applyPageRecords;if(typeof build!=='function'||typeof apply!=='function')return;
    window.buildPageRecords=function(){const r=build.apply(this,arguments);r.forEach((rec,i)=>{const list=STATE.byPage[i+1];if(list?.length)rec.presentationMedia=list.map(o=>({...o,dataUrl:null,sourceData:null}))});return r};
    window.applyPageRecords=function(records){const media={};(records||[]).forEach((r,i)=>{if(r.presentationMedia?.length)media[i+1]=r.presentationMedia});const out=apply.apply(this,arguments);STATE.byPage=media;setTimeout(hydrate,0);return out};STATE.wrapped=true;
  }
  function wrapRender(){const fn=window.renderCurrentPagePreview;if(typeof fn!=='function'||fn.__pmWrapped)return;const w=async function(){const r=await fn.apply(this,arguments);await hydrate();return r};w.__pmWrapped=true;window.renderCurrentPagePreview=w}

  async function dataUrlBuffer(data){return fetch(data).then(r=>r.arrayBuffer())}

  function drawMediaWithCrop(pg,o,x,y,width,height,draw){
    const pts=o?.cropPoints;
    if(!pts||pts.length<3){draw();return}
    const ops=[PDFLib.pushGraphicsState(),PDFLib.moveTo(x+pts[0].x*width,y+(1-pts[0].y)*height)];
    for(let i=1;i<pts.length;i++)ops.push(PDFLib.lineTo(x+pts[i].x*width,y+(1-pts[i].y)*height));
    ops.push(PDFLib.closePath(),PDFLib.clip(),PDFLib.endPath());
    pg.pushOperators(...ops);draw();pg.pushOperators(PDFLib.popGraphicsState());
  }
  async function decoratePdf(pdf){
    const pages=pdf.getPages?.()||[];if(!pages.length)return;const count=Math.min(pages.length,Number((typeof totalPreviewPages!=='undefined'&&totalPreviewPages)||pages.length));
    for(let i=0;i<count;i++)for(const o of (STATE.byPage[i+1]||[])){
      const pg=pages[i],sz=pg.getSize(),x=o.x*sz.width,y=(1-o.y-o.h)*sz.height,width=o.w*sz.width,height=o.h*sz.height;
      try{
        if(o.kind==='pdf'){
          let source=o.sourceData;if(!source&&o.sourceRef&&typeof window.loadImageFromProject==='function')source=await window.loadImageFromProject(o.sourceRef);
          if(source){const bytes=await dataUrlBuffer(source),embedded=await pdf.embedPdf(bytes,[Math.max(0,(o.sourcePage||1)-1)]);if(embedded?.[0]){drawMediaWithCrop(pg,o,x,y,width,height,()=>pg.drawPage(embedded[0],{x,y,width,height}));continue}}
        }
        let data=o.dataUrl;if(!data&&o.imageRef&&typeof window.loadImageFromProject==='function')data=await window.loadImageFromProject(o.imageRef);if(!data)continue;
        const bytes=await dataUrlBuffer(data),img=data.startsWith('data:image/png')?await pdf.embedPng(bytes):await pdf.embedJpg(bytes);drawMediaWithCrop(pg,o,x,y,width,height,()=>pg.drawImage(img,{x,y,width,height}));
      }catch(e){console.warn('Export vloženého média',e)}
    }
  }
  function wrapRunPanel(){if(STATE.runWrapped||typeof window.runPanel!=='function'||!window.PDFLib?.PDFDocument)return;const orig=window.runPanel;window.runPanel=async function(){const proto=PDFLib.PDFDocument.prototype,save=proto.save;proto.save=async function(){if(!this.__pmDecorated){this.__pmDecorated=true;await decoratePdf(this)}return save.apply(this,arguments)};try{return await orig.apply(this,arguments)}finally{proto.save=save}};STATE.runWrapped=true}

  function init(){css();toolbar();modal();wrapStructure();wrapRender();wrapRunPanel();hydrate();setTimeout(()=>{toolbar();wrapStructure();wrapRender();wrapRunPanel();hydrate()},500);setTimeout(()=>{toolbar();wrapStructure();wrapRender();wrapRunPanel();hydrate()},1800)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();
