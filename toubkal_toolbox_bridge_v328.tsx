import React from 'react';
import * as THREE from 'three';
import { STLExporter } from 'three/examples/jsm/exporters/STLExporter.js';

function collectVisibleCadMeshes(): THREE.Group {
  const scene=(window as any).__TOOLBOX_CAD_SCENE as THREE.Scene|undefined;
  if(!scene) throw new Error('3D scéna ještě není připravená.');
  scene.updateMatrixWorld(true);
  const group=new THREE.Group();
  const seen=new Set<string>();
  scene.traverse((o:any)=>{
    if(!o?.isMesh || o.visible===false) return;
    const id=String(o.userData?.cadNodeId||'');
    if(!id || seen.has(id)) return;
    seen.add(id);
    const clone=new THREE.Mesh(o.geometry.clone());
    clone.matrixAutoUpdate=false;
    clone.matrix.copy(o.matrixWorld);
    group.add(clone);
  });
  if(!group.children.length) throw new Error('V modelu není žádné viditelné 3D těleso.');
  return group;
}

function makeStlBlob(): Blob {
  const group=collectVisibleCadMeshes();
  const exporter=new STLExporter();
  const data=exporter.parse(group,{binary:true}) as DataView;
  group.traverse((o:any)=>o.geometry?.dispose?.());
  return new Blob([data],{type:'model/stl'});
}

function downloadBlob(blob:Blob,name:string){
  const url=URL.createObjectURL(blob),a=document.createElement('a');
  a.href=url;a.download=name;document.body.appendChild(a);a.click();a.remove();
  setTimeout(()=>URL.revokeObjectURL(url),1500);
}

function openDb():Promise<IDBDatabase>{
  return new Promise((resolve,reject)=>{
    const r=indexedDB.open('20-20-toolbox-transfer',1);
    r.onupgradeneeded=()=>{if(!r.result.objectStoreNames.contains('files'))r.result.createObjectStore('files')};
    r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error);
  });
}

async function sendToPrint(){
  const blob=makeStlBlob();
  const db=await openDb();
  await new Promise<void>((resolve,reject)=>{
    const tx=db.transaction('files','readwrite');
    tx.objectStore('files').put({blob,name:'20-20-toubkal-model.stl',time:Date.now()},'modeler-to-print');
    tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error);
  });
  location.href='../index.html?tool=3dprint&import=modeler';
}

const Btn:React.FC<React.ButtonHTMLAttributes<HTMLButtonElement>>=p=><button {...p} style={{height:24,border:'1px solid #77734b',borderRadius:5,padding:'0 9px',background:p.className==='primary'?'#18181b':'#fffef0',color:p.className==='primary'?'#fff':'#18181b',fontSize:10,cursor:'pointer',whiteSpace:'nowrap'}}/>;

export const ToolboxBridge:React.FC=()=>{
  const run=(fn:()=>void|Promise<void>)=>Promise.resolve().then(fn).catch(e=>alert(e?.message||String(e)));
  return <div style={{display:'flex',alignItems:'center',gap:6,padding:'0 8px',height:'100%',background:'#f7f197',borderLeft:'1px solid #d8d06d'}}>
    <span style={{fontSize:10,fontWeight:700,letterSpacing:.6,color:'#18181b',marginRight:2}}>20-20</span>
    <Btn onClick={()=>location.href='../index.html'}>← TOOLBOX</Btn>
    <Btn onClick={()=>run(()=>downloadBlob(makeStlBlob(),'20-20-model.stl'))}>STÁHNOUT STL</Btn>
    <Btn className="primary" onClick={()=>run(sendToPrint)}>POSLAT DO 3D TISKU</Btn>
  </div>;
};
