from pathlib import Path
import re

p=Path('index.html')
s=p.read_text(encoding='utf-8-sig')

# Keep visible version on current build and remove legacy project-storage overwrites.
s=re.sub(r'(<div class="app-version" id="app-version">)V[^<]+(</div>)',r'\1V3.22\2',s,count=1)
s=s.replace("if (version) version.textContent = 'V3.14s · SAFARI';","if (version) version.textContent = 'V3.22';")
s=s.replace("if (version) version.textContent = 'V3.14s';","if (version) version.textContent = 'V3.22';")
s=s.replace("if (version) version.textContent = 'V3.21';","if (version) version.textContent = 'V3.22';")

# Cache-bust docs upgrade if present.
s=s.replace('docs_upgrade_v321.js?v=321','docs_upgrade_v321.js?v=322')

# Load the new semantic text checker once, after docs upgrade when possible.
script='<script src="docs_textcheck_v322.js?v=322"></script>'
if script not in s:
    anchor='<script src="docs_upgrade_v321.js?v=322"></script>'
    if anchor in s:
        s=s.replace(anchor,anchor+'\n'+script,1)
    else:
        anchor='<script src="norms_ui_v315b.js?v=315b"></script>'
        if anchor in s:
            s=s.replace(anchor,script+'\n'+anchor,1)
        else:
            s=s.replace('</body>',script+'\n</body>',1)

p.write_text(s,encoding='utf-8')
print('V3.22 text checker loader patched')