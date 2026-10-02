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
    const parent=get('rmMiniMap');if(!parent)return;
    const plan=state.floorplan;
    if(!plan||!plan.image||!plan.rect){
      parent.innerHTML='<div class="rm-map-help" style="padding:22px 10px">Půdorys se právě připravuje nebo zatím nebyl vygenerován. Použij tlačítko Obnovit půdorys.</div>';
      return;
    }
    const rect=plan.rect;
    const sceneList=state.scenes||[];
    parent.innerHTML='<div class="rm-map-stage" style="position:relative;width:100%">'+
      '<img class="rm-map-base" alt="Půdorysný řez skutečného modelu ve výšce 2 m" src="'+plan.image+'"/>'+
      '<div id="rmTooltip" class="rm-map-tooltip"></div>'+
      '</div>';
    const stage=parent.querySelector('.rm-map-stage');
    const tip=get('rmTooltip');
    // Positions use SketchUp screen coordinates captured with the same camera
    // and viewport as the real cut screenshot. No approximation from bounds.
    const toPixel=(x,y)=>{
      const deltaX=(x-rect.world_center[0])/rect.world_unit;
      const deltaY=(y-rect.world_center[1])/rect.world_unit;
      return [rect.origin[0]+deltaX*rect.xaxis[0]+deltaY*rect.yaxis[0],
              rect.origin[1]+deltaX*rect.xaxis[1]+deltaY*rect.yaxis[1]];
    };
    const move=e=>{
      const r=stage.getBoundingClientRect(),w=tip.offsetWidth||166,h=tip.offsetHeight||145;
      tip.style.left=Math.max(2,Math.min(e.clientX-r.left+12,r.width-w-2))+'px';
      tip.style.top=Math.max(2,Math.min(e.clientY-r.top+12,r.height-h-2))+'px';
    };
    for(const scene of sceneList){
      if(!scene.eye||scene.eye.length!==2)continue;
      const uv=toPixel(scene.eye[0],scene.eye[1]);
      if(!uv.every(Number.isFinite)||uv[0]<0||uv[0]>1||uv[1]<0||uv[1]>1)continue;
      const dir=scene.direction||[0,1];
      // +X world points right; +Y world points up in our north-up top camera.
      const northRadians=Math.atan2(-dir[1],dir[0]),deg=northRadians*180/Math.PI;
      const selected=scene.name===selectedName||(!selectedName&&scene.selected);
      const col=selected?'#ffd52a':'#fff';
      const marker=document.createElement('button');
      marker.className='rm-cam-spot';
      marker.title=scene.name;
      marker.style.left=(uv[0]*100)+'%';
      marker.style.top=(uv[1]*100)+'%';
      marker.setAttribute('aria-label',scene.name+' – dvojklik aktivuje záběr');
      marker.innerHTML='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 22 22">'+
        '<circle cx="11" cy="11" r="4.3" fill="'+col+'" stroke="#121922" stroke-width="1.6"/>'+
        '<path d="M17 11L12 8L12 14Z" transform="rotate('+deg+' 11 11)" fill="'+col+'" stroke="#121922" stroke-width=".6"/></svg>';
      marker.addEventListener('mouseenter',e=>{
        tip.innerHTML='<strong>'+escapeHtml(scene.name)+'</strong>'+
          (scene.preview?'<img src="'+scene.preview+'" alt="Náhled záběru"/>':
           '<div class="rm-map-no-preview">Náhled vznikne po aktivaci nebo uložení scény.</div>');
        tip.style.display='block';
        move(e);
      });
      marker.addEventListener('mousemove',move);
      marker.addEventListener('mouseleave',()=>{tip.style.display='none';});
      marker.addEventListener('click',e=>{
        if(e.detail>1)return;
        if(clickTimer)clearTimeout(clickTimer);
        clickTimer=setTimeout(()=>{selectedName=scene.name;oldPick(scene.name);renderAll();},240);
      });
      marker.addEventListener('dblclick',()=>{
        if(clickTimer)clearTimeout(clickTimer);
        selectedName=scene.name;
        oldActivate(scene.name);
        renderAll();
      });
      stage.appendChild(marker);
    }
  }
  function renderAll(){renderRows();renderPlan();renderDetails();}

  Manager.receive=function(data){
    state=data;
    oldReceive(data);
    if(selectedName&&!data.scenes.some(s=>s.name===selectedName))selectedName=null;
    renderAll();
  };
  Manager.draw=function(){oldDraw();renderAll();};
  Manager.currentState=function(current){
    state.current=current;
    const focal=get('currentFocal'),frame=get('frameState'),ratio=get('viewRatio'),projection=get('currentProjection');
    if(focal)focal.textContent=current.focal?current.focal+' mm':'Rovnoběžné';
    if(frame)frame.textContent=current.frame?(current.ratio||'ZAPNUTO'):'VYPNUTO';
    if(ratio && current.ratio && Array.from(ratio.options).some(o=>o.value===current.ratio))ratio.value=current.ratio;
    if(projection)projection.textContent=(current.two_point?'2-bod ON · ':'')+(current.perspective?'Perspektiva':'Rovnoběžné promítání');
  };
  Manager.updatePreview=function(info){
    const scene=state.scenes.find(x=>x.name===info.name);
    if(scene){scene.preview=info.preview;renderAll();}
  };
  const ratio=get('viewRatio');
  if(ratio){
    ratio.addEventListener('change',function(){send({kind:'frame',ratio:this.value});});
  }
})();