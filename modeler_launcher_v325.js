(()=>{
  function addLauncher(){
    const menu=document.querySelector('.menu-app-row.beta')||document.querySelector('.menu-app-groups');
    if(!menu||document.getElementById('modeler-launcher-v325'))return;
    const b=document.createElement('div');b.id='modeler-launcher-v325';b.className='tile';b.tabIndex=0;b.setAttribute('role','button');
    b.innerHTML='<b>3D Modeler <small class="menu-status">BETA</small></b><span>Nový model od nuly nebo rychlá úprava STL/OBJ/GLB. Export a předání do 3D tisku.</span>';
    const go=()=>location.href='modeler/index.html';b.onclick=go;b.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();go()}};menu.appendChild(b);
  }
  function db(){return new Promise((res,rej)=>{const r=indexedDB.open('20-20-toolbox-transfer',1);r.onupgradeneeded=()=>{if(!r.result.objectStoreNames.contains('files'))r.result.createObjectStore('files')};r.onsuccess=()=>res(r.result);r.onerror=()=>rej(r.error)})}
  async function importToPrint(){
    const p=new URLSearchParams(location.search);if(p.get('tool')!=='3dprint'||p.get('import')!=='modeler')return;
    try{window.openTool?.('3dprint');const d=await db(),data=await new Promise((res,rej)=>{const tx=d.transaction('files','readonly'),r=tx.objectStore('files').get('modeler-to-print');r.onsuccess=()=>res(r.result);r.onerror=()=>rej(r.error)});if(!data?.blob)throw new Error('Přenesený model nebyl nalezen.');
      const file=new File([data.blob],data.name||'20-20-modeler.stl',{type:'model/stl'}),inputs=[...document.querySelectorAll('#tool-3dprint input[type=file]')];let target=inputs.find(x=>/stl|obj|3mf|model/i.test((x.accept||'')+' '+(x.id||'')+' '+(x.name||'')))||inputs[0];if(!target)throw new Error('V aplikaci 3D tisk nebyl nalezen vstup pro model.');const dt=new DataTransfer();dt.items.add(file);target.files=dt.files;target.dispatchEvent(new Event('change',{bubbles:true}));
      setTimeout(()=>history.replaceState({},'',location.pathname),300);setTimeout(()=>{const msg=document.createElement('div');msg.textContent='Model z 3D Modeleru byl předán do 3D tisku.';Object.assign(msg.style,{position:'fixed',left:'50%',bottom:'24px',transform:'translateX(-50%)',background:'#18181b',color:'#fff',padding:'9px 13px',borderRadius:'7px',fontSize:'11px',zIndex:9999});document.body.appendChild(msg);setTimeout(()=>msg.remove(),2200)},350);
    }catch(e){console.error(e);alert('Předání modelu do 3D tisku se nepodařilo: '+(e.message||e))}
  }
  function init(){addLauncher();setTimeout(addLauncher,500);setTimeout(importToPrint,120)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();