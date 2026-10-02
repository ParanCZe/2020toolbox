#!/usr/bin/env python3
"""Only RM TOOLS is prominent; retain all other SketchUp plugins in collapsed Legacy."""
from pathlib import Path
import re

root=Path(__file__).resolve().parent.parent
page=root/"index.html"
s=page.read_text(encoding="utf-8")
anchor='<div id="suplugins-grid" class="suplugins-grid"></div>'
assert s.count(anchor)==1
s=s.replace(anchor,anchor+'''
    <details id="suplugins-legacy" class="suplugins-legacy">
      <summary><span class="legacy-title">Legacy plugins</span><span id="legacy-plugin-count" class="legacy-count"></span><span class="legacy-hint">Starší samostatné pluginy</span></summary>
      <div id="suplugins-legacy-grid" class="suplugins-grid legacy-grid"></div>
    </details>
''',1)

css_marker='.suplugin-divider{grid-column:1/-1;height:1px;background:#c9cbd0;margin:2px 0 0}'
assert s.count(css_marker)==1
newcss="""
/* SketchUp downloads: single full-width RM TOOLS hero + folded legacy tools. */
#suplugins-grid{display:block;margin-top:21px}
#suplugins-grid>.suplugin-card.featured{width:100%;min-height:264px;border:2px solid #cfc24c;border-radius:18px;background:linear-gradient(135deg,#fffbe8,#fff 68%);box-shadow:0 16px 44px rgba(24,24,27,.12)}
#suplugins-grid>.suplugin-card.featured .suplugin-card-main{padding:32px 36px 24px;grid-template-columns:106px minmax(0,1fr);gap:25px}
#suplugins-grid>.suplugin-card.featured .suplugin-icon{width:106px;height:106px;border-radius:19px}
#suplugins-grid>.suplugin-card.featured .suplugin-icon svg{width:63px;height:63px}
#suplugins-grid>.suplugin-card.featured .suplugin-title{font-size:28px}
#suplugins-grid>.suplugin-card.featured .suplugin-desc{font-size:15px;max-width:920px}
#suplugins-grid>.suplugin-card.featured .suplugin-actions{padding:0 35px 30px;gap:12px}
#suplugins-grid>.suplugin-card.featured .suplugin-install{font-size:14px;padding:13px 22px}
#suplugins-grid>.suplugin-divider{display:none}
.suplugins-legacy{margin-top:27px;background:#f8f8fa;border:1px solid #d9dbdf;border-radius:13px;overflow:hidden}
.suplugins-legacy>summary{list-style:none;display:flex;align-items:center;flex-wrap:wrap;gap:12px;cursor:pointer;padding:19px 22px;color:#27272a}
.suplugins-legacy>summary::-webkit-details-marker{display:none}
.suplugins-legacy>summary:before{content:'▸';font-size:19px;color:#63666d;transition:transform .15s}
.suplugins-legacy[open]>summary:before{transform:rotate(90deg)}
.suplugins-legacy .legacy-title{font-size:17px;font-weight:800}
.suplugins-legacy .legacy-count{background:#e6e6e8;border-radius:20px;padding:4px 9px;font-size:11px}
.suplugins-legacy .legacy-hint{margin-left:auto;font-size:11px;color:#757981}
.suplugins-legacy[open]>summary{border-bottom:1px solid #d9dbdf}
.suplugins-legacy .legacy-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(310px,1fr));gap:14px;margin:0;padding:18px}
@media(max-width:650px){
 #suplugins-grid>.suplugin-card.featured .suplugin-card-main{grid-template-columns:65px minmax(0,1fr);padding:23px 18px 17px;gap:14px}
 #suplugins-grid>.suplugin-card.featured .suplugin-icon{width:65px;height:65px}
 #suplugins-grid>.suplugin-card.featured .suplugin-icon svg{width:38px;height:38px}
 #suplugins-grid>.suplugin-card.featured .suplugin-title{font-size:21px}
 #suplugins-grid>.suplugin-card.featured .suplugin-actions{padding:0 18px 23px}
}
"""
s=s.replace(css_marker,css_marker+"\n"+newcss,1)

start=s.index("function renderSketchUpPlugins(){")
end=s.index("function toggleSuPluginHistory(",start)
old=s[start:end]
body=old[old.index("    const latest="):old.index("  }).join('');")]
assert 'suplugin-state-' in body and 'installSuPlugin' in body
new="""function renderSuPluginCard(p){
"""+body+"""}
function renderSketchUpPlugins(){
  const main=document.getElementById('suplugins-grid');
  const legacy=document.getElementById('suplugins-legacy-grid');
  if(!main||!legacy)return;
  const current=SU_PLUGIN_CATALOG.filter(p=>p.id==='rm-tools-suite');
  const archived=SU_PLUGIN_CATALOG.filter(p=>p.id!=='rm-tools-suite');
  main.innerHTML=current.map(renderSuPluginCard).join('');
  legacy.innerHTML=archived.map(renderSuPluginCard).join('');
  const counter=document.getElementById('legacy-plugin-count');
  if(counter)counter.textContent=archived.length+' pluginů';
  refreshSuPluginVersions();
}
"""
s=s[:start]+new+s[end:]

cat=s.index("const SU_PLUGIN_CATALOG = [")
idx=s.index("id:'rm-tools-suite'",cat)
left=s.rfind("{",cat,idx)
depth=0
quote=None
escaped=False
right=None
for pos in range(left,len(s)):
    char=s[pos]
    if quote:
        if escaped:escaped=False
        elif char=="\\":escaped=True
        elif char==quote:quote=None
    elif char in ("'",'"',chr(96)):quote=char
    elif char=="{":depth+=1
    elif char=="}":
        depth-=1
        if depth==0:
            right=pos+1
            break
assert right is not None
block=s[left:right]
assert "current:'2.0.4.6'" in block
block=block.replace("current:'2.0.4.6'","current:'2.0.4.7'",1)
block,n=re.subn(r"description:'[^']*'",
    "description:'MODEL LIBRARY · 2D STROMY A KEŘE (Meye) · CHECKER · LIVE Mirror · Knihovna materiálů · Agent + Bridge'",
    block,count=1)
assert n==1
block,n=re.subn(r"meta:'[^']*'",
    "meta:'v2.0.4.7: online katalog Meye se stromovými cutouty. Plné PNG se stáhne až při vložení pomocí +.'",
    block,count=1)
assert n==1
file="20-20_RM_TOOLS_v2.0.4.7.rbz"
size=(root/"SketchUpPlugins"/file).stat().st_size
entry='{"version":"2.0.4.7","file":"'+file+'","size":'+str(size)+',"repo_file":"SketchUpPlugins/'+file+'"}'
assert '"version":"2.0.4.7"' not in block
opening=block.index("[",block.index("versions:["))
cursor=opening+1
balance=1
while balance:
    if block[cursor]=="[":balance+=1
    elif block[cursor]=="]":balance-=1
    cursor+=1
ending=cursor-1
entries=block[opening+1:ending].rstrip()
if entries and not entries.endswith(","):entries+=","
entries+="\n              "+entry+"\n            "
block=block[:opening+1]+entries+block[ending:]
s=s[:left]+block+s[right:]
assert "let suBridgeActiveUrl=null;" in s
assert "const status=await ensureSuBridge(true);" in s
assert "current:'2.0.4.7'" in s
assert s.count('<details id="suplugins-legacy"')==1
assert s.count('function renderSketchUpPlugins()')==1
page.write_text(s,encoding="utf-8")
print("PASS: big RM TOOLS 2.0.4.7 primary installer")
print("PASS: all other plugin releases retained in collapsed Legacy plugins")
print("PASS: existing cached web Bridge preserved")
