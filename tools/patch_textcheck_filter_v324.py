from pathlib import Path

idx=Path('index.html')
s=idx.read_text(encoding='utf-8')
script='<script src="docs_textcheck_filter_v324.js?v=324"></script>'
if script not in s:
    s=s.replace('</body>',script+'\n</body>')
# visible version and stale overrides
s=s.replace('id="app-version">V3.23<','id="app-version">V3.24<')
s=s.replace('id="app-version">V3.22<','id="app-version">V3.24<')
s=s.replace('id="app-version">V3.21<','id="app-version">V3.24<')
idx.write_text(s,encoding='utf-8')

for name in ['docs_upgrade_v321.js','docs_textcheck_web_v323.js']:
    p=Path(name)
    if not p.exists(): continue
    t=p.read_text(encoding='utf-8')
    t=t.replace("const APP_VERSION='V3.23'","const APP_VERSION='V3.24'")
    t=t.replace("const APP_VERSION='V3.21'","const APP_VERSION='V3.24'")
    p.write_text(t,encoding='utf-8')
