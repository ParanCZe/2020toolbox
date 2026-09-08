from pathlib import Path
import re

P=Path('index.html')
s=P.read_text(encoding='utf-8-sig')

# 1) HOTFIX: V3.14y omylem vlozila externi skripty dovnitr template stringu
# pro tisk Seznamu vykresu. HTML parser tim ukoncil hlavni <script> a zbytek JS
# se vykresloval jako text. Obnovime puvodni template string.
bad='''<\\/script>\n<script src="norms_data_v314y.js?v=314y"></script>\n<script src="norms_engine_v314y.js?v=314y"></script>\n</body></html>`);w.document.close();'''
good='''<\\/script></body></html>`);w.document.close();'''
if bad in s:
    s=s.replace(bad,good,1)

# Pokud je rozbita varianta s realnym </script>, oprav i ji konzervativne.
s=s.replace('''<\\/script>\r\n<script src="norms_data_v314y.js?v=314y"></script>\r\n<script src="norms_engine_v314y.js?v=314y"></script>\r\n</body></html>`);w.document.close();''',good,1)

# 2) Verze aplikace.
s=re.sub(r'(<div class="app-version" id="app-version">)V3\.14[a-z](</div>)',r'\1V3.14z\2',s,count=1)
s=s.replace('; 20-20-TOOLBOX V3.14y\\n;','; 20-20-TOOLBOX V3.14z\\n;',1)

# 3) Externi databaze/engine norem patri do HLAVNIHO dokumentu, pred posledni </body>.
main_scripts='''\n<script src="norms_data_v314y.js?v=314z"></script>\n<script src="norms_engine_v314y.js?v=314z"></script>\n'''
# Odstran jen pripadne samostatne kopie mimo nas cil a vloz jednu pred finalni body.
# (Po oprave template stringu uz tam zadne byt nemaji.)
if 'norms_data_v314y.js?v=314z' not in s:
    pos=s.rfind('</body>')
    if pos<0: raise SystemExit('Final </body> not found')
    s=s[:pos]+main_scripts+s[pos:]

# 4) Modal "Co je noveho" - ukaze se jednou pro kazdou verzi v danem prohlizeci.
css='''\n/* CO JE NOVEHO — V3.14z */\n#toolbox-whatsnew{display:none;position:fixed;inset:0;z-index:90000;background:rgba(0,0,0,.48);align-items:center;justify-content:center;padding:20px}\n#toolbox-whatsnew.active{display:flex}\n.whatsnew-box{width:min(620px,94vw);max-height:86vh;overflow:auto;background:#fff;border:1px solid var(--border);border-radius:14px;box-shadow:0 24px 70px rgba(0,0,0,.24)}\n.whatsnew-head{display:flex;align-items:center;justify-content:space-between;gap:16px;padding:16px 18px;background:#f7f197;border-bottom:1px solid #e2db7d}\n.whatsnew-head b{font:normal 16px 'Antarctican Mono',monospace}.whatsnew-ver{font:11px 'Antarctican Mono',monospace;color:#52525b}\n.whatsnew-body{padding:18px}.whatsnew-item{padding:12px 0;border-bottom:1px solid var(--border)}.whatsnew-item:last-child{border-bottom:0}.whatsnew-item strong{display:block;font-size:13px;margin-bottom:4px}.whatsnew-item span{font-size:11px;line-height:1.5;color:var(--muted)}\n.whatsnew-actions{padding:0 18px 18px;display:flex;justify-content:flex-end}.whatsnew-actions button{min-width:120px}\n'''
if '/* CO JE NOVEHO — V3.14z */' not in s:
    p=s.find('</style>')
    if p<0: raise SystemExit('</style> not found')
    s=s[:p]+css+s[p:]

modal='''\n<div id="toolbox-whatsnew" role="dialog" aria-modal="true" aria-labelledby="toolbox-whatsnew-title">\n  <div class="whatsnew-box">\n    <div class="whatsnew-head"><b id="toolbox-whatsnew-title">Co je nového</b><span class="whatsnew-ver">V3.14z</span></div>\n    <div class="whatsnew-body">\n      <div class="whatsnew-item"><strong>Normy — velké rozšíření databáze</strong><span>Normy jsou nově postavené jako prohledávatelná projektantská databáze s kategoriemi, odkazy na zdroje a rychlým skokem na konkrétní požadavek.</span></div>\n      <div class="whatsnew-item"><strong>Nová aplikace Interiérové standardy</strong><span>Rychlé hledání ergonomie, rozměrů nábytku, odstupů, výšek polic, koupelen, kuchyní a dalších běžných návrhových hodnot.</span></div>\n      <div class="whatsnew-item"><strong>3D tisk — kontrola G-code před stažením</strong><span>Po slicingu se nejdřív otevře G-code Viewer. Soubor stáhneš až po vizuální kontrole.</span></div>\n      <div class="whatsnew-item"><strong>Opravená chyba hlavního rozhraní</strong><span>Opraveno vykreslení JavaScriptu jako textu a nefunkční tlačítka po předchozí aktualizaci.</span></div>\n    </div>\n    <div class="whatsnew-actions"><button class="action" type="button" onclick="closeToolboxWhatsNew()">Rozumím</button></div>\n  </div>\n</div>\n'''
if 'id="toolbox-whatsnew"' not in s:
    body=s.find('<body>')
    if body<0: raise SystemExit('<body> not found')
    body_end=body+len('<body>')
    s=s[:body_end]+modal+s[body_end:]

js='''\n<script>\n(function(){\n  const VERSION='V3.14z', KEY='20-20-toolbox-whatsnew-seen';\n  window.closeToolboxWhatsNew=function(){\n    const el=document.getElementById('toolbox-whatsnew');\n    if(el)el.classList.remove('active');\n    try{localStorage.setItem(KEY,VERSION)}catch(e){}\n  };\n  function show(){\n    let seen=''; try{seen=localStorage.getItem(KEY)||''}catch(e){}\n    if(seen===VERSION)return;\n    const el=document.getElementById('toolbox-whatsnew');\n    if(el)el.classList.add('active');\n  }\n  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(show,220)); else setTimeout(show,220);\n})();\n</script>\n'''
if "const VERSION='V3.14z', KEY='20-20-toolbox-whatsnew-seen'" not in s:
    pos=s.rfind('</body>')
    s=s[:pos]+js+s[pos:]

# Safety checks: externi scripts nesmi byt uvnitr print template a zakladni JS nesmi byt vystaven jako text.
if bad in s: raise SystemExit('Broken script insertion still present')
if '<div class="app-version" id="app-version">V3.14z</div>' not in s: raise SystemExit('Version not updated')
if s.count('norms_data_v314y.js?v=314z') != 1: raise SystemExit('Norm data script count != 1')
if s.count('id="toolbox-whatsnew"') != 1: raise SystemExit('Whats new modal count != 1')

P.write_text(s,encoding='utf-8')
print('V3.14z hotfix + changelog applied')
