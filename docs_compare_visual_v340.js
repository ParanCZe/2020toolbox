(()=>{
  const DEFAULT='#dc2626';
  function hexToRgb(hex){const h=String(hex||DEFAULT).replace('#','');const n=parseInt(h.length===3?h.split('').map(x=>x+x).join(''):h,16);return{r:(n>>16)&255,g:(n>>8)&255,b:n&255}}
  function getColor(){return document.getElementById('compareDiffColor')?.value||localStorage.getItem('toolbox.compare.diffColor')||DEFAULT}
  function installUi(){
    const q=document.getElementById('compareQuality');if(!q)return;
    if(!document.getElementById('compareDiffColor')){
      const lab=document.createElement('label');lab.innerHTML=`Barva změn <span style="display:flex;align-items:center;gap:6px"><input id="compareDiffColor" type="color" value="${localStorage.getItem('toolbox.compare.diffColor')||DEFAULT}" style="width:38px;height:30px;padding:1px;border:1px solid #d4d4d8;border-radius:5px;background:#fff;cursor:pointer"><span id="compareDiffColorHex" class="compare-control-value"></span></span>`;
      q.closest('label')?.after(lab);
      const inp=lab.querySelector('input'),txt=lab.querySelector('#compareDiffColorHex');
      const sync=()=>{txt.textContent=inp.value.toUpperCase();localStorage.setItem('toolbox.compare.diffColor',inp.value);recolorVisible();window.scheduleCompareRender?.()};
      txt.textContent=inp.value.toUpperCase();inp.addEventListener('input',sync);inp.addEventListener('change',sync);
    }
    [...q.options].forEach(o=>{if(o.value==='standard')o.textContent='Standard · 3200 px';if(o.value==='high')o.textContent='Vysoká · 5200 px';if(o.value==='ultra')o.textContent='Tisková · 7200 px'});
    const note=document.querySelector('#docs-compare .docs-note');if(note)note.innerHTML='Výpočet změn probíhá ve vysokém rozlišení. Výsledek „Rozdíl“ se zobrazuje jako skutečné PDF: obě původní PDF stránky zůstávají vložené vektorově a zvýraznění změn se převádí na jemnou vektorovou vrstvu.';
  }
  function recolorCanvas(){const c=document.getElementById('compareCanvasDiff');if(!c||!c.width)return;const ctx=c.getContext('2d',{willReadFrequently:true});try{const im=ctx.getImageData(0,0,c.width,c.height),d=im.data,col=hexToRgb(getColor());let hit=false;for(let i=0;i<d.length;i+=4){if(d[i]>175&&d[i+1]<90&&d[i+2]<90){d[i]=col.r;d[i+1]=col.g;d[i+2]=col.b;hit=true}}if(hit)ctx.putImageData(im,0,0)}catch(_){}}
  function recolorSvg(){const host=document.getElementById('compareVectorDiff');if(!host)return;host.querySelectorAll('svg path[fill="#dc2626"],svg path[fill="#DC2626"]').forEach(p=>p.setAttribute('fill',getColor()))}
  function recolorVisible(){recolorCanvas();recolorSvg()}

  function collectFineRects(mask,w,h,maxRects=120000){
    function blockHit(x,y,step){const x2=Math.min(w,x+step),y2=Math.min(h,y+step);for(let yy=y;yy<y2;yy++){let i=yy*w+x;for(let xx=x;xx<x2;xx++,i++)if(mask[i])return true}return false}
    function collect(step){
      const done=[],active=new Map();
      for(let y=0;y<h;y+=step){
        const runs=[];let x=0;
        while(x<w){while(x<w&&!blockHit(x,y,step))x+=step;if(x>=w)break;const x0=x;x+=step;while(x<w&&blockHit(x,y,step))x+=step;runs.push([x0,Math.min(w,x)-x0])}
        const next=new Map();
        for(const [rx,rw] of runs){const key=rx+':'+rw,prev=active.get(key);if(prev&&prev[1]+prev[3]===y){prev[3]=Math.min(h,y+step)-prev[1];next.set(key,prev)}else{const r=[rx,y,rw,Math.min(step,h-y)];next.set(key,r)}}
        for(const [k,r] of active)if(!next.has(k))done.push(r);
        active.clear();for(const [k,r] of next)active.set(k,r);
        if(done.length+active.size>maxRects*1.35)return null;
      }
      for(const r of active.values())done.push(r);return done;
    }
    for(const step of [1,2,4]){const rects=collect(step);if(rects&&rects.length<=maxRects)return{rects,step}}
    const rects=collect(4)||[];return{rects:rects.slice(0,maxRects),step:4};
  }

  function showNativePdf(){
    const host=document.getElementById('compareVectorDiff');
    if(!host||!window.docsData?.compareDiffPdfUrl)return false;
    if(host.querySelector('iframe.compare-native-pdf'))return true;
    host.innerHTML='';host.classList.add('native-pdf-mode');host.dataset.vector='pdf';
    const frame=document.createElement('iframe');frame.className='compare-native-pdf';frame.title='Nativní PDF porovnání';frame.src=docsData.compareDiffPdfUrl+'#page=1&zoom=page-width';host.appendChild(frame);return true;
  }

  function installOverrides(){
    window.compareRenderTarget=function(){const q=document.getElementById('compareQuality')?.value||'high';return q==='ultra'?7200:q==='standard'?3200:5200};
    window.collectChangeRects=collectFineRects;
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
      const packed=collectFineRects(cleanChange,w,h,120000);
      const ink=rgb(col.r/255,col.g/255,col.b/255);
      for(const [x,y,rw,rh] of packed.rects){const X=x/scale,Y=pageH-(y+rh)/scale,W=rw/scale,H=rh/scale;if(W>0&&H>0)p.drawRectangle({x:X,y:Y,width:W,height:H,color:ink,opacity:.80})}
      const bytes=await out.save({useObjectStreams:true,addDefaultPage:false});
      revokeCompareDiffPdfUrl();docsData.compareDiffPdfBytes=bytes;docsData.compareDiffPdfUrl=URL.createObjectURL(new Blob([bytes],{type:'application/pdf'}));
      const host=document.getElementById('compareVectorDiff');if(host){host.innerHTML='';host.classList.add('native-pdf-mode');host.dataset.vector='pdf';host.dataset.baseWidth=String(pageW);host.dataset.baseHeight=String(pageH);host.dataset.diffSegments=String(packed.rects.length);host.dataset.diffCell=String(packed.step);showNativePdf()}
      return{rects:packed.rects.length,step:packed.step,pageW,pageH};
    };
    const orig=window.renderPdfComparison;
    if(typeof orig==='function'&&!orig.__v341){const wrapped=async function(...args){const r=await orig.apply(this,args);recolorVisible();showNativePdf();return r};wrapped.__v341=true;window.renderPdfComparison=wrapped}
  }
  function init(){installUi();installOverrides();setTimeout(()=>{installUi();installOverrides();recolorVisible();showNativePdf()},400)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();