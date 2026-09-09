from pathlib import Path
import re

root=Path('.')
index=root/'index.html'
s=index.read_text(encoding='utf-8')
# Never inject inside template strings: only before the physical final body close.
script='<script src="modeler_launcher_v325.js?v=325"></script>'
s=re.sub(r'\s*<script src="modeler_launcher_v325\.js[^\"]*"></script>\s*','\n',s)
pos=s.rfind('</body>')
if pos<0:
    raise SystemExit('Final </body> not found')
s=s[:pos]+script+'\n'+s[pos:]
s=re.sub(r'(<div class="app-version" id="app-version">)V[^<]+(</div>)',r'\1V3.25\2',s,count=1)
if s.count('modeler_launcher_v325.js')!=1:
    raise SystemExit('Modeler launcher injection count is not exactly 1')
index.write_text(s,encoding='utf-8')

for name in ['docs_upgrade_v321.js','docs_textcheck_web_v323.js','docs_textcheck_filter_v324.js']:
    p=root/name
    if p.exists():
        t=p.read_text(encoding='utf-8')
        t=re.sub(r"const APP_VERSION='V[^']+';", "const APP_VERSION='V3.25';", t, count=1)
        p.write_text(t,encoding='utf-8')

p=root/'norms_ui_v315b.js'
if p.exists():
    t=p.read_text(encoding='utf-8')
    t=re.sub(r"const VERSION='V[^']+';", "const VERSION='V3.25';", t, count=1)
    p.write_text(t,encoding='utf-8')

print('V3.25 modeler integration patched safely')
