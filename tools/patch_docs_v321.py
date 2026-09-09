from pathlib import Path
import re

p=Path('index.html')
s=p.read_text(encoding='utf-8-sig')

# Keep the visible header version aligned with the actual release.
s=s.replace("if (version) version.textContent = 'V3.14s · SAFARI';","if (version) version.textContent = 'V3.21 · SAFARI';")
s=s.replace("if (version) version.textContent = 'V3.14s';","if (version) version.textContent = 'V3.21';")
s=re.sub(r'(<div class="app-version" id="app-version">)V[^<]+(</div>)',r'\1V3.21\2',s,count=1)

# Load the documentation upgrade once, after the existing norms/UI extension.
old='<script src="norms_ui_v315b.js?v=315b"></script>'
new='<script src="norms_ui_v315b.js?v=315b"></script>\n<script src="docs_upgrade_v321.js?v=321"></script>'
if 'docs_upgrade_v321.js' not in s:
    if old not in s: raise SystemExit('norms UI script tag not found')
    s=s.replace(old,new,1)

p.write_text(s,encoding='utf-8')

# Also align the extension version/changelog label.
ui=Path('norms_ui_v315b.js')
u=ui.read_text(encoding='utf-8-sig')
u=u.replace("const VERSION='V3.20';","const VERSION='V3.21';",1)
ui.write_text(u,encoding='utf-8')

print('V3.21 documentation patch applied')