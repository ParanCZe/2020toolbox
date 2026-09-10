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

loader='<script src="presentation_editor_v332.js?v=332"></script>'
anchor='<script src="sketchup_extension_button_v330.js?v=330"></script>'
if loader not in s and anchor in s:
    s=s.replace(anchor,anchor+'\n'+loader,1);changed=True

checks=[
    'window.getInfoBarNorthAngle?window.getInfoBarNorthAngle(pageNumber)',
    'window.__thumbRenderToken',
    'presentation_editor_v332.js?v=332'
]
missing=[x for x in checks if x not in s]
if missing:
    raise SystemExit('V3.32 patch incomplete: '+', '.join(missing))

if changed:
    p.write_text(s,encoding='utf-8')
    print('V3.32 presentation editor patch applied')
else:
    print('V3.32 patch already applied')
