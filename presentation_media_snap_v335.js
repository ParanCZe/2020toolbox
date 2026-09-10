(()=>{
  const SNAP_PX=10;
  function pageNo(){return Number((typeof currentPreviewPage!=='undefined'&&currentPreviewPage)||1)}
  function arr(){return window.presentationMediaState?.byPage?.[pageNo()]||[]}
  function geom(){const c=document.getElementById('preview-canvas');if(!c)return null;const par=c.parentElement,cr=c.getBoundingClientRect(),pr=par.getBoundingClientRect();return{par,left:cr.left-pr.left,top:cr.top-pr.top,w:cr.width,h:cr.height,cr,pr}}
  function objFor(el){return arr().find(o=>String(o.id)===String(el.dataset.id))}
  function persist(){try{window.persistProjectStructureNow?.()}catch(e){console.warn(e)}}
  function select(el){document.querySelectorAll('.presentation-media-item').forEach(x=>x.classList.remove('selected'));el.classList.add('selected')}
  function snap(v,target,tol){return Math.abs(v-target)<=tol?target:v}
  function snapMove(o,x,y,g){
    const tx=SNAP_PX/g.w,ty=SNAP_PX/g.h;
    for(const t of [0,1,-o.w,1-o.w])x=snap(x,t,tx);
    for(const t of [0,1,-o.h,1-o.h])y=snap(y,t,ty);
    return{x,y};
  }
  function updateEl(el,o,g){
    el.style.left=(g.left+o.x*g.w)+'px';el.style.top=(g.top+o.y*g.h)+'px';el.style.width=(o.w*g.w)+'px';el.style.height=(o.h*g.h)+'px';
    const tools=el.querySelector('.pm-mini-tools');if(tools){
      requestAnimationFrame(()=>{
        const er=el.getBoundingClientRect(),mr=document.getElementById('preview-main')?.getBoundingClientRect();if(!mr)return;
        tools.style.top=er.top-32<mr.top?'4px':'-29px';
        const tr=tools.getBoundingClientRect();
        if(tr.right>mr.right)tools.style.left=Math.max(4,er.width-tr.width-4)+'px';else if(tr.left<mr.left)tools.style.left=(mr.left-er.left+4)+'px';else tools.style.left='-1px';
      });
    }
  }
  function wire(el){
    if(el.dataset.snapV335==='1')return;el.dataset.snapV335='1';const o=objFor(el),g=geom();if(!o||!g)return;
    el.onpointerdown=e=>{
      if(e.target.closest('.pm-delete,.pm-resize,.pm-mini-tools,.crop334,.pm-crop-edit'))return;
      e.preventDefault();e.stopPropagation();select(el);const sx=e.clientX,sy=e.clientY,ox=o.x,oy=o.y;el.setPointerCapture(e.pointerId);
      el.onpointermove=ev=>{const p=snapMove(o,ox+(ev.clientX-sx)/g.w,oy+(ev.clientY-sy)/g.h,g);o.x=p.x;o.y=p.y;updateEl(el,o,g)};
      const end=()=>{el.onpointermove=null;el.onpointerup=null;el.onpointercancel=null;persist()};el.onpointerup=end;el.onpointercancel=end;
    };
    const rz=el.querySelector('.pm-resize');if(rz)rz.onpointerdown=e=>{
      e.preventDefault();e.stopPropagation();select(el);const sx=e.clientX,sy=e.clientY,ow=o.w,oh=o.h,owpx=ow*g.w,ohpx=oh*g.h,aspect=o.aspect||owpx/Math.max(1,ohpx);rz.setPointerCapture(e.pointerId);
      rz.onpointermove=ev=>{
        const dx=ev.clientX-sx,dy=ev.clientY-sy;let scale=Math.max(.08,(owpx+dx)/Math.max(1,owpx),(ohpx+dy)/Math.max(1,ohpx));
        let w=(owpx*scale)/g.w,h=((owpx*scale)/aspect)/g.h;
        const tx=SNAP_PX/g.w,ty=SNAP_PX/g.h;
        const right=o.x+w,bottom=o.y+h;
        if(Math.abs(right-1)<=tx){w=1-o.x;h=(w*g.w/aspect)/g.h}
        else if(Math.abs(right)<=tx){w=Math.max(.02,-o.x);h=(w*g.w/aspect)/g.h}
        if(Math.abs(bottom-1)<=ty){h=1-o.y;w=(h*g.h*aspect)/g.w}
        else if(Math.abs(bottom)<=ty){h=Math.max(.02,-o.y);w=(h*g.h*aspect)/g.w}
        o.w=Math.max(.02,w);o.h=Math.max(.02,h);updateEl(el,o,g);
      };
      const end=()=>{rz.onpointermove=null;rz.onpointerup=null;rz.onpointercancel=null;persist()};rz.onpointerup=end;rz.onpointercancel=end;
    };
    updateEl(el,o,g);
  }
  function decorate(){document.querySelectorAll('.presentation-media-item').forEach(wire)}
  function syncAll(){const g=geom();if(!g)return;document.querySelectorAll('.presentation-media-item').forEach(el=>{const o=objFor(el);if(o)updateEl(el,o,g)})}
  function css(){if(document.getElementById('presentation-media-snap-v335-style'))return;const s=document.createElement('style');s.id='presentation-media-snap-v335-style';s.textContent=`#canvas-container{overflow:visible!important}.presentation-media-item{overflow:visible!important}.presentation-media-item .pm-mini-tools{z-index:180!important}.presentation-media-item.selected{z-index:90!important}`;document.head.appendChild(s)}
  function init(){css();decorate();const obs=new MutationObserver(decorate);obs.observe(document.documentElement,{childList:true,subtree:true});document.addEventListener('presentation-canvas-fitted',()=>setTimeout(syncAll,0));document.addEventListener('presentation-zoom-resynced',()=>setTimeout(syncAll,0));setInterval(decorate,600)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();
