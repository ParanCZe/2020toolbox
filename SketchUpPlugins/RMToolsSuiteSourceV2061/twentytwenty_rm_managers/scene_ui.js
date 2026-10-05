(function(){
  'use strict';
  if(!window.Manager)return;
  let state={scenes:[],section:{segments:[],bounds:[0,0,1,1]}};
  let selectedId=null,clickTimer=null;
  const oldReceive=Manager.receive.bind(Manager);
  const oldDraw=Manager.draw.bind(Manager);
  const escapeHtml=x=>String(x==null?'':x).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const send=data=>sketchup.action(JSON.stringify(data));
  const get=id=>document.getElementById(id);

  function sceneForSettings(){
    return state.scenes.find(s=>s.id===selectedId) ||
           state.scenes.find(s=>s.selected) || null;
  }
  function renderSettings(){
    const current=state.current||{};
    const page=sceneForSettings();
    const selectedFocal=page ? page.focal : current.focal;
    const selectedRatio=page ? page.ratio : current.ratio;
    document.querySelectorAll('#viewTools [data-lens]').forEach(b=>{
      const active=selectedFocal!=null && Math.abs(Number(b.dataset.lens)-Number(selectedFocal))<.7;
      b.classList.toggle('rm-chosen',active);
      b.setAttribute('aria-pressed',String(active));
    });
    // One source of truth: top presets replace the duplicate camera editor.
  const tools=get('viewTools');
  if(tools){
    tools.querySelectorAll('.lensgrid button').forEach(button=>{
      const mm=Number(button.textContent.trim().replace(/[^\d.]/g,''));
      if(!mm)return;
      button.dataset.lens=String(mm);
      button.onclick=e=>{
        e.preventDefault();
        const scene=sceneForSettings();
        if(!scene){get('message').textContent='Nejdříve vyber scénu.';return;}
        send({kind:'quick_lens',id:scene.id,mm});
      };
    });
    // No second click needed and no duplicate frame-change callbacks.
    const show=Array.from(tools.querySelectorAll('button')).find(x=>x.textContent.trim()==='Zobrazit rám');
    const off=Array.from(tools.querySelectorAll('button')).find(x=>x.textContent.trim()==='Vypnout');
    if(show){
      show.id='rmFrameShow';
      show.onclick=e=>{
        e.preventDefault();
        const scene=sceneForSettings();
        if(!scene){get('message').textContent='Nejdříve vyber scénu.';return;}
        send({kind:'quick_ratio',id:scene.id,ratio:get('viewRatio').value});
      };
    }
    if(off){
      off.id='rmFrameOff';
      off.onclick=e=>{
        e.preventDefault();
        const scene=sceneForSettings();
        if(!scene){get('message').textContent='Nejdříve vyber scénu.';return;}
        send({kind:'quick_ratio',id:scene.id,ratio:'off'});
      };
    }
    const heightButton=Array.from(tools.querySelectorAll('button')).find(x=>x.textContent.trim()==='Výška 1,8 m');
    if(heightButton)heightButton.onclick=e=>{
      e.preventDefault();const scene=sceneForSettings();
      if(!scene){get('message').textContent='Nejdříve vyber scénu.';return;}
      send({kind:'quick_height',id:scene.id});
    };
    const twoButton=Array.from(tools.querySelectorAll('button')).find(x=>x.textContent.trim()==='2-bodová perspektiva');
    if(twoButton)twoButton.onclick=e=>{
      e.preventDefault();const scene=sceneForSettings();
      if(!scene){get('message').textContent='Nejdříve vyber scénu.';return;}
      send({kind:'quick_two_point',id:scene.id});
    };
  }
  const create=get('rmCreateName'),createBtn=get('rmCreateScene');
  if(create && !create.dataset.rmBound){
    create.dataset.rmBound='yes';
    create.addEventListener('input',()=>{create.dataset.auto='no';});
  }
  if(createBtn && !createBtn.dataset.rmBound){
    createBtn.dataset.rmBound='yes';
    createBtn.addEventListener('click',()=>{
    if(!create.value.trim()){get('message').textContent='Zadej název nové scény.';return;}
    send({kind:'create',name:create.value.trim()});
    create.dataset.auto='yes';
    });
  }
  const ratio=get('viewRatio');
    if(ratio && selectedRatio && Array.from(ratio.options).some(o=>o.value===selectedRatio)){
      ratio.value=selectedRatio;
    }
    const currentFocal=get('currentFocal'), frame=get('frameState');
    if(currentFocal)currentFocal.textContent=current.focal?current.focal+' mm':'–';
    if(frame)frame.textContent=current.frame?(current.ratio||'zapnuto'):'vypnuto';
    const btn=get('rmFrameOff');
    if(btn){btn.classList.toggle('rm-chosen', selectedRatio==='');btn.setAttribute('aria-pressed',String(selectedRatio===''));}
    const frameButton=get('rmFrameShow');
    if(frameButton){frameButton.classList.toggle('rm-chosen',selectedRatio!==''&&!!selectedRatio);}
    const two=Array.from(tools.querySelectorAll('button')).find(x=>x.textContent.trim()==='2-bodová perspektiva');
    if(two){two.classList.toggle('rm-chosen',!!page?.two_point);two.setAttribute('aria-pressed',String(!!page?.two_point));}
    const height=Array.from(tools.querySelectorAll('button')).find(x=>x.textContent.trim()==='Výška 1,8 m');
    if(height){height.classList.toggle('rm-chosen',!!page?.height_1800);height.setAttribute('aria-pressed',String(!!page?.height_1800));}
    const caption=get('rmSelectedScene');
    if(caption)caption.textContent=page?'Upravuješ scénu: '+page.name:'Nejdříve vyber scénu.';
  }
  function renderDetails(){
    const card=get('details'); if(!card)return;
    const scene=sceneForSettings();
    if(!scene){
      card.innerHTML='<h2>SCENE MANAGER</h2><p class="note">Vyber scénu vlevo. Novou vytvoříš nad půdorysem.</p>';
      renderSettings();return;
    }
    card.innerHTML='<h2>'+escapeHtml(scene.name)+'</h2>'+
      (scene.preview?'<img class="rm-detail-thumb" alt="Aktuální náhled scény" src="'+scene.preview+'"/>':
      '<p class="note">Náhled se vytvoří při otevření nebo uložení scény.</p>')+
      '<div class="line"><span class="small">Ohnisko</span><strong>'+escapeHtml(scene.focal?scene.focal+' mm':'Rovnoběžné')+'</strong></div>'+
      '<div class="line"><span class="small">Poměr stran</span><strong>'+escapeHtml(scene.ratio||'Bez rámečku')+'</strong></div>'+
      '<div class="line"><span class="small">Promítání</span><strong>'+escapeHtml(scene.perspective?'Perspektiva':'Rovnoběžné')+'</strong></div>'+
      '<p class="note">Ohnisko a formát nastavíš přímo předvolbami nahoře.</p>'+
      '<button class="primary rm-update-view" id="rmUpdateView" type="button">Aktualizovat záběr</button>'+
      '<p class="note">Uloží novou polohu a směr kamery ze současného pohledu, ale ponechá uložené ohnisko a poměr stran.</p>'+
      '<div class="line"><input id="rmRename" value="'+escapeHtml(scene.name)+'" aria-label="Název scény"/>'+
      '<button id="rmRenameBtn" type="button">Přejmenovat</button></div>'+
      '<button id="rmDeleteScene" class="rm-delete" type="button">Smazat scénu</button>';
    get('rmUpdateView').addEventListener('click',()=>send({kind:'update_view',id:scene.id}));
    get('rmRenameBtn').addEventListener('click',()=>send({kind:'rename',id:scene.id,new_name:get('rmRename').value}));
    get('rmDeleteScene').addEventListener('click',()=>{
      if(confirm('Opravdu smazat scénu '+scene.name+'?'))send({kind:'delete',id:scene.id});
    });
    renderSettings();
  }

  function defaultName(){
    const ids=state.scenes.map(s=>parseInt((s.name.match(/^([0-9]+)/)||[])[1],10)).filter(Number.isFinite);
    return String(Math.max(0,...ids)+1).padStart(2,'0')+' - EXTERIER - HLAVNI';
  }
  function newSceneForm(){
    const input=get('rmCreateName');
    if(input && document.activeElement!==input && (!input.value || input.dataset.auto==='yes')){
      input.value=defaultName();input.dataset.auto='yes';
    }
  }

  function renderSceneSets(){
    const select=get('rmSetSelect');
    if(!select)return;
    const previous=select.value;
    const sets=state.scene_sets||[];
    select.innerHTML=sets.length
      ? sets.map(set=>'<option value="'+escapeHtml(set.name)+'">'+escapeHtml(set.name)+' · '+Number(set.count||0)+' scén</option>').join('')
      : '<option value="">Žádné uložené sady</option>';
    if(previous && sets.some(set=>set.name===previous))select.value=previous;

    const save=get('rmSaveSet'),apply=get('rmApplySet'),del=get('rmDeleteSet'),name=get('rmSetName');
    if(save&&!save.dataset.rmBound){
      save.dataset.rmBound='yes';
      save.addEventListener('click',()=>{
        const value=name.value.trim();
        if(!value){get('message').textContent='Zadej název sady scén.';return;}
        send({kind:'scene_set_save',set_name:value});
      });
    }
    if(apply&&!apply.dataset.rmBound){
      apply.dataset.rmBound='yes';
      apply.addEventListener('click',()=>{
        if(!select.value){get('message').textContent='Nejdřív vyber uloženou sadu.';return;}
        if(confirm('Použít sadu '+select.value+'? Existující scény stejného názvu se nastaví podle sady a chybějící se vytvoří.'))
          send({kind:'scene_set_apply',set_name:select.value});
      });
    }
    if(del&&!del.dataset.rmBound){
      del.dataset.rmBound='yes';
      del.addEventListener('click',()=>{
        if(!select.value)return;
        if(confirm('Smazat sadu '+select.value+'?'))send({kind:'scene_set_delete',set_name:select.value});
      });
    }
  }

  function renderRows(){
    const tree=get('tree');
    if(!tree)return;
    const query=(get('search')?.value||'').toLocaleLowerCase('cs').trim();
    tree.innerHTML=state.scenes.filter(s=>s.name.toLocaleLowerCase('cs').includes(query)).map(s=>
      '<div class="rm-scene-row '+(s.id===selectedId||s.selected&&!selectedId?'selected':'')+
      '" data-id="'+escapeHtml(s.id)+'" data-scene="'+escapeHtml(s.name)+'" title="Dvojklik přepne na scénu">'+
      (s.preview?'<img class="rm-scene-thumb" src="'+s.preview+'" alt="Náhled '+escapeHtml(s.name)+'"/>':
       '<div class="rm-scene-no-thumb">KAMERA</div>')+
      '<div class="rm-scene-info"><strong>'+escapeHtml(s.name)+'</strong><small>'+
      (s.focal?s.focal+' mm':'Ortho')+' · '+escapeHtml(s.ratio||'bez rámečku')+
      '</small></div></div>').join('');
    tree.querySelectorAll('.rm-scene-row').forEach(row=>{
      row.addEventListener('click',e=>{
        if(e.detail>1)return;
        if(clickTimer)clearTimeout(clickTimer);
        clickTimer=setTimeout(()=>{selectedId=row.dataset.id;renderRows();renderDetails();},240);
      });
      row.addEventListener('dblclick',()=>{
        if(clickTimer)clearTimeout(clickTimer);
        selectedId=row.dataset.id;
        send({kind:'activate',id:selectedId});renderRows();renderDetails();
      });
    });
  }

  function renderPlan(){
    const parent=get('rmMiniMap');if(!parent)return;
    const plan=state.floorplan;
    if(!plan||!plan.image||!plan.rect){
      parent.innerHTML='<div class="rm-map-help" style="padding:22px 10px">'+
        '<strong>'+ (state.floorplan_error ? 'Generování půdorysu selhalo' : 'Půdorys není vygenerovaný') +'</strong>'+
        '<p>'+ (state.floorplan_error ? escapeHtml(state.floorplan_error) :
          'Oblast se určuje podle první kamery. Použij Obnovit půdorys, případně zavři rozpracovanou komponentu.') +'</p></div>';
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
    const toWorld=(u,v)=>{
      const sx=u-rect.origin[0], sy=v-rect.origin[1];
      const a=rect.xaxis[0], b=rect.yaxis[0], c=rect.xaxis[1], d=rect.yaxis[1];
      const det=a*d-b*c;
      if(!Number.isFinite(det)||Math.abs(det)<1e-12)return null;
      const dx=(sx*d-b*sy)/det*rect.world_unit;
      const dy=(a*sy-sx*c)/det*rect.world_unit;
      return [rect.world_center[0]+dx,rect.world_center[1]+dy];
    };
    const pointerUV=e=>{
      const box=stage.getBoundingClientRect();
      return [Math.max(0,Math.min(1,(e.clientX-box.left)/box.width)),
              Math.max(0,Math.min(1,(e.clientY-box.top)/box.height))];
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
      // Real saved camera forward vector. Looking vertically down has no XY
      // forward heading, so use camera's image-up direction in that case.
      const dir=scene.direction||[0,0];
      const heading=Math.hypot(dir[0],dir[1])>1e-6 ? dir : (scene.up||[0,1]);
      const screenDx=heading[0]*rect.xaxis[0]+heading[1]*rect.yaxis[0];
      const screenDy=heading[0]*rect.xaxis[1]+heading[1]*rect.yaxis[1];
      // Artwork's arrow points UP before rotation; compass rotation is
      // clockwise from image top, not from geographic north.
      const deg=Math.atan2(screenDx,-screenDy)*180/Math.PI;
      const selected=scene.id===selectedId||(!selectedId&&scene.selected);
      const col=selected?'#ffdb31':'#ffec8c';
      const marker=document.createElement('button');
      marker.className='rm-cam-spot';
      marker.title=scene.name;
      marker.style.left=(uv[0]*100)+'%';
      marker.style.top=(uv[1]*100)+'%';
      marker.setAttribute('aria-label',scene.name+' – dvojklik aktivuje záběr');
      marker.classList.toggle('rm-cam-selected',selected);
      marker.innerHTML='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36" aria-hidden="true">'+
        '<g transform="rotate('+deg+' 18 18)">'+
        '<path d="M18 0L30 20H6Z" fill="'+col+'" stroke="#050b10" stroke-width="3.5" stroke-linejoin="round"/>'+
        '<circle cx="18" cy="20" r="11" fill="#121a23" stroke="#fff" stroke-width="2.5"/>'+
        '<circle cx="18" cy="20" r="8" fill="'+col+'" stroke="#141b20" stroke-width="2.2"/>'+
        '<circle cx="18" cy="20" r="2.4" fill="#1a222b"/></g></svg>';
      marker.addEventListener('mouseenter',e=>{
        if(marker.classList.contains('rm-dragging'))return;
        tip.innerHTML='<strong>'+escapeHtml(scene.name)+'</strong>'+
          (scene.preview?'<img src="'+scene.preview+'" alt="Náhled záběru"/>':
           '<div class="rm-map-no-preview">Náhled vznikne po aktivaci nebo uložení scény.</div>');
        tip.style.display='block';
        move(e);
      });
      marker.addEventListener('mousemove',e=>{if(!marker.classList.contains('rm-dragging'))move(e);});
      marker.addEventListener('mouseleave',()=>{if(!marker.classList.contains('rm-dragging'))tip.style.display='none';});

      let holdTimer=null,dragging=false,downPoint=null;
      const cancelHold=()=>{if(holdTimer){clearTimeout(holdTimer);holdTimer=null;}};
      marker.addEventListener('pointerdown',e=>{
        if(e.button!==0)return;
        downPoint=[e.clientX,e.clientY];
        marker.setPointerCapture?.(e.pointerId);
        cancelHold();
        holdTimer=setTimeout(()=>{
          dragging=true;
          marker.classList.add('rm-dragging');
          tip.style.display='none';
          selectedId=scene.id;
          if(navigator.vibrate)navigator.vibrate(20);
        },1500);
      });
      marker.addEventListener('pointermove',e=>{
        if(!downPoint)return;
        if(!dragging){
          if(Math.hypot(e.clientX-downPoint[0],e.clientY-downPoint[1])>7)cancelHold();
          return;
        }
        e.preventDefault();
        const pos=pointerUV(e);
        marker.style.left=(pos[0]*100)+'%';
        marker.style.top=(pos[1]*100)+'%';
      });
      const finishDrag=e=>{
        cancelHold();
        if(dragging){
          e.preventDefault();
          const pos=pointerUV(e),world=toWorld(pos[0],pos[1]);
          marker.dataset.dragged='yes';
          dragging=false;
          marker.classList.remove('rm-dragging');
          if(world)send({kind:'move_scene_marker',id:scene.id,x:world[0],y:world[1]});
          setTimeout(()=>{delete marker.dataset.dragged;},350);
        }
        downPoint=null;
        try{marker.releasePointerCapture?.(e.pointerId);}catch(_err){}
      };
      marker.addEventListener('pointerup',finishDrag);
      marker.addEventListener('pointercancel',e=>{cancelHold();dragging=false;downPoint=null;marker.classList.remove('rm-dragging');});
      marker.addEventListener('click',e=>{
        if(marker.dataset.dragged==='yes'||e.detail>1)return;
        if(clickTimer)clearTimeout(clickTimer);
        clickTimer=setTimeout(()=>{selectedId=scene.id;renderAll();},240);
      });
      marker.addEventListener('dblclick',()=>{
        if(marker.dataset.dragged==='yes')return;
        if(clickTimer)clearTimeout(clickTimer);
        selectedId=scene.id;
        send({kind:'activate',id:selectedId});
        renderAll();
      });
      stage.appendChild(marker);
    }
  }
  function renderAll(){renderSceneSets();renderRows();renderPlan();renderDetails();newSceneForm();}

  Manager.receive=function(data){
    state=data;
    oldReceive(data);
    if(selectedId&&!data.scenes.some(s=>s.id===selectedId))selectedId=null;
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
  Manager.renamed=function(info){
    selectedId=info.id;
    const scene=state.scenes.find(x=>x.id===info.id);
    if(scene)scene.name=info.name;
    renderAll();
  };
  Manager.updatePreview=function(info){
    const scene=state.scenes.find(x=>x.id===info.id);
    if(scene){scene.preview=info.preview;renderAll();}
  };
  const ratio=get('viewRatio');
  if(ratio){
    ratio.addEventListener('change',function(){
      const scene=sceneForSettings();
      if(!scene){get('message').textContent='Nejdříve vyber scénu.';return;}
      send({kind:'quick_ratio',id:scene.id,ratio:this.value});
    });
  }
})();