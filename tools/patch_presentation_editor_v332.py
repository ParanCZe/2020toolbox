from pathlib import Path
p=Path('index.html')
s=p.read_text(encoding='utf-8')
changed=False

old="if(cfg.rightMode==='scale') drawScaleNorthCanvas(ctx,width,y,barHeight,scale,cfg.scale,Number(document.getElementById('northAngle').value)||0,cfg.scaleStyle||'ticks',document.getElementById('northStyle').value||'circle');"
new="if(cfg.rightMode==='scale') drawScaleNorthCanvas(ctx,width,y,barHeight,scale,cfg.scale,(window.getInfoBarNorthAngle?window.getInfoBarNorthAngle(pageNumber):(Number(document.getElementById('northAngle').value)||0)),cfg.scaleStyle||'ticks',document.getElementById('northStyle').value||'circle');"
if old in s:
    s=s.replace(old,new,1);changed=True

old2="const arrowAngle=(Number(document.getElementById('northAngle').value)||0)*Math.PI/180;"
new2="const arrowAngle=(window.getInfoBarNorthAngle?window.getInfoBarNorthAngle(pageNumber):(Number(document.getElementById('northAngle').value)||0))*Math.PI/180;"
if old2 in s:
    s=s.replace(old2,new2,1);changed=True

needle="async function renderThumbnails() {\n  const sidebar = document.getElementById('thumbs-sidebar');"
repl="async function renderThumbnails() {\n  const renderToken = (window.__thumbRenderToken = (window.__thumbRenderToken || 0) + 1);\n  const sidebar = document.getElementById('thumbs-sidebar');"
if needle in s:
    s=s.replace(needle,repl,1);changed=True

needle2="    sidebar.appendChild(wrap);\n  }\n}\n\nfunction highlightActiveThumb()"
repl2="    if (renderToken !== window.__thumbRenderToken) return;\n    sidebar.appendChild(wrap);\n  }\n}\n\nfunction highlightActiveThumb()"
if needle2 in s:
    s=s.replace(needle2,repl2,1);changed=True

if not changed:
    print('V3.32 patch already applied or anchors not found')
else:
    p.write_text(s,encoding='utf-8')
    print('V3.32 presentation editor patch applied')
