from pathlib import Path
import re

p=Path('index.html')
s=p.read_text(encoding='utf-8-sig')

# Visible app version.
s=re.sub(r'(<div class="app-version" id="app-version">)V3\.\d+[a-z](</div>)',r'\1V3.15b\2',s,count=1)

# Update existing changelog modal version text if present.
s=re.sub(r'(<span class="whatsnew-ver">)V3\.\d+[a-z](</span>)',r'\1V3.15b\2',s,count=1)

# Load V3.15b behavior after existing norms engine so it can enhance/override UI safely.
loader='\n<script src="norms_ui_v315b.js?v=315b"></script>\n'
if 'norms_ui_v315b.js?v=315b' not in s:
    pos=s.rfind('</body>')
    if pos < 0: raise SystemExit('final </body> not found')
    s=s[:pos]+loader+s[pos:]

# Cache-bust current norms database/engine, preserving filenames.
s=s.replace('norms_data_v314y.js?v=314z','norms_data_v314y.js?v=315b')
s=s.replace('norms_engine_v314y.js?v=314z','norms_engine_v314y.js?v=315b')
s=s.replace('norms_data_v314y.js?v=314y','norms_data_v314y.js?v=315b')
s=s.replace('norms_engine_v314y.js?v=314y','norms_engine_v314y.js?v=315b')

assert '<div class="app-version" id="app-version">V3.15b</div>' in s
assert 'norms_ui_v315b.js?v=315b' in s
assert s.count('norms_ui_v315b.js?v=315b') == 1

p.write_text(s,encoding='utf-8')
print('V3.15b norms UI patch applied')
