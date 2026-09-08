from pathlib import Path

P = Path('index.html')
s = P.read_text(encoding='utf-8-sig')

# Visible app version only. Bridge remains 3.14v.
s = s.replace('<div class="app-version">V3.14v</div>', '<div class="app-version">V3.14w</div>', 1)

old_download = '''    const blob=new Blob([header+gcode],{type:'text/x-gcode'}),a=document.createElement('a'),ratio=String(document.getElementById('print3d-scale')?.value||1).replace(/[^0-9._-]/g,'');a.href=URL.createObjectURL(blob);a.download=f.name.replace(/\\.[^.]+$/,'')+`_MK3S_WINDOWS_REPAIR_1-${ratio}.gcode`;a.click();setTimeout(()=>URL.revokeObjectURL(a.href),2500);'''
new_download = '''    const ratio=String(document.getElementById('print3d-scale')?.value||1).replace(/[^0-9._-]/g,'');
    const downloadName=f.name.replace(/\\.[^.]+$/,'')+`_MK3S_WINDOWS_REPAIR_1-${ratio}.gcode`;
    open3DPrintGcodePreview(header+gcode,downloadName);'''
if old_download not in s:
    if 'open3DPrintGcodePreview(header+gcode,downloadName)' not in s:
        raise SystemExit('Direct G-code download anchor not found')
else:
    s = s.replace(old_download, new_download, 1)

s = s.replace(
    "    const header=`; 20-20-TOOLBOX V3.14s\\n; slicer_engine = LOCAL ${ver}",
    "    const header=`; 20-20-TOOLBOX V3.14w\\n; slicer_engine = LOCAL ${ver}",
    1,
)

s = s.replace(
    "    if(st)st.textContent='G-code vytvořen: Windows RepairAsync → PrusaSlicer.';",
    "    if(st)st.textContent='G-code vytvořen. Zkontroluj náhled a potom zvol Stáhnout G-code.';",
    1,
)
s = s.replace(
    "<b>Zkontroluj výsledný model v PrusaSlicer G-code Vieweru.</b>",
    "<b>Otevřen náhled G-code. Stažení je povolené až po úspěšném načtení vieweru.</b>",
    1,
)

marker = "document.addEventListener('DOMContentLoaded',()=>setTimeout(()=>check3DPrintPrusaBridge(true),700));"
if 'function open3DPrintGcodePreview(gcode,filename)' not in s:
    if marker not in s:
        raise SystemExit('DOMContentLoaded anchor not found')
    helper = r'''
let print3dGcodePreviewOverlay=null;
let print3dGcodePreviewPayload=null;
let print3dGcodePreviewOldOverflow='';
function close3DPrintGcodePreview(reason='cancel'){
  if(!print3dGcodePreviewOverlay)return;
  try{print3dGcodePreviewOverlay.remove()}catch{}
  print3dGcodePreviewOverlay=null;
  print3dGcodePreviewPayload=null;
  document.body.style.overflow=print3dGcodePreviewOldOverflow||'';
  const st=document.getElementById('st-3dprint');
  if(reason==='cancel'&&st)st.textContent='Stažení G-code zrušeno. Můžeš upravit nastavení a export spustit znovu.';
}
function open3DPrintGcodePreview(gcode,filename){
  close3DPrintGcodePreview('replace');
  print3dGcodePreviewPayload={gcode:String(gcode||''),filename:String(filename||'toolbox.gcode')};
  print3dGcodePreviewOldOverflow=document.body.style.overflow;
  document.body.style.overflow='hidden';
  const overlay=document.createElement('div');
  overlay.id='print3d-gcode-preview-overlay';
  overlay.setAttribute('role','dialog');
  overlay.setAttribute('aria-modal','true');
  overlay.setAttribute('aria-label','Kontrola G-code před stažením');
  Object.assign(overlay.style,{position:'fixed',inset:'0',zIndex:'50000',background:'rgba(0,0,0,.72)',padding:'18px',display:'flex',alignItems:'center',justifyContent:'center'});
  const frame=document.createElement('iframe');
  frame.id='print3d-gcode-preview-frame';
  frame.title='G-code Viewer – kontrola před stažením';
  frame.src='gcode_viewer_embedded.html?v=314w';
  frame.allow='fullscreen';
  Object.assign(frame.style,{width:'min(1500px,97vw)',height:'min(920px,95vh)',border:'1px solid #3a3f47',borderRadius:'14px',background:'#17191d',boxShadow:'0 24px 70px rgba(0,0,0,.45)'});
  frame.addEventListener('load',()=>{
    try{frame.contentWindow.postMessage({type:'toolbox-gcode-preview-load',...print3dGcodePreviewPayload},'*')}catch(e){console.error('G-code preview postMessage',e)}
  });
  overlay.appendChild(frame);
  overlay.addEventListener('mousedown',e=>{if(e.target===overlay)close3DPrintGcodePreview('cancel')});
  document.body.appendChild(overlay);
  print3dGcodePreviewOverlay=overlay;
}
window.addEventListener('message',e=>{
  const overlay=print3dGcodePreviewOverlay,frame=overlay?.querySelector('#print3d-gcode-preview-frame');
  if(!overlay||!frame||e.source!==frame.contentWindow)return;
  const d=e.data||{},st=document.getElementById('st-3dprint'),status=document.getElementById('print3d-cura-status');
  if(d.type==='toolbox-gcode-preview-ready'){
    if(st)st.textContent=`G-code náhled připraven: ${Number(d.layers||0)} vrstev. Zkontroluj ho a klikni „Stáhnout G-code“.`;
    return;
  }
  if(d.type==='toolbox-gcode-preview-error'){
    if(st)st.textContent='G-code viewer našel problém. Stažení zůstává zablokované.';
    if(status)status.innerHTML='<b>⚠ G-CODE VIEWER NENAČETL VÝSTUP</b><br>'+escapeHtml(d.message||'Neznámá chyba vieweru.')+'<br><b>Soubor se nestáhl.</b>';
    return;
  }
  if(d.type==='toolbox-gcode-preview-cancel'){
    close3DPrintGcodePreview('cancel');
    return;
  }
  if(d.type==='toolbox-gcode-preview-downloaded'){
    if(st)st.textContent='G-code zkontrolován a stažen.';
    if(status)status.innerHTML='<b>✓ G-CODE ZKONTROLOVÁN A STAŽEN</b><br>Viewer G-code úspěšně načetl před povolením stažení.';
    close3DPrintGcodePreview('download');
  }
});
window.addEventListener('keydown',e=>{if(e.key==='Escape'&&print3dGcodePreviewOverlay)close3DPrintGcodePreview('cancel')});

'''
    s = s.replace(marker, helper + marker, 1)

# Safety checks.
if '<div class="app-version">V3.14w</div>' not in s:
    raise SystemExit('V3.14w app version not applied')
if 'gcode_viewer_embedded.html?v=314w' not in s:
    raise SystemExit('G-code viewer iframe missing')
if 'open3DPrintGcodePreview(header+gcode,downloadName)' not in s:
    raise SystemExit('Export does not open preview')
if "a.download=f.name.replace" in s:
    raise SystemExit('Old direct download still present')

P.write_text(s, encoding='utf-8')
print('V3.14w G-code preview patch applied')
