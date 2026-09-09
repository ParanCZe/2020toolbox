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
const grid=new THREE.GridHelper(20000,100,0x999999,0xc8c8c8);scene.add(grid);
const axes=new THREE.AxesHelper(1200);axes.position.y=2;scene.add(axes);
scene.add(new THREE.HemisphereLight(0xffffff,0x777777,2.4));const sun=new THREE.DirectionalLight(0xffffff,2.2);sun.position.set(6000,9000,5000);sun.castShadow=true;scene.add(sun);
const ray=new THREE.Raycaster(),pointer=new THREE.Vector2();let selected=null,history=[],redo=[],restoring=false,toastTimer=null;

function toast(t){const el=$('toast');el.textContent=t;el.classList.add('show');clearTimeout(toastTimer);toastTimer=setTimeout(()=>el.classList.remove('show'),1700)}
function resize(){const w=viewport.clientWidth,h=viewport.clientHeight;renderer.setSize(w,h,false);camera.aspect=w/h;camera.updateProjectionMatrix()}addEventListener('resize',resize);resize();
function render(){orbit.update();renderer.render(scene,camera);requestAnimationFrame(render)}render();
function material(color=0xc9c9c9){return new THREE.MeshStandardMaterial({color,roughness:.72,metalness:.04,side:THREE.DoubleSide})}
function addObject(obj,name='Objekt'){pushHistory();obj.name=name;obj.traverse?.(o=>{if(o.isMesh){o.castShadow=true;o.receiveShadow=true;if(!o.material)o.material=material()}});work.add(obj);select(obj);updateStats()}
function addPrimitive(type){let g,n;if(type==='box'){g=new THREE.BoxGeometry(1000,1000,1000);n='Kvádr'}if(type==='cylinder'){g=new THREE.CylinderGeometry(500,500,1000,48);n='Válec'}if(type==='sphere'){g=new THREE.SphereGeometry(500,40,24);n='Koule'}if(type==='plane'){g=new THREE.BoxGeometry(1200,100,1200);n='Deska'}const m=new THREE.Mesh(g,material());m.position.y=(type==='plane'?50:500);addObject(m,n)}
function selectableRoot(o){while(o&&o.parent&&o.parent!==work)o=o.parent;return o?.parent===work?o:null}
renderer.domElement.addEventListener('pointerdown',e=>{if(transform.dragging||e.button!==0)return;const r=renderer.domElement.getBoundingClientRect();pointer.x=((e.clientX-r.left)/r.width)*2-1;pointer.y=-((e.clientY-r.top)/r.height)*2+1;ray.setFromCamera(pointer,camera);const hits=ray.intersectObjects(work.children,true);if(hits.length)select(selectableRoot(hits[0].object));else select(null)});
function select(o){selected=o;transform.detach();if(o)transform.attach(o);syncPanel()}
function localDims(o){const box=new THREE.Box3().setFromObject(o);const s=new THREE.Vector3();box.getSize(s);return s}
function syncPanel(){const p=$('objectPanel'),no=$('noSelection');p.hidden=!selected;no.hidden=!!selected;if(!selected)return;const d=localDims(selected);$('objName').value=selected.name||'Objekt';$('dimX').value=d.x.toFixed(1);$('dimY').value=d.y.toFixed(1);$('dimZ').value=d.z.toFixed(1);$('posX').value=selected.position.x.toFixed(1);$('posY').value=selected.position.y.toFixed(1);$('posZ').value=selected.position.z.toFixed(1);$('rotX').value=THREE.MathUtils.radToDeg(selected.rotation.x).toFixed(1);$('rotY').value=THREE.MathUtils.radToDeg(selected.rotation.y).toFixed(1);$('rotZ').value=THREE.MathUtils.radToDeg(selected.rotation.z).toFixed(1);let mesh=null;selected.traverse?.(o=>{if(!mesh&&o.isMesh)mesh=o});if(selected.isMesh)mesh=selected;if(mesh?.material?.color)$('objColor').value='#'+mesh.material.color.getHexString()}
function pushHistory(){if(restoring)return;history.push(work.clone(true));if(history.length>30)history.shift();redo=[]}
function restore(snapshot){restoring=true;transform.detach();work.clear();for(const c of snapshot.children)work.add(c.clone(true));selected=null;syncPanel();updateStats();restoring=false}
function undo(){if(!history.length)return;redo.push(work.clone(true));restore(history.pop())}function redoFn(){if(!redo.length)return;history.push(work.clone(true));restore(redo.pop())}
transform.addEventListener('dragging-changed',e=>orbit.enabled=!e.value);transform.addEventListener('mouseDown',pushHistory);transform.addEventListener('objectChange',()=>{syncPanel();updateStats()});
function setMode(mode){transform.setMode(mode);document.querySelectorAll('[data-mode]').forEach(b=>b.classList.toggle('active',b.dataset.mode===mode))}
function duplicate(){if(!selected)return;pushHistory();const c=selected.clone(true);c.position.x+=150;c.position.z+=150;c.name=(selected.name||'Objekt')+' kopie';work.add(c);select(c);updateStats()}
function del(){if(!selected)return;pushHistory();work.remove(selected);select(null);updateStats()}
function newModel(){if(work.children.length&&!confirm('Založit nový model a zahodit aktuální scénu?'))return;pushHistory();work.clear();select(null);updateStats();toast('Nový prázdný model')}
function fitObject(o){const b=new THREE.Box3().setFromObject(o),s=new THREE.Vector3(),c=new THREE.Vector3();b.getSize(s);b.getCenter(c);const max=Math.max(s.x,s.y,s.z,1000),dist=max*2.3;camera.position.set(c.x+dist,c.y+dist*.8,c.z+dist);orbit.target.copy(c);orbit.update()}
async function openFile(file){if(!file)return;const ext=file.name.split('.').pop().toLowerCase(),buf=await file.arrayBuffer();try{let obj;if(ext==='stl'){const geo=new STLLoader().parse(buf);obj=new THREE.Mesh(geo,material());obj.name=file.name}else if(ext==='obj'){obj=new OBJLoader().parse(new TextDecoder().decode(buf));obj.name=file.name;obj.traverse(o=>{if(o.isMesh&&!o.material)o.material=material()})}else if(ext==='glb'||ext==='gltf'){const loader=new GLTFLoader();const gltf=await new Promise((res,rej)=>loader.parse(buf,'',res,rej));obj=gltf.scene;obj.name=file.name}else throw new Error('Nepodporovaný formát');addObject(obj,file.name);fitObject(obj);toast('Model načten')}catch(e){alert('Model se nepodařilo načíst: '+(e.message||e))}}
function exportStlBlob(){const ex=new STLExporter(),data=ex.parse(work,{binary:true});return new Blob([data],{type:'model/stl'})}
function download(){if(!work.children.length){toast('Model je prázdný');return}const blob=exportStlBlob(),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='20-20-model.stl';a.click();setTimeout(()=>URL.revokeObjectURL(url),1500)}
function openDb(){return new Promise((res,rej)=>{const r=indexedDB.open('20-20-toolbox-transfer',1);r.onupgradeneeded=()=>r.result.createObjectStore('files');r.onsuccess=()=>res(r.result);r.onerror=()=>rej(r.error)})}
async function sendPrint(){if(!work.children.length){toast('Model je prázdný');return}try{const db=await openDb(),blob=exportStlBlob();await new Promise((res,rej)=>{const tx=db.transaction('files','readwrite');tx.objectStore('files').put({blob,name:'20-20-modeler.stl',time:Date.now()},'modeler-to-print');tx.oncomplete=res;tx.onerror=()=>rej(tx.error)});location.href='../index.html?tool=3dprint&import=modeler'}catch(e){alert('Předání do 3D tisku selhalo: '+(e.message||e))}}
function updateStats(){let meshes=0,tris=0;work.traverse(o=>{if(o.isMesh){meshes++;const g=o.geometry;tris+=g.index?g.index.count/3:(g.attributes.position?.count||0)/3}});$('stats').textContent=`${work.children.length} objektů · ${meshes} meshů · ${Math.round(tris).toLocaleString('cs-CZ')} trojúhelníků`}
function setView(v){const c=selected?new THREE.Box3().setFromObject(selected).getCenter(new THREE.Vector3()):new THREE.Vector3(0,500,0),d=5000;if(v==='top')camera.position.set(c.x,c.y+d,c.z+.01);if(v==='front')camera.position.set(c.x,c.y,c.z+d);if(v==='right')camera.position.set(c.x+d,c.y,c.z);if(v==='iso')camera.position.set(c.x+d,c.y+d*.75,c.z+d);orbit.target.copy(c);camera.lookAt(c);orbit.update()}

