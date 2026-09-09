(()=>{
  function removeModeler(){
    document.getElementById('modeler-launcher-v325')?.remove();
  }
  function init(){removeModeler();setTimeout(removeModeler,300);setTimeout(removeModeler,1000)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();
