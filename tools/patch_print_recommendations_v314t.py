from pathlib import Path
import re

p = Path('index.html')
h = p.read_text(encoding='utf-8-sig')

# Web/UI release only. Bridge remains 3.14s.
h = h.replace('<div class="app-version" id="app-version">V3.14s</div>', '<div class="app-version" id="app-version">V3.14t</div>')
h = h.replace('/* 3D TISK — V3.14s BETA */', '/* 3D TISK — V3.14t BETA */')
h = h.replace('/* 3D TISK — V3.14s: kompaktní rozhraní + záložky */', '/* 3D TISK — V3.14t: kompaktní rozhraní + záložky */')

adv_old = '<label>Účel<select id="print3d-purpose" onchange="schedule3DPrintEstimate()"><option value="architecture" selected>Architektonická maketa</option><option value="normal">Běžný díl</option><option value="strong">Pevný díl</option></select></label>'
adv_new = adv_old + '<label>Cíl doporučení<select id="print3d-priority" onchange="schedule3DPrintEstimate()"><option value="balanced" selected>Vyvážený / spolehlivý</option><option value="detail">Detail / přesnost</option><option value="speed">Rychlost / prototyp</option></select></label>'
if adv_old in h and 'id="print3d-priority"' not in h:
    h = h.replace(adv_old, adv_new, 1)

simple_anchor = '''<select id="print3d-simple-purpose" onchange="set3DPrintSimplePurpose(this.value)">
                <option value="architecture" selected>Maketa / dekorace</option><option value="normal">Běžný předmět</option><option value="strong">Pevný funkční díl</option>
              </select>
            </label>'''
simple_new = simple_anchor + '''
            <label style="font-size:11px;color:var(--muted);display:flex;flex-direction:column;gap:4px;margin-top:8px">Co je důležitější?
              <select id="print3d-simple-priority" onchange="set3DPrintSimplePriority(this.value)">
                <option value="balanced" selected>Vyvážený tisk</option><option value="detail">Co nejhezčí / přesný</option><option value="speed">Co nejrychlejší prototyp</option>
              </select>
            </label>
            <div class="print3d-simple-note">Výchozí <b>Vyvážený tisk</b> míří na spolehlivý výsledek bez zbytečně husté výplně. Detail zpomalí vrstvy; Rychlost zjednoduší výplň a použije vyšší vrstvu, pokud to geometrie dovolí.</div>'''
if simple_anchor in h and 'id="print3d-simple-priority"' not in h:
    h = h.replace(simple_anchor, simple_new, 1)

h = h.replace(
    "const pairs=[['print3d-material','print3d-simple-material'],['print3d-purpose','print3d-simple-purpose'],['print3d-units','print3d-simple-units'],['print3d-scale','print3d-simple-scale']]",
    "const pairs=[['print3d-material','print3d-simple-material'],['print3d-purpose','print3d-simple-purpose'],['print3d-priority','print3d-simple-priority'],['print3d-units','print3d-simple-units'],['print3d-scale','print3d-simple-scale']]"
)
purpose_fn = "function set3DPrintSimplePurpose(v){const a=document.getElementById('print3d-purpose');if(a)a.value=v;print3dState.simplePrepared=false;update3DPrintSimpleUI()}"
if purpose_fn in h and 'function set3DPrintSimplePriority' not in h:
    h = h.replace(purpose_fn, purpose_fn + "\nfunction set3DPrintSimplePriority(v){const a=document.getElementById('print3d-priority');if(a)a.value=v;print3dState.simplePrepared=false;update3DPrintSimpleUI()}", 1)