document.querySelectorAll('[data-add]').forEach(b=>b.onclick=()=>addPrimitive(b.dataset.add));document.querySelectorAll('[data-mode]').forEach(b=>b.onclick=()=>setMode(b.dataset.mode));document.querySelectorAll('[data-view]').forEach(b=>b.onclick=()=>setView(b.dataset.view));
$('btnDuplicate').onclick=duplicate;$('btnDelete').onclick=del;$('btnUndo').onclick=undo;$('btnRedo').onclick=redoFn;$('btnNew').onclick=newModel;$('btnOpen').onclick=()=>$('fileOpen').click();$('fileOpen').onchange=()=>openFile($('fileOpen').files?.[0]);$('btnDownload').onclick=download;$('btnPrint').onclick=sendPrint;
$('gridToggle').onchange=e=>grid.visible=e.target.checked;$('snapToggle').onchange=e=>{transform.setTranslationSnap(e.target.checked?10:null)};
$('objName').onchange=e=>{if(selected){pushHistory();selected.name=e.target.value||'Objekt';syncPanel()}};$('objColor').oninput=e=>{if(!selected)return;selected.traverse(o=>{if(o.isMesh&&o.material?.color)o.material.color.set(e.target.value)});if(selected.isMesh&&selected.material?.color)selected.material.color.set(e.target.value)};
['posX','posY','posZ'].forEach((id,i)=>$(id).onchange=e=>{if(!selected)return;pushHistory();selected.position.setComponent(i,Number(e.target.value)||0);syncPanel()});
['rotX','rotY','rotZ'].forEach((id,i)=>$(id).onchange=e=>{if(!selected)return;pushHistory();selected.rotation.setComponent(i,THREE.MathUtils.degToRad(Number(e.target.value)||0));syncPanel()});
['dimX','dimY','dimZ'].forEach((id,i)=>$(id).onchange=e=>{if(!selected)return;const cur=localDims(selected).getComponent(i),target=Math.max(.001,Number(e.target.value)||cur);if(cur>0){pushHistory();selected.scale.setComponent(i,selected.scale.getComponent(i)*(target/cur));syncPanel()}});
addEventListener('keydown',e=>{if(/INPUT|TEXTAREA|SELECT/.test(document.activeElement?.tagName))return;if(e.key==='w'||e.key==='W')setMode('translate');if(e.key==='e'||e.key==='E')setMode('rotate');if(e.key==='r'||e.key==='R')setMode('scale');if(e.key==='Delete')del();if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='d'){e.preventDefault();duplicate()}if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='z'){e.preventDefault();e.shiftKey?redoFn():undo()}});
updateStats();toast('3D Modeler připraven');