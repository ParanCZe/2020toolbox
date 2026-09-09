from pathlib import Path

p=Path('index.html')
s=p.read_text(encoding='utf-8-sig')
tag='<script src="sketchup_extension_button_v330.js?v=330"></script>'
if tag not in s:
    i=s.lower().rfind('</body>')
    if i<0:
        raise SystemExit('final </body> not found')
    s=s[:i]+tag+'\n'+s[i:]
    p.write_text(s,encoding='utf-8',newline='\n')
print('V3.30 SketchUp extension download loader ready')