replacement = '''function analyze3DPrintRecommendationGeometry(){
  const out=current3DPrintDims(),tri=get3DPrintTriangleCache(),over=get3DPrintOverhangInfo();
  if(!out)return {ready:false,over};
  const dims=[Math.max(.001,out.x),Math.max(.001,out.y),Math.max(.001,out.z)].sort((a,b)=>a-b),minDim=dims[0],maxDim=dims[2],foot=Math.max(1,out.x*out.y),bboxVol=Math.max(1,out.x*out.y*out.z),boxArea=Math.max(1,2*(out.x*out.y+out.x*out.z+out.y*out.z));
  const complexity=tri?.area>0?tri.area/boxArea:1,stability=out.z/Math.max(1,Math.sqrt(foot)),aspect=maxDim/minDim;
  const size=maxDim<20?'tiny':maxDim<45?'small':maxDim>130?'large':'medium';
  const shape=complexity>2.6?'complex':complexity>1.55?'medium':'simple';
  return {ready:true,out,tri,over,minDim,maxDim,foot,bboxVol,complexity,stability,aspect,size,shape};
}
function apply3DPrintRecommendedSettings(show=true){
  print3dState.simplePrepared=true;
  const purpose=document.getElementById('print3d-purpose')?.value||'architecture',priority=document.getElementById('print3d-priority')?.value||'balanced',material=document.getElementById('print3d-material')?.value||'pla',g=analyze3DPrintRecommendationGeometry();
  let quality='quality';
  if(priority==='detail')quality='detail';
  else if(priority==='speed')quality=(g.ready&&(g.size==='tiny'||g.shape==='complex'))?'quality':'speed';
  else if(purpose==='architecture'&&g.ready&&(g.size==='tiny'||g.size==='small'||g.shape==='complex'))quality='detail';
  document.getElementById('print3d-quality').value=quality;
  apply3DPrintMaterialPreset(false);apply3DPrintQualityPreset(false);

  let perimeters=3,infill=12,pattern='gyroid';
  if(purpose==='architecture'){
    perimeters=2;infill=priority==='speed'?5:priority==='detail'?8:7;pattern='rectilinear';
  }else if(purpose==='strong'){
    perimeters=4;infill=priority==='speed'?18:priority==='detail'?26:22;pattern='gyroid';
  }else{
    perimeters=3;infill=priority==='speed'?8:priority==='detail'?15:12;pattern=priority==='speed'?'rectilinear':'gyroid';
  }
  if(g.ready){
    if(g.size==='large'&&purpose!=='strong')infill=Math.max(5,infill-2);
    if(g.size==='tiny'&&purpose==='architecture')infill=Math.max(4,infill-2);
    if(g.minDim<4.5||g.stability>2.2||g.aspect>8)perimeters+=1;
    if(g.shape==='complex'&&purpose!=='architecture')perimeters+=1;
    if(purpose==='strong'&&g.minDim<8)perimeters=Math.max(perimeters,5);
  }
  if(priority==='speed'&&purpose!=='strong')perimeters=Math.max(2,perimeters-1);
  perimeters=Math.max(2,Math.min(6,perimeters));infill=Math.max(4,Math.min(35,Math.round(infill)));
  set3DInput('print3d-perimeters',perimeters);set3DInput('print3d-infill',infill);set3DInput('print3d-infill-pattern',pattern);

  let top=priority==='speed'?3:priority==='detail'?5:4,bottom=priority==='speed'?3:4;
  if(purpose==='strong'){top=Math.max(top,5);bottom=Math.max(bottom,5)}
  set3DInput('print3d-top-solid',top);set3DInput('print3d-bottom-solid',bottom);

  const over=g.over||get3DPrintOverhangInfo();let support='off';
  if(over&&over.ratio>.025)support=over.ratio>.12?'everywhere':'buildplate';
  set3DInput('print3d-supports',support);
  const supportDensity=priority==='speed'?10:priority==='detail'?15:12;
  set3DInput('print3d-support-density',over&&over.ratio>.12?Math.min(20,supportDensity+3):supportDensity);set3DInput('print3d-support-interface',priority==='speed'?1:2);invalidate3DPrintSupportCache();

  let brim=0;
  if(g.ready&&(g.foot<650||g.stability>1.8))brim=5;
  if(g.ready&&(g.stability>3.2||g.foot<250))brim=8;
  if(material==='asa'&&g.ready&&Math.max(g.out.x,g.out.y)>80)brim=Math.max(brim,8);
  set3DInput('print3d-brim',brim);

  const q=PRINT3D_QUALITY[document.getElementById('print3d-quality').value]||PRINT3D_QUALITY.quality,m=PRINT3D_MATERIALS[material]||PRINT3D_MATERIALS.pla;
  const goalLabel=priority==='detail'?'Detail / přesnost':priority==='speed'?'Rychlost / prototyp':'Vyvážený / spolehlivý',purposeLabel=purpose==='architecture'?'maketa / dekorace':purpose==='strong'?'pevný funkční díl':'běžný předmět';
  const lines=[`Cíl: ${goalLabel} · použití: ${purposeLabel}`,`Tiskárna: Original Prusa i3 MK3S · tryska ${num3D('print3d-nozzle',.4).toFixed(2)} mm`,`Profil: ${q.label} · vrstva ${num3D('print3d-layer-height').toFixed(2)} mm`,`Perimetry: ${perimeters} · výplň ${infill} % (${document.getElementById('print3d-infill-pattern').selectedOptions[0].text}) · plné vrstvy ${top}/${bottom}`,`Podpěry: ${support==='off'?'vypnuto':support==='buildplate'?'jen z podložky':'všude'} · brim: ${brim?brim+' mm':'ne'}`,`Tryska: ${m.nozzleFirst} / ${m.nozzle} °C · podložka: ${m.bedFirst} / ${m.bed} °C · ventilátor: ${m.fan} %`,`Rychlosti: perimetry ${num3D('print3d-speed-perim')} · výplň ${num3D('print3d-speed-infill')} · travel ${num3D('print3d-speed-travel')} mm/s`];
  if(g.ready){
    const sizeLabel=g.size==='tiny'?'velmi malý':g.size==='small'?'malý':g.size==='large'?'velký':'střední',shapeLabel=g.shape==='complex'?'členitý':g.shape==='simple'?'jednoduchý':'středně členitý';
    lines.push(`Analýza modelu: ${sizeLabel}, ${shapeLabel}; rozměr ${g.out.x.toFixed(1)} × ${g.out.y.toFixed(1)} × ${g.out.z.toFixed(1)} mm.`);
    if(purpose!=='strong'&&infill<=10)lines.push('Výplň je záměrně nízká: u nenosného modelu pevnost zbytečně nezvyšujeme hustou výplní; důležitější jsou obvodové stěny a plné horní/spodní vrstvy.');
    if(g.stability>1.8||g.foot<650)lines.push('Model má menší nebo štíhlejší kontakt s podložkou, proto byl přidán brim.');
  }
  if(over&&over.ratio>.025)lines.push(`Toolbox našel převislou plochu (~${(over.ratio*100).toFixed(1)} % povrchu), proto zapnul podpěry ${support==='everywhere'?'všude':'z podložky'}.`);
  lines.push(m.note);
  const box=document.getElementById('print3d-recommended');if(box)box.innerHTML='<b>NASTAVENO DOPORUČENÍ PODLE MODELU:</b><br>'+lines.map(escapeHtml).join('<br>');
  update3DPrintLayerControls();render3DPrintLayer();schedule3DPrintEstimate();if(show){const st=document.getElementById('st-3dprint');if(st)st.textContent='Doporučení bylo přepočítáno podle geometrie modelu, účelu a cíle tisku.'}
}
'''

pattern = r'function apply3DPrintRecommendedSettings\(show=true\)\{.*?\n\}\nfunction invalidate3DPrintSupportCache\(\)'
m = re.search(pattern, h, flags=re.S)
if not m:
    raise SystemExit('apply3DPrintRecommendedSettings block not found')
h = re.sub(pattern, lambda _: replacement + 'function invalidate3DPrintSupportCache()', h, count=1, flags=re.S)

p.write_text(h, encoding='utf-8')
print('V3.14t smart recommendations patched')
