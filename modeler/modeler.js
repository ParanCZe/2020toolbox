import * as THREE from 'three';
import {OrbitControls} from 'three/addons/controls/OrbitControls.js';
import {TransformControls} from 'three/addons/controls/TransformControls.js';
import {STLLoader} from 'three/addons/loaders/STLLoader.js';
import {OBJLoader} from 'three/addons/loaders/OBJLoader.js';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';
import {STLExporter} from 'three/addons/exporters/STLExporter.js';

const $=id=>document.getElementById(id), viewport=$('viewport');
const scene=new THREE.Scene();scene.background=new THREE.Color(0xe9e9ea);
const camera=new THREE.PerspectiveCamera(45,1,1,200000);camera.position.set(4500,3500,4500);
const renderer=new THREE.WebGLRenderer({antialias:true,preserveDrawingBuffer:true});renderer.setPixelRatio(Math.min(devicePixelRatio,2));renderer.shadowMap.enabled=true;viewport.appendChild(renderer.domElement);
const orbit=new OrbitControls(camera,renderer.domElement);orbit.enableDamping=true;orbit.target.set(0,500,0);orbit.screenSpacePanning=true;
const transform=new TransformControls(camera,renderer.domElement);scene.add(transform);transform.setTranslationSnap(10);transform.setRotationSnap(THREE.MathUtils.degToRad(5));
const work=new THREE.Group();work.name='MODEL';scene.add(work);
const helperLayer=new THREE.Group();helperLayer.name='HELPERS';scene.add(helperLayer);
const grid=new THREE.GridHelper(20000,100,0x999999,0xc8c8c8);scene.add(grid);
const axes=new THREE.AxesHelper(1200);axes.position.y=2;scene.add(axes);
scene.add(new THREE.HemisphereLight(0xffffff,0x777777,2.4));const sun=new THREE.DirectionalLight(0xffffff,2.2);sun.position.set(6000,9000,5000);sun.castShadow=true;scene.add(sun);

const ray=new THREE.Raycaster(),pointer=new THREE.Vector2(),ground=new THREE.Plane(new THREE.Vector3(0,1,0),0);
let selected=null,history=[],redo=[],restoring=false,toastTimer=null,tool='select',sketchPts=[],preview=null,toolStart=null,pushState=null,measureObj=null;
const edgeMaterial=new THREE.LineBasicMaterial({color:0x303030});

