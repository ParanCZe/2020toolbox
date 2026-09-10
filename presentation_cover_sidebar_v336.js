(()=>{
  const SID='presentation-cover-sidebar-v336';
  function css(){if(document.getElementById(SID+'-style'))return;const s=document.createElement('style');s.id=SID+'-style';s.textContent=`
    #${SID}{display:none;flex:0 0 205px;width:205px;min-width:205px;height:100%;min-height:0;overflow-y:auto;overflow-x:hidden;background:#fff;border:1px solid #d4d4d8;border-radius:8px;padding:10px;align-self:stretch}
    #${SID}.active{display:block}
    #${SID} #cover-image-editor-tools{display:flex!important;flex-direction:column!important;align-items:stretch!important;gap:9px!important;width:100%!important;max-height:none!important;overflow:visible!important;padding:0!important;margin:0!important;border:0!important;background:transparent!important}
    #${SID} #cover-image-editor-tools>b{display:block;font-size:11px!important;margin:0 0 2px!important;line-height:1.25}
    #${SID} .cover-image-settings{display:flex!important;flex-direction:column!important;align-items:stretch!important;gap:10px!important;width:100%!important;min-width:0!important;flex:0 0 auto!important}
    #${SID} .cover-image-settings label{display:flex!important;flex-direction:column!important;align-items:stretch!important;gap:4px!important;width:100%!important;font-size:10px!important;line-height:1.2!important;white-space:normal!important;color:#3f3f46}
    #${SID} .cover-image-settings input[type="range"]{display:block!important;width:100%!important;min-width:0!important;margin:0!important;padding:0!important;height:18px!important}
    #${SID} .cover-image-settings select,#${SID} .cover-image-settings input:not([type="range"]){width:100%!important;min-width:0!important}
    @media(max-width:1100px){#${SID}{flex-basis:175px;width:175px;min-width:175px;padding:8px}}
  `;document.head.appendChild(s)}
  function ensure(){
    const body=document.getElementById('preview-body'),main=document.getElementById('preview-main');if(!body||!main)return null;
    let side=document.getElementById(SID);if(!side){side=document.createElement('aside');side.id=SID;body.insertBefore(side,main)}
    const tools=document.getElementById('cover-image-editor-tools');if(tools&&tools.parentElement!==side)side.appendChild(tools);
    return side;
  }
  function sync(){
    const side=ensure(),tools=document.getElementById('cover-image-editor-tools');if(!side||!tools)return;
    const visible=tools.style.display!=='none'&&getComputedStyle(tools).display!=='none';
    side.classList.toggle('active',visible);
    if(visible){tools.style.display='flex';}else{side.style.display='';}
    setTimeout(()=>window.fitPresentationCanvas?.(),0);
  }
  function watch(){const tools=document.getElementById('cover-image-editor-tools');if(!tools)return;new MutationObserver(sync).observe(tools,{attributes:true,attributeFilter:['style','class']})}
  function init(){css();ensure();watch();sync();setTimeout(()=>{ensure();watch();sync()},400);setTimeout(()=>{ensure();watch();sync()},1400);document.addEventListener('presentation-canvas-fitted',sync)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();