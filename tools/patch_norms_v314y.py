from pathlib import Path
import re

p=Path('index.html')
s=p.read_text(encoding='utf-8-sig')

# Visible app version. Bridge stays 3.14v.
s=s.replace('<div class="app-version" id="app-version">V3.14x</div>','<div class="app-version" id="app-version">V3.14y</div>',1)
if '<div class="app-version" id="app-version">V3.14y</div>' not in s:
    s,_=re.subn(r'(<div\b[^>]*id=["\']app-version["\'][^>]*>\s*)V3\.14[a-z](\s*</div>)',r'\1V3.14y\2',s,count=1,flags=re.I)

# The G-code header may keep its feature version, but the app shell should report y.
loader='''\n<script src="norms_data_v314y.js?v=314y"></script>\n<script src="norms_engine_v314y.js?v=314y"></script>\n'''
if 'norms_engine_v314y.js' not in s:
    if '</body>' not in s: raise SystemExit('body closing tag not found')
    s=s.replace('</body>',loader+'</body>',1)

if '<div class="app-version" id="app-version">V3.14y</div>' not in s:
    raise SystemExit('V3.14y visible version missing')
if 'norms_data_v314y.js?v=314y' not in s or 'norms_engine_v314y.js?v=314y' not in s:
    raise SystemExit('V3.14y script loader missing')
if 'id="tool-norms"' not in s:
    raise SystemExit('Existing norms tool missing')
if "openTool('norms')" not in s:
    raise SystemExit('Norms menu tile missing')

p.write_text(s,encoding='utf-8')
print('V3.14y norms + interior standards integration applied')