function toast(t){const el=$('toast');el.textContent=t;el.classList.add('show');clearTimeout(toastTimer);toastTimer=setTimeout(()=>el.classList.remove('show'),1700)}
function status(t,v='—'){$('statusText').textContent=t;$('statusValue').textContent=v}
function resize(){const w=viewport.clientWidth,h=viewport.clientHeight;renderer.setSize(w,h,false);camera.aspect=w/h;camera.updateProjectionMatrix()}addEventListener('resize',resize);resize();
function render(){orbit.update();renderer.render(scene,camera);requestAnimationFrame(render)}render();
function material(color=0xc9c9c9,opacity=1){return new THREE.MeshStandardMaterial({color,roughness:.72,metalness:.04,side:THREE.DoubleSide,transparent:opacity<1,opacity})}
function addEdges(o){o.traverse?.(m=>{if(m.isMesh&&!m.userData.edgeHelper){const e=new THREE.LineSegments(new THREE.EdgesGeometry(m.geometry,18),edgeMaterial.clone());e.userData.edgeHelper=true;e.raycast=()=>{};m.add(e)}})}
function refreshEdges(){work.traverse(o=>{if(o.userData.edgeHelper)o.visible=$('edgesToggle').checked})}
function addObject(obj,name='Objekt',push=true){if(push)pushHistory();obj.name=name;obj.traverse?.(o=>{if(o.isMesh){o.castShadow=true;o.receiveShadow=true;if(!o.material)o.material=material()}});addEdges(obj);work.add(obj);select(obj);updateStats();refreshEdges()}
function addPrimitive(type){let g,n;if(type==='box'){g=new THREE.BoxGeometry(1000,1000,1000);n='Kvádr'}if(type==='cylinder'){g=new THREE.CylinderGeometry(500,500,1000,48);n='Válec'}if(type==='sphere'){g=new THREE.SphereGeometry(500,40,24);n='Koule'}if(type==='plane'){g=new THREE.BoxGeometry(1200,100,1200);n='Deska'}const m=new THREE.Mesh(g,material());m.position.y=(type==='plane'?50:500);addObject(m,n)}
function selectableRoot(o){while(o&&o.parent&&o.parent!==work)o=o.parent;return o?.parent===work?o:null}
function localDims(o){const box=new THREE.Box3().setFromObject(o);const s=new THREE.Vector3();box.getSize(s);return s}
function select(o){selected=o;transform.detach();if(o&&tool==='select')transform.attach(o);syncPanel()}
function syncPanel(){const p=$('objectPanel'),no=$('noSelection');p.hidden=!selected;no.hidden=!!selected;if(!selected){$('faceTools').hidden=true;return}const d=localDims(selected);$('objName').value=selected.name||'Objekt';$('dimX').value=d.x.toFixed(1);$('dimY').value=d.y.toFixed(1);$('dimZ').value=d.z.toFixed(1);$('posX').value=selected.position.x.toFixed(1);$('posY').value=selected.position.y.toFixed(1);$('posZ').value=selected.position.z.toFixed(1);$('rotX').value=THREE.MathUtils.radToDeg(selected.rotation.x).toFixed(1);$('rotY').value=THREE.MathUtils.radToDeg(selected.rotation.y).toFixed(1);$('rotZ').value=THREE.MathUtils.radToDeg(selected.rotation.z).toFixed(1);let mesh=null;selected.traverse?.(o=>{if(!mesh&&o.isMesh&&!o.userData.edgeHelper)mesh=o});if(selected.isMesh)mesh=selected;if(mesh?.material?.color)$('objColor').value='#'+mesh.material.color.getHexString();$('faceTools').hidden=!selected.userData.isFace}
function pushHistory(){if(restoring)return;history.push(work.clone(true));if(history.length>40)history.shift();redo=[]}
function restore(snapshot){restoring=true;transform.detach();work.clear();for(const c of snapshot.children)work.add(c.clone(true));selected=null;syncPanel();updateStats();refreshEdges();restoring=false}
function undo(){if(!history.length)return;redo.push(work.clone(true));restore(history.pop())}function redoFn(){if(!redo.length)return;history.push(work.clone(true));restore(redo.pop())}
transform.addEventListener('dragging-changed',e=>orbit.enabled=!e.value);transform.addEventListener('mouseDown',pushHistory);transform.addEventListener('objectChange',()=>{syncPanel();updateStats()});
function setMode(mode){setTool('select');transform.setMode(mode);document.querySelectorAll('[data-mode]').forEach(b=>b.classList.toggle('active',b.dataset.mode===mode));if(selected)transform.attach(selected)}
function duplicate(){if(!selected)return;pushHistory();const c=selected.clone(true);c.position.x+=150;c.position.z+=150;c.name=(selected.name||'Objekt')+' kopie';work.add(c);select(c);updateStats()}
function del(){if(!selected)return;pushHistory();work.remove(selected);select(null);updateStats()}
function newModel(){if(work.children.length&&!confirm('Založit nový model a zahodit aktuální scénu?'))return;pushHistory();work.clear();select(null);clearToolState();updateStats();toast('Nový prázdný model')}
function fitObject(o){const b=new THREE.Box3().setFromObject(o),s=new THREE.Vector3(),c=new THREE.Vector3();b.getSize(s);b.getCenter(c);const max=Math.max(s.x,s.y,s.z,1000),dist=max*2.3;camera.position.set(c.x+dist,c.y+dist*.8,c.z+dist);orbit.target.copy(c);orbit.update()}
async function openFile(file){if(!file)return;const ext=file.name.split('.').pop().toLowerCase(),buf=await file.arrayBuffer();try{let obj;if(ext==='stl'){const geo=new STLLoader().parse(buf);obj=new THREE.Mesh(geo,material());obj.name=file.name}else if(ext==='obj'){obj=new OBJLoader().parse(new TextDecoder().decode(buf));obj.name=file.name;obj.traverse(o=>{if(o.isMesh&&!o.material)o.material=material()})}else if(ext==='glb'||ext==='gltf'){const loader=new GLTFLoader();const gltf=await new Promise((res,rej)=>loader.parse(buf,'',res,rej));obj=gltf.scene;obj.name=file.name}else throw new Error('Nepodporovaný formát');addObject(obj,file.name);fitObject(obj);toast('Model načten')}catch(e){alert('Model se nepodařilo načíst: '+(e.message||e))}}
function exportStlBlob(){const ex=new STLExporter(),data=ex.parse(work,{binary:true});return new Blob([data],{type:'model/stl'})}
function download(){if(!work.children.length){toast('Model je prázdný');return}const blob=exportStlBlob(),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='20-20-model.stl';a.click();setTimeout(()=>URL.revokeObjectURL(url),1500)}
function openDb(){return new Promise((res,rej)=>{const r=indexedDB.open('20-20-toolbox-transfer',1);r.onupgradeneeded=()=>r.result.createObjectStore('files');r.onsuccess=()=>res(r.result);r.onerror=()=>rej(r.error)})}
async function sendPrint(){if(!work.children.length){toast('Model je prázdný');return}try{const db=await openDb(),blob=exportStlBlob();await new Promise((res,rej)=>{const tx=db.transaction('files','readwrite');tx.objectStore('files').put({blob,name:'20-20-modeler.stl',time:Date.now()},'modeler-to-print');tx.oncomplete=res;tx.onerror=()=>rej(tx.error)});location.href='../index.html?tool=3dprint&import=modeler'}catch(e){alert('Předání do 3D tisku selhalo: '+(e.message||e))}}
function updateStats(){let meshes=0,tris=0;work.traverse(o=>{if(o.isMesh&&!o.userData.edgeHelper){meshes++;const g=o.geometry;tris+=g.index?g.index.count/3:(g.attributes.position?.count||0)/3}});$('stats').textContent=`${work.children.length} objektů · ${meshes} meshů · ${Math.round(tris).toLocaleString('cs-CZ')} trojúhelníků`}
function setView(v){const c=selected?new THREE.Box3().setFromObject(selected).getCenter(new THREE.Vector3()):new THREE.Vector3(0,500,0),d=5000;if(v==='top')camera.position.set(c.x,c.y+d,c.z+.01);if(v==='front')camera.position.set(c.x,c.y,c.z+d);if(v==='right')camera.position.set(c.x+d,c.y,c.z);if(v==='iso')camera.position.set(c.x+d,c.y+d*.75,c.z+d);orbit.target.copy(c);camera.lookAt(c);orbit.update()}

