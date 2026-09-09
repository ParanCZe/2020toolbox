from pathlib import Path

INDEX=Path('index.html')
UPGRADE=Path('docs_upgrade_v321.js')

# Fix the single version owner so its MutationObserver does not fight newer scripts.
if UPGRADE.exists():
    s=UPGRADE.read_text(encoding='utf-8-sig')
    s=s.replace("const APP_VERSION='V3.21';","const APP_VERSION='V3.23';",1)
    UPGRADE.write_text(s,encoding='utf-8')

s=INDEX.read_text(encoding='utf-8-sig')
# Static fallback shown before JS starts.
s=s.replace('id="app-version">V3.22<','id="app-version">V3.23<')
s=s.replace('id="app-version">V3.21<','id="app-version">V3.23<')
s=s.replace('id="app-version">V3.15b<','id="app-version">V3.23<')

# Load URL extension after the original text checker.
tag='<script src="docs_textcheck_web_v323.js?v=323"></script>'
if tag not in s:
    anchor='<script src="docs_textcheck_v322.js?v=322"></script>'
    if anchor in s:
        s=s.replace(anchor,anchor+'\n'+tag,1)
    else:
        s=s.replace('</body>',tag+'\n</body>',1)
INDEX.write_text(s,encoding='utf-8')
print('V3.23 patched')
