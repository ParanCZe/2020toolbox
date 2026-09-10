(()=>{
  const STYLE_ID='presentation-crop-modes-v334-style';

  function pageNo(){return Number((typeof currentPreviewPage!=='undefined'&&currentPreviewPage)||1)}
  function clamp(v,a=0,b=1){return Math.max(a,Math.min(b,v))}
  function save(){try{scheduleAutosave?.();persistProjectStructureNow?.()}catch(e){console.warn('Uložení cropu',e)}}
  function polygonCss(points){return points?.length>=3?`polygon(${points.map(p=>`${(p.x*100).toFixed(3)}% ${(p.y*100).toFixed(3)}%`).join(',')})`:''}
  function apply(host,obj){const img=host?.querySelector?.('img');if(img)img.style.clipPath=polygonCss(obj?.cropPoints)||''}

  function mediaObj(host){
    const list=window.presentationMediaState?.byPage?.[pageNo()]||[];
    return list.find(o=>String(o.id)===String(host?.dataset?.id));
  }
  function moodObj(host){
    const p=Number(host?.dataset?.page||pageNo()),i=Number(host?.dataset?.cellIndex);
    return (typeof allPagesTexts!=='undefined'&&allPagesTexts[p]?.cells?.[i])||null;
  }

  function css(){
    if(document.getElementById(STYLE_ID))return;
    const s=document.createElement('style');s.id=STYLE_ID;s.textContent=`
      .crop334{position:absolute;inset:0;z-index:120;background:rgba(255,255,255,.16);cursor:crosshair;touch-action:none;user-select:none}
      .crop334-toolbar{position:absolute;left:8px;top:8px;z-index:140;display:flex;align-items:center;gap:4px;padding:4px;background:#fff;border:1px solid #18181b;border-radius:7px;box-shadow:0 2px 10px rgba(0,0,0,.18)}
      .crop334-toolbar button{height:28px;padding:0 9px;border:1px solid #d4d4d8;border-radius:5px;background:#fff;color:#18181b;font-size:10px;font-weight:700;cursor:pointer;white-space:nowrap}
      .crop334-toolbar button.active,.crop334-toolbar button.ok{background:#f7f197;border-color:#18181b}
      .crop334-toolbar .sep{width:1px;height:20px;background:#d4d4d8;margin:0 2px}
      .crop334-svg{position:absolute;inset:0;width:100%;height:100%;pointer-events:none;overflow:visible}
      .crop334-rect{position:absolute;border:2px solid #18181b;background:rgba(247,241,151,.12);box-shadow:0 0 0 9999px rgba(255,255,255,.48);cursor:move;box-sizing:border-box}
      .crop334-h{position:absolute;width:11px;height:11px;border:1px solid #18181b;background:#f7f197;border-radius:2px;box-sizing:border-box}
      .crop334-h.nw{left:-6px;top:-6px;cursor:nwse-resize}.crop334-h.n{left:50%;top:-6px;transform:translateX(-50%);cursor:ns-resize}.crop334-h.ne{right:-6px;top:-6px;cursor:nesw-resize}
      .crop334-h.e{right:-6px;top:50%;transform:translateY(-50%);cursor:ew-resize}.crop334-h.se{right:-6px;bottom:-6px;cursor:nwse-resize}.crop334-h.s{left:50%;bottom:-6px;transform:translateX(-50%);cursor:ns-resize}.crop334-h.sw{left:-6px;bottom:-6px;cursor:nesw-resize}.crop334-h.w{left:-6px;top:50%;transform:translateY(-50%);cursor:ew-resize}
      .crop334-point{position:absolute;width:10px;height:10px;border:1px solid #18181b;background:#f7f197;border-radius:50%;transform:translate(-50%,-50%);cursor:grab;z-index:135}
      .crop334-help{position:absolute;left:8px;bottom:8px;z-index:140;background:rgba(255,255,255,.92);border:1px solid #d4d4d8;border-radius:5px;padding:4px 7px;font-size:9px;color:#52525b;pointer-events:none}
    `;document.head.appendChild(s);
  }

  function rectFromPoints(obj){
    if(obj?.cropMode==='rect'&&Array.isArray(obj.cropPoints)&&obj.cropPoints.length===4){
      const xs=obj.cropPoints.map(p=>p.x),ys=obj.cropPoints.map(p=>p.y);
      return{x1:clamp(Math.min(...xs)),y1:clamp(Math.min(...ys)),x2:clamp(Math.max(...xs)),y2:clamp(Math.max(...ys))};
    }
    return{x1:.1,y1:.1,x2:.9,y2:.9};
  }
  function rectPoints(r){return[{x:r.x1,y:r.y1},{x:r.x2,y:r.y1},{x:r.x2,y:r.y2},{x:r.x1,y:r.y2}]}

  function openCrop(host,obj,isMood){
    if(!host||!obj)return;
    host.querySelector('.crop334')?.remove();
    host.querySelector(isMood?'.mb-crop-edit':'.pm-crop-edit')?.remove();
    const oldPoints=Array.isArray(obj.cropPoints)?obj.cropPoints.map(p=>({...p})):null;
    const oldMode=obj.cropMode||'polygon';
    let mode=oldMode==='rect'?'rect':'polygon';
    let pts=oldPoints?.map(p=>({...p}))||[];
    let rect=rectFromPoints(obj);

    const layer=document.createElement('div');layer.className='crop334';
    layer.innerHTML=`<div class="crop334-toolbar"><button data-mode="rect">OBDÉLNÍK</button><button data-mode="polygon">POLYGON</button><span class="sep"></span><button class="ok" title="Potvrdit">✓</button><button class="cancel" title="Zrušit">×</button><button class="reset" title="Zrušit ořez">↺</button></div><svg class="crop334-svg" viewBox="0 0 100 100" preserveAspectRatio="none"><polygon fill="rgba(247,241,151,.14)" stroke="#18181b" stroke-width=".45" vector-effect="non-scaling-stroke"></polygon></svg><div class="crop334-help"></div>`;
    host.appendChild(layer);
    const toolbar=layer.querySelector('.crop334-toolbar'),poly=layer.querySelector('polygon'),help=layer.querySelector('.crop334-help');

    const norm=e=>{const r=layer.getBoundingClientRect();return{x:clamp((e.clientX-r.left)/Math.max(1,r.width)),y:clamp((e.clientY-r.top)/Math.max(1,r.height))}};
    function redrawPolygon(){
      layer.querySelectorAll('.crop334-point').forEach(n=>n.remove());
      poly.style.display='';poly.setAttribute('points',pts.map(p=>`${p.x*100},${p.y*100}`).join(' '));
      pts.forEach((p,i)=>{const h=document.createElement('span');h.className='crop334-point';h.style.left=(p.x*100)+'%';h.style.top=(p.y*100)+'%';h.dataset.i=i;layer.appendChild(h)});
    }
    function redrawRect(){
      poly.style.display='none';layer.querySelectorAll('.crop334-point,.crop334-rect').forEach(n=>n.remove());
      const r=document.createElement('div');r.className='crop334-rect';
      r.style.left=(rect.x1*100)+'%';r.style.top=(rect.y1*100)+'%';r.style.width=((rect.x2-rect.x1)*100)+'%';r.style.height=((rect.y2-rect.y1)*100)+'%';
      ['nw','n','ne','e','se','s','sw','w'].forEach(k=>{const h=document.createElement('span');h.className='crop334-h '+k;h.dataset.handle=k;r.appendChild(h)});layer.appendChild(r);
    }
    function redraw(){
      toolbar.querySelectorAll('[data-mode]').forEach(b=>b.classList.toggle('active',b.dataset.mode===mode));
      help.textContent=mode==='rect'?'Táhni prázdnou plochou pro nový výřez. Rohy/strany mění rozměr, uvnitř výřez posuneš.':'Klikáním přidávej body. Body můžeš následně posouvat.';
      if(mode==='rect')redrawRect();else redrawPolygon();
    }

    toolbar.addEventListener('pointerdown',e=>{e.stopPropagation();e.preventDefault()});
    toolbar.addEventListener('click',e=>{
      e.stopPropagation();const m=e.target.closest('[data-mode]');if(m){mode=m.dataset.mode;if(mode==='rect'&&oldMode!=='rect')rect={x1:.1,y1:.1,x2:.9,y2:.9};if(mode==='polygon'&&oldMode==='rect')pts=[];redraw();return}
    });

    let drag=null;
    layer.addEventListener('pointerdown',e=>{
      if(e.target.closest('.crop334-toolbar'))return;
      e.preventDefault();e.stopPropagation();
      const p=norm(e);
      if(mode==='polygon'){
        const point=e.target.closest('.crop334-point');
        if(point){drag={type:'point',i:Number(point.dataset.i),id:e.pointerId};layer.setPointerCapture(e.pointerId);return}
        pts.push(p);redrawPolygon();return;
      }
      const rr=e.target.closest('.crop334-rect'),hh=e.target.closest('.crop334-h');
      if(hh){drag={type:'resize',handle:hh.dataset.handle,start:p,base:{...rect},id:e.pointerId};layer.setPointerCapture(e.pointerId);return}
      if(rr){drag={type:'move',start:p,base:{...rect},id:e.pointerId};layer.setPointerCapture(e.pointerId);return}
      rect={x1:p.x,y1:p.y,x2:p.x,y2:p.y};drag={type:'new',start:p,id:e.pointerId};layer.setPointerCapture(e.pointerId);redrawRect();
    });
    layer.addEventListener('pointermove',e=>{
      if(!drag||drag.id!==e.pointerId)return;e.preventDefault();e.stopPropagation();const p=norm(e);
      if(drag.type==='point'){pts[drag.i]=p;redrawPolygon();return}
      if(drag.type==='new'){
        rect={x1:Math.min(drag.start.x,p.x),y1:Math.min(drag.start.y,p.y),x2:Math.max(drag.start.x,p.x),y2:Math.max(drag.start.y,p.y)};redrawRect();return;
      }
      if(drag.type==='move'){
        const w=drag.base.x2-drag.base.x1,h=drag.base.y2-drag.base.y1,dx=p.x-drag.start.x,dy=p.y-drag.start.y;
        let x1=clamp(drag.base.x1+dx,0,1-w),y1=clamp(drag.base.y1+dy,0,1-h);rect={x1,y1,x2:x1+w,y2:y1+h};redrawRect();return;
      }
      if(drag.type==='resize'){
        let r={...drag.base},k=drag.handle;
        if(k.includes('w'))r.x1=clamp(p.x,0,r.x2-.005);if(k.includes('e'))r.x2=clamp(p.x,r.x1+.005,1);
        if(k.includes('n'))r.y1=clamp(p.y,0,r.y2-.005);if(k.includes('s'))r.y2=clamp(p.y,r.y1+.005,1);
        rect=r;redrawRect();
      }
    });
    const end=e=>{if(drag&&drag.id===e.pointerId){try{layer.releasePointerCapture(e.pointerId)}catch(_){ }drag=null}};
    layer.addEventListener('pointerup',end);layer.addEventListener('pointercancel',end);

    toolbar.querySelector('.ok').addEventListener('click',e=>{
      e.preventDefault();e.stopPropagation();
      if(mode==='polygon'&&pts.length<3){alert('Pro polygonální ořez označ alespoň 3 body.');return}
      if(mode==='rect'&&((rect.x2-rect.x1)<.005||(rect.y2-rect.y1)<.005)){alert('Vytvoř větší obdélníkový výřez.');return}
      obj.cropMode=mode;obj.cropPoints=mode==='rect'?rectPoints(rect):pts.map(p=>({...p}));layer.remove();apply(host,obj);save();
    });
    toolbar.querySelector('.cancel').addEventListener('click',e=>{e.preventDefault();e.stopPropagation();obj.cropMode=oldMode;obj.cropPoints=oldPoints;layer.remove();apply(host,obj)});
    toolbar.querySelector('.reset').addEventListener('click',e=>{e.preventDefault();e.stopPropagation();obj.cropMode=null;obj.cropPoints=null;layer.remove();apply(host,obj);save()});
    redraw();
  }

  function cropButtonInfo(btn){
    if(!btn||btn.title!=='Ořez / maska')return null;
    const media=btn.closest('.presentation-media-item');if(media){const obj=mediaObj(media);return obj?{host:media,obj,isMood:false}:null}
    const mood=btn.closest('.moodboard-cell');if(mood){const obj=moodObj(mood);return obj?{host:mood,obj,isMood:true}:null}
    return null;
  }
  function intercept(e){
    const btn=e.target.closest?.('button[title="Ořez / maska"]');const info=cropButtonInfo(btn);if(!info)return;
    e.preventDefault();e.stopPropagation();e.stopImmediatePropagation();openCrop(info.host,info.obj,info.isMood);
  }
  function blockDrag(e){if(e.target.closest?.('.crop334,.crop334-toolbar')){e.stopPropagation()}}
  function init(){css();document.addEventListener('click',intercept,true);document.addEventListener('pointerdown',blockDrag,true)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();
