(()=>{
  const DEFAULT='#dc2626';
  function hexToRgb(hex){const h=String(hex||DEFAULT).replace('#','');const n=parseInt(h.length===3?h.split('').map(x=>x+x).join(''):h,16);return{r:(n>>16)&255,g:(n>>8)&255,b:n&255}}
  function getColor(){return document.getElementById('compareDiffColor')?.value||localStorage.getItem('toolbox.compare.diffColor')||DEFAULT}
  function installUi(){
    const q=document.getElementById('compareQuality');if(!q||document.getElementById('compareDiffColor'))return;
    const lab=document.createElement('label');lab.innerHTML=`Barva změn <span style="display:flex;align-items:center;gap:6px"><input id="compareDiffColor" type="color" value="${localStorage.getItem('toolbox.compare.diffColor')||DEFAULT}" style="width:38px;height:30px;padding:1px;border:1px solid #d4d4d8;border-radius:5px;background:#fff;cursor:pointer"><span id="compareDiffColorHex" class="compare-control-value"></span></span>`;
    q.closest('label')?.after(lab);
    const inp=lab.querySelector('input'),txt=lab.querySelector('#compareDiffColorHex');
    const sync=()=>{txt.textContent=inp.value.toUpperCase();localStorage.setItem('toolbox.compare.diffColor',inp.value);recolorVisible();window.scheduleCompareRender?.()};
    txt.textContent=inp.value.toUpperCase();inp.addEventListener('input',sync);inp.addEventListener('change',sync);
    const note=document.querySelector('#docs-compare .docs-note');if(note)note.innerHTML=note.innerHTML.replace(/červené změny/gi,'barevně zvýrazněné změny').replace(/Červená vrstva/gi,'Vrstva změn');
  }
  function recolorCanvas(){
    const c=document.getElementById('compareCanvasDiff');if(!c||!c.width)return;const ctx=c.getContext('2d',{willReadFrequently:true});
    try{const im=ctx.getImageData(0,0,c.width,c.height),d=im.data,col=hexToRgb(getColor());let hit=false;for(let i=0;i<d.length;i+=4){if(d[i]>175&&d[i+1]<90&&d[i+2]<90){d[i]=col.r;d[i+1]=col.g;d[i+2]=col.b;hit=true}}if(hit)ctx.putImageData(im,0,0)}catch(_){ }
  }
  function recolorSvg(){const host=document.getElementById('compareVectorDiff');if(!host)return;host.querySelectorAll('svg path[fill="#dc2626"],svg path[fill="#DC2626"]').forEach(p=>p.setAttribute('fill',getColor()))}
  function recolorVisible(){recolorCanvas();recolorSvg()}

  function installOverrides(){
    // Higher raster working resolution. The final native diff PDF still keeps both source PDFs as vectors.
    window.compareRenderTarget=function(){const q=document.getElementById('compareQuality')?.value||'high';return q==='ultra'?4800:q==='standard'?2400:3600};

    window.buildNativeVectorDiffPdf=async function(cleanChange,w,h,scale,align,pageA,pageB){
      if(!window.PDFLib?.PDFDocument||!window.docsData?.compareA||!window.docsData?.compareB)throw new Error('PDF-lib není dostupný pro vektorové složení.');
      const {PDFDocument,rgb}=PDFLib,col=hexToRgb(getColor());
      const [aBytes,bBytes]=await Promise.all([docsData.compareA.arrayBuffer(),docsData.compareB.arrayBuffer()]);
      const out=await PDFDocument.create();
      const [aPage]=await out.embedPdf(aBytes,[Math.max(0,pageA-1)]),[bPage]=await out.embedPdf(bBytes,[Math.max(0,pageB-1)]);
      const pageW=w/scale,pageH=h/scale,dx=align.dx/scale,dy=align.dy/scale,p=out.addPage([pageW,pageH]);
      p.drawRectangle({x:0,y:0,width:pageW,height:pageH,color:rgb(1,1,1)});
      p.drawPage(aPage,{x:0,y:pageH-aPage.height,width:aPage.width,height:aPage.height,opacity:.34});
      p.drawPage(bPage,{x:dx,y:pageH-bPage.height-dy,width:bPage.width,height:bPage.height,opacity:.70});
      const packed=collectChangeRects(cleanChange,w,h);
      for(const [x,y,rw,rh] of packed.rects){const X=x/scale,Y=pageH-(y+rh)/scale,W=rw/scale,H=rh/scale;if(W<=0||H<=0)continue;p.drawRectangle({x:X,y:Y,width:W,height:H,color:rgb(col.r/255,col.g/255,col.b/255),opacity:.82})}
      const bytes=await out.save({useObjectStreams:true,addDefaultPage:false});
      revokeCompareDiffPdfUrl();docsData.compareDiffPdfBytes=bytes;docsData.compareDiffPdfUrl=URL.createObjectURL(new Blob([bytes],{type:'application/pdf'}));
      const host=document.getElementById('compareVectorDiff');if(host){host.innerHTML='';host.classList.add('native-pdf-mode');host.dataset.vector='pdf';host.dataset.baseWidth=String(pageW);host.dataset.baseHeight=String(pageH);host.dataset.diffSegments=String(packed.rects.length);host.dataset.diffCell=String(packed.step);const frame=document.createElement('iframe');frame.className='compare-native-pdf';frame.title='Nativní vektorové PDF porovnání';frame.src=docsData.compareDiffPdfUrl+'#page=1&zoom=page-width';host.appendChild(frame)}
      return{rects:packed.rects.length,step:packed.step,pageW,pageH};
    };

    const orig=window.renderPdfComparison;
    if(typeof orig==='function'&&!orig.__v340){const wrapped=async function(...args){const r=await orig.apply(this,args);recolorVisible();return r};wrapped.__v340=true;window.renderPdfComparison=wrapped}
  }
  function init(){installUi();installOverrides();setTimeout(()=>{installUi();installOverrides();recolorVisible()},400)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();