function setTool(t){tool=t;clearToolState();transform.detach();document.querySelectorAll('[data-tool]').forEach(b=>b.classList.toggle('active',b.dataset.tool===t));viewport.className='tool-'+t;$('toolBadge').textContent=({select:'VÝBĚR',line:'ČÁRA / POLYGON',rect:'OBDÉLNÍK',circle:'KRUH',measure:'MĚŘENÍ',pushpull:'PUSH / PULL'})[t]||t.toUpperCase();orbit.enabled=t==='select';if(t==='select'&&selected)transform.attach(selected);status(t==='select'?'Kliknutím vyber objekt':'Klikni do pracovní roviny')}
function clearToolState(){sketchPts=[];toolStart=null;pushState=null;if(preview){helperLayer.remove(preview);preview=null}if(measureObj){helperLayer.remove(measureObj);measureObj=null}$('measureOverlay').style.display='none'}
function screenPointer(e){const r=renderer.domElement.getBoundingClientRect();pointer.x=((e.clientX-r.left)/r.width)*2-1;pointer.y=-((e.clientY-r.top)/r.height)*2+1;ray.setFromCamera(pointer,camera)}
function endpointCandidates(){const pts=[];work.traverse(o=>{if(o.userData.shapePts){o.userData.shapePts.forEach(p=>{const v=new THREE.Vector3(p.x,0,p.y);o.localToWorld(v);pts.push(v)})}});return pts}
function snapPoint(p){const out=p.clone(),snap=Number($('snapSize').value)||10;if($('snapToggle').checked){out.x=Math.round(out.x/snap)*snap;out.y=Math.round(out.y/snap)*snap;out.z=Math.round(out.z/snap)*snap}if($('endpointSnap').checked){let best=null,bd=60;for(const c of endpointCandidates()){const d=c.distanceTo(out);if(d<bd){bd=d;best=c}}if(best)out.copy(best)}return out}
function groundPoint(e){screenPointer(e);const p=new THREE.Vector3();if(!ray.ray.intersectPlane(ground,p))return null;return snapPoint(p)}
function linePreview(points,last){if(preview)helperLayer.remove(preview);const arr=[...points,last].filter(Boolean);if(arr.length<2)return;const g=new THREE.BufferGeometry().setFromPoints(arr),m=new THREE.LineBasicMaterial({color:0xd97706});preview=new THREE.Line(g,m);helperLayer.add(preview)}
function makeFace(points,name='Plocha'){if(points.length<3)return null;const shape=new THREE.Shape();shape.moveTo(points[0].x,points[0].z);for(let i=1;i<points.length;i++)shape.lineTo(points[i].x,points[i].z);shape.closePath();const g=new THREE.ShapeGeometry(shape),m=new THREE.Mesh(g,material(0xf7f197,.92));m.rotation.x=-Math.PI/2;m.position.y=.5;m.userData.isFace=true;m.userData.shapePts=points.map(p=>({x:p.x,y:p.z}));m.userData.baseY=0;addObject(m,name);return m}
function shapeFromPts(arr){const s=new THREE.Shape();s.moveTo(arr[0].x,arr[0].y);for(let i=1;i<arr.length;i++)s.lineTo(arr[i].x,arr[i].y);s.closePath();return s}
function extrudeFace(face,height){if(!face?.userData.isFace)return;const pts=face.userData.shapePts;if(!pts?.length)return;pushHistory();const shape=shapeFromPts(pts),g=new THREE.ExtrudeGeometry(shape,{depth:Math.max(.1,Math.abs(height)),bevelEnabled:false,curveSegments:32});const mesh=new THREE.Mesh(g,material());mesh.rotation.x=-Math.PI/2;mesh.position.copy(face.position);mesh.position.y=face.position.y;if(height<0){mesh.rotation.x=Math.PI/2;mesh.position.y=face.position.y}mesh.name=(face.name||'Plocha')+' solid';mesh.userData.sourceShapePts=pts.map(p=>({...p}));work.remove(face);addObject(mesh,mesh.name,false);syncPanel();updateStats();toast(`Vytaženo ${Math.round(height)} mm`)}
function exactPush(){if(!selected?.userData.isFace)return;extrudeFace(selected,Number($('pushHeight').value)||1000)}
function makeCircleFace(c,r){const pts=[];for(let i=0;i<48;i++){const a=i/48*Math.PI*2;pts.push(new THREE.Vector3(c.x+Math.cos(a)*r,0,c.z+Math.sin(a)*r))}makeFace(pts,'Kruhová plocha')}
function distanceLabel(a,b){return `${a.distanceTo(b).toFixed(1)} mm`}

