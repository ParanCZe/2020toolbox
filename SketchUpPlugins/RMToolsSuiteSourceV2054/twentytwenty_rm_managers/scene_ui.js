(function(){
  'use strict';
  if(!window.Manager)return;
  let state={scenes:[],section:{segments:[],bounds:[0,0,1,1]}};
  let selectedName=null,clickTimer=null;
  const oldReceive=Manager.receive.bind(Manager);
  const oldDraw=Manager.draw.bind(Manager);
  const oldPick=Manager.pickScene.bind(Manager);
  const oldActivate=Manager.activateScene.bind(Manager);
  const escapeHtml=x=>String(x==null?'':x).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const send=data=>sketchup.action(JSON.stringify(data));
  const get=id=>document.getElementById(id);

  function renderDetails(){
    const card=get('details');
    if(!card || !selectedName)return;
    const scene=state.scenes.find(x=>x.name===selectedName);
    if(!scene)return;
    if(scene.preview){
      if(!card.querySelector('.rm-detail-thumb')){
        const img=document.createElement('img');img.className='rm-detail-thumb';img.alt='Aktuální náhled záběru';
        card.insertBefore(img,card.children[1]||null);
      }
      card.querySelector('.rm-detail-thumb').src=scene.preview;
    }
    const ratio=get('ratio');
    if(ratio){
      ratio.onchange=function(){
        send({kind:'scene_ratio',name:scene.name,ratio:this.value});
      };
    }
    const focal=get('focal');
    if(focal){
      focal.onchange=function(){
        send({kind:'scene_focal',name:scene.name,focal:this.value});
      };
    }
  }

  function renderRows(){
    const tree=get('tree');
    if(!tree)return;
    const query=(get('search')?.value||'').toLocaleLowerCase('cs').trim();
    tree.innerHTML=state.scenes.filter(s=>s.name.toLocaleLowerCase('cs').includes(query)).map(s=>
      '<div class="rm-scene-row '+(s.name===selectedName||s.selected&&!selectedName?'selected':'')+
      '" data-scene="'+escapeHtml(s.name)+'" title="Dvojklik přepne na scénu">'+
      (s.preview?'<img class="rm-scene-thumb" src="'+s.preview+'" alt="Náhled '+escapeHtml(s.name)+'"/>':
       '<div class="rm-scene-no-thumb">KAMERA</div>')+
      '<div class="rm-scene-info"><strong>'+escapeHtml(s.name)+'</strong><small>'+
      (s.focal?s.focal+' mm':'Ortho')+' · '+escapeHtml(s.ratio||'bez rámečku')+
      '</small></div></div>').join('');
    tree.querySelectorAll('.rm-scene-row').forEach(row=>{
      row.addEventListener('click',e=>{
        if(e.detail>1)return;
        if(clickTimer)clearTimeout(clickTimer);
        clickTimer=setTimeout(()=>{selectedName=row.dataset.scene;oldPick(selectedName);renderRows();renderDetails();},240);
      });
      row.addEventListener('dblclick',()=>{
        if(clickTimer)clearTimeout(clickTimer);
        selectedName=row.dataset.scene;
        oldActivate(selectedName);renderRows();renderDetails();
      });
    });
  }

  function renderPlan(){
    const el=get('rmMiniMap');if(!el)return;
    const segments=state.section?.segments||[];
    const scenes=state.scenes||[];
    const bounds=state.section?.bounds||[0,0,1,1];
    const positions=scenes.filter(s=>s.eye&&s.eye.length===2).map(s=>s.eye);
    const xs=[bounds[0],bounds[2],...positions.map(p=>p[0])],
      ys=[bounds[1],bounds[3],...positions.map(p=>p[1])];
    let x0=Math.min(...xs),x1=Math.max(...xs),y0=Math.min(...ys),y1=Math.max(...ys);
    const pad=Math.max(x1-x0,y1-y0,1)*.075;
    x0-=pad;x1+=pad;y0-=pad;y1+=pad;
    const w=Math.max(0.1,x1-x0),h=Math.max(0.1,y1-y0);
    const pw=400,ph=265,k=Math.min(378/w,244/h),dx=(pw-w*k)/2,dy=(ph-h*k)/2;
    const pt=(x,y)=>[dx+(x-x0)*k, ph-dy-(y-y0)*k];
    const lines=segments.map(seg=>{
      if(seg.length<4)return '';
      const a=pt(seg[0],seg[1]),b=pt(seg[2],seg[3]);
      return '<path d="M'+a[0].toFixed(1)+' '+a[1].toFixed(1)+' L'+b[0].toFixed(1)+' '+b[1].toFixed(1)+'"/>';
    }).join('');
    const a=pt(bounds[0],bounds[1]),b=pt(bounds[2],bounds[3]);
    const outline=segments.length?'':'<rect x="'+Math.min(a[0],b[0])+'" y="'+Math.min(a[1],b[1])+
      '" width="'+Math.abs(b[0]-a[0])+'" height="'+Math.abs(b[1]-a[1])+
      '" fill="none" stroke="#6b7e89" stroke-dasharray="4 4"/>';
    const dots=scenes.map((s,i)=>{
      if(!s.eye||s.eye.length<2)return '';
      const p=pt(s.eye[0],s.eye[1]),dir=s.direction||[0,1],angle=Math.atan2(-dir[1],dir[0])*180/Math.PI;
      const selected=s.name===selectedName||(!selectedName&&s.selected),col=selected?'#ffd52a':'#e6ebed';
      return '<g class="rm-cam-dot" data-index="'+i+'" tabindex="0" role="button" aria-label="'+escapeHtml(s.name)+'" style="cursor:pointer">'+
        '<circle cx="'+p[0]+'" cy="'+p[1]+'" r="11" fill="transparent"/>'+
        '<circle cx="'+p[0]+'" cy="'+p[1]+'" r="'+(selected?5:4)+'" fill="'+col+'" stroke="#151b22" stroke-width="1.5"/>'+
        '<path d="M 6 0 L -3 -3 L -3 3 Z" transform="translate('+p[0]+' '+p[1]+') rotate('+angle+')" fill="'+col+'"/></g>';
    }).join('');
    el.innerHTML='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 265" aria-label="Půdorysný řez a pozice kamer">'+
      '<defs><pattern id="rmGrid" width="20" height="20" patternUnits="userSpaceOnUse"><path d="M20 0 L0 0 0 20" fill="none" stroke="#26313c" stroke-width=".65"/></pattern></defs>'+
      '<rect width="400" height="265" fill="url(#rmGrid)"/>'+
      '<g stroke="#9eb8bd" stroke-width="1.1" stroke-linecap="round" fill="none">'+lines+outline+'</g>'+
      dots+'<text x="12" y="18" fill="#adb8c4" font-size="10">ŘEZ +2 m</text>'+
      '<path d="M379 31 V9 L374 16 M379 9 L384 16" fill="none" stroke="#ffd52a"/>'+
      '<text x="379" y="43" fill="#ffd52a" font-size="10" text-anchor="middle">S</text></svg>'+
      '<div id="rmTooltip" class="rm-map-tooltip"></div>'+
      (!segments.length?'<div class="rm-map-help">V této výšce nejsou nalezeny řezové hrany; obrys je orientační.</div>':'');
    const tip=get('rmTooltip');
    const move=e=>{
      const rect=el.getBoundingClientRect(),tw=tip.offsetWidth||166,th=tip.offsetHeight||145;
      tip.style.left=Math.max(2,Math.min(e.clientX-rect.left+10,rect.width-tw-2))+'px';
      tip.style.top=Math.max(2,Math.min(e.clientY-rect.top+10,rect.height-th-2))+'px';
    };
    el.querySelectorAll('.rm-cam-dot').forEach(dot=>{
      const scene=scenes[Number(dot.dataset.index)];
      dot.addEventListener('mouseenter',e=>{
        tip.innerHTML='<strong>'+escapeHtml(scene.name)+'</strong>'+
          (scene.preview?'<img src="'+scene.preview+'" alt="Náhled záběru"/>':
             '<div class="rm-map-no-preview">Náhled se vytvoří po aktivaci záběru.</div>');
        tip.style.display='block';move(e);
      });
      dot.addEventListener('mousemove',move);
      dot.addEventListener('mouseleave',()=>{tip.style.display='none';});
      dot.addEventListener('click',e=>{
        if(e.detail>1)return;
        if(clickTimer)clearTimeout(clickTimer);
        clickTimer=setTimeout(()=>{selectedName=scene.name;oldPick(scene.name);renderAll();},240);
      });
      dot.addEventListener('dblclick',()=>{
        if(clickTimer)clearTimeout(clickTimer);
        selectedName=scene.name;oldActivate(scene.name);renderAll();
      });
    });
  }
  function renderAll(){renderRows();renderPlan();renderDetails();}

  Manager.receive=function(data){
    state=data;
    oldReceive(data);
    if(selectedName&&!data.scenes.some(s=>s.name===selectedName))selectedName=null;
    renderAll();
  };
  Manager.draw=function(){oldDraw();renderAll();};
  Manager.updatePreview=function(info){
    const scene=state.scenes.find(x=>x.name===info.name);
    if(scene){scene.preview=info.preview;renderAll();}
  };
  const ratio=get('viewRatio');
  if(ratio){
    ratio.addEventListener('change',function(){send({kind:'frame',ratio:this.value});});
  }
})();