renderer.domElement.addEventListener('pointerdown',e=>{
  if(transform.dragging||e.button!==0)return;
  if(tool==='select'){screenPointer(e);const hits=ray.intersectObjects(work.children,true).filter(h=>!h.object.userData.edgeHelper);if(hits.length)select(selectableRoot(hits[0].object));else select(null);return}
  if(tool==='pushpull'){screenPointer(e);const hits=ray.intersectObjects(work.children,true).filter(h=>selectableRoot(h.object)?.userData.isFace);const f=hits[0]?selectableRoot(hits[0].object):null;if(!f){toast('Push/Pull vyžaduje nakreslenou plochu');return}select(f);pushState={face:f,startY:e.clientY,height:0};status('Táhni myší nahoru / dolů, kliknutím potvrď','0 mm');return}
  const p=groundPoint(e);if(!p)return;
  if(tool==='line'){
    if(!sketchPts.length){sketchPts=[p];status('Další bod · klikni na první bod pro uzavření','0 mm');return}
    const first=sketchPts[0];if(sketchPts.length>=3&&p.distanceTo(first)<Math.max(30,(Number($('snapSize').value)||10)*2)){makeFace(sketchPts,'Polygon');clearToolState();status('Plocha vytvořena');return}
    sketchPts.push(p);status('Další bod · klikni na první bod pro uzavření',distanceLabel(sketchPts[sketchPts.length-2],p));return
  }
  if(tool==='rect'){if(!toolStart){toolStart=p;status('Klikni na protilehlý roh');return}const a=toolStart,b=p;makeFace([new THREE.Vector3(a.x,0,a.z),new THREE.Vector3(b.x,0,a.z),new THREE.Vector3(b.x,0,b.z),new THREE.Vector3(a.x,0,b.z)],'Obdélníková plocha');clearToolState();status('Obdélník vytvořen',`${Math.abs(b.x-a.x).toFixed(1)} × ${Math.abs(b.z-a.z).toFixed(1)} mm`);return}
  if(tool==='circle'){if(!toolStart){toolStart=p;status('Klikni pro poloměr');return}const r=toolStart.distanceTo(p);makeCircleFace(toolStart,r);clearToolState();status('Kruh vytvořen',`R ${r.toFixed(1)} mm`);return}
  if(tool==='measure'){if(!toolStart){toolStart=p;status('Klikni na druhý bod');return}const d=distanceLabel(toolStart,p),g=new THREE.BufferGeometry().setFromPoints([toolStart,p]),m=new THREE.LineBasicMaterial({color:0x2563eb});measureObj=new THREE.Line(g,m);helperLayer.add(measureObj);$('measureOverlay').textContent=d;$('measureOverlay').style.display='block';toolStart=null;status('Změřeno',d);return}
});
renderer.domElement.addEventListener('pointermove',e=>{
  if(pushState){const h=(pushState.startY-e.clientY)*10;pushState.height=h;$('statusValue').textContent=`${h.toFixed(0)} mm`;return}
  if(tool==='select')return;const p=groundPoint(e);if(!p)return;
  if(tool==='line'&&sketchPts.length)linePreview(sketchPts,p);
  if(tool==='rect'&&toolStart){const a=toolStart,b=p;linePreview([a,new THREE.Vector3(b.x,0,a.z),b],new THREE.Vector3(a.x,0,b.z));status('Klikni na protilehlý roh',`${Math.abs(b.x-a.x).toFixed(1)} × ${Math.abs(b.z-a.z).toFixed(1)} mm`)}
  if(tool==='circle'&&toolStart){const r=toolStart.distanceTo(p),pts=[];for(let i=0;i<=48;i++){const a=i/48*Math.PI*2;pts.push(new THREE.Vector3(toolStart.x+Math.cos(a)*r,0,toolStart.z+Math.sin(a)*r))}if(preview)helperLayer.remove(preview);preview=new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts),new THREE.LineBasicMaterial({color:0xd97706}));helperLayer.add(preview);status('Klikni pro poloměr',`R ${r.toFixed(1)} mm`)}
  if(tool==='measure'&&toolStart){linePreview([toolStart],p);status('Klikni na druhý bod',distanceLabel(toolStart,p))}
});
renderer.domElement.addEventListener('pointerup',e=>{
  if(pushState&&Math.abs(e.clientY-pushState.startY)>3){const st=pushState;pushState=null;extrudeFace(st.face,st.height||10);setTool('select')}
});

function faceFromSketch(){if(sketchPts.length>=3){makeFace(sketchPts,'Plocha');clearToolState();setTool('select')}else toast('Nejdřív nakresli alespoň 3 body')}

document.querySelectorAll('[data-add]').forEach(b=>b.onclick=()=>addPrimitive(b.dataset.add));document.querySelectorAll('[data-mode]').forEach(b=>b.onclick=()=>setMode(b.dataset.mode));document.querySelectorAll('[data-view]').forEach(b=>b.onclick=()=>setView(b.dataset.view));document.querySelectorAll('[data-tool]').forEach(b=>b.onclick=()=>setTool(b.dataset.tool));
$('btnDuplicate').onclick=duplicate;$('btnDelete').onclick=del;$('btnUndo').onclick=undo;$('btnRedo').onclick=redoFn;$('btnNew').onclick=newModel;$('btnOpen').onclick=()=>$('fileOpen').click();$('fileOpen').onchange=()=>openFile($('fileOpen').files?.[0]);$('btnDownload').onclick=download;$('btnPrint').onclick=sendPrint;$('btnPushExact').onclick=exactPush;$('btnFaceFromSelection').onclick=faceFromSketch;
$('gridToggle').onchange=e=>grid.visible=e.target.checked;$('snapToggle').onchange=e=>{transform.setTranslationSnap(e.target.checked?(Number($('snapSize').value)||10):null)};$('snapSize').onchange=()=>{if($('snapToggle').checked)transform.setTranslationSnap(Number($('snapSize').value)||10)};$('edgesToggle').onchange=refreshEdges;
$('objName').onchange=e=>{if(selected){pushHistory();selected.name=e.target.value||'Objekt';syncPanel()}};$('objColor').oninput=e=>{if(!selected)return;selected.traverse(o=>{if(o.isMesh&&!o.userData.edgeHelper&&o.material?.color)o.material.color.set(e.target.value)});if(selected.isMesh&&selected.material?.color)selected.material.color.set(e.target.value)};
['posX','posY','posZ'].forEach((id,i)=>$(id).onchange=e=>{if(!selected)return;pushHistory();selected.position.setComponent(i,Number(e.target.value)||0);syncPanel()});
['rotX','rotY','rotZ'].forEach((id,i)=>$(id).onchange=e=>{if(!selected)return;pushHistory();selected.rotation.setComponent(i,THREE.MathUtils.degToRad(Number(e.target.value)||0));syncPanel()});
['dimX','dimY','dimZ'].forEach((id,i)=>$(id).onchange=e=>{if(!selected)return;const cur=localDims(selected).getComponent(i),target=Math.max(.001,Number(e.target.value)||cur);if(cur>0){pushHistory();selected.scale.setComponent(i,selected.scale.getComponent(i)*(target/cur));syncPanel()}});
addEventListener('keydown',e=>{if(/INPUT|TEXTAREA|SELECT/.test(document.activeElement?.tagName))return;const k=e.key.toLowerCase();if(k==='escape'){setTool('select');return}if(k==='l')setTool('line');if(k==='b')setTool('rect');if(k==='c')setTool('circle');if(k==='p')setTool('pushpull');if(k==='m')setTool('measure');if(k==='w')setMode('translate');if(k==='e')setMode('rotate');if(k==='r')setMode('scale');if(e.key==='Delete')del();if((e.ctrlKey||e.metaKey)&&k==='d'){e.preventDefault();duplicate()}if((e.ctrlKey||e.metaKey)&&k==='z'){e.preventDefault();e.shiftKey?redoFn():undo()}});

setTool('select');updateStats();toast('3D Modeler V3.26 připraven');