from pathlib import Path

p = Path('index.html')
s = p.read_text(encoding='utf-8')

# Version bump throughout the single-file app.
s = s.replace('3.14n', '3.14o')

# Main description / install links.
s = s.replace(
    'PrusaBridge nejdřív spustí <b>Windows.Graphics.Printing3D.RepairAsync</b> (Windows repair algoritmus používaný PrusaSlicerem na Windows), a teprve jeho výstup předá skutečnému PrusaSliceru pro slicing.',
    'PrusaBridge nejdřív spustí <b>nativní WinRT Printing3DModel.RepairAsync přes C++ helper</b> (bez PowerShell projekce WinRT), a teprve jeho výstup předá skutečnému PrusaSliceru pro slicing.'
)
s = s.replace(
    'href="20-20-PrusaBridge.exe" download',
    'href="https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/PrusaBridge/20-20-PrusaBridge.exe" download'
)
s = s.replace(
    '<button id="print3d-prusa-check-btn" class="back-btn" style="margin:0" onclick="check3DPrintPrusaBridge(false)">Zkontrolovat spojení</button>',
    '<button id="print3d-prusa-check-btn" class="back-btn" style="margin:0" onclick="check3DPrintPrusaBridge(false)">Zkontrolovat spojení</button>\n              <button id="print3d-prusa-update-btn" class="back-btn" style="margin:0" onclick="update3DPrintPrusaBridge(false)">↻ Aktualizovat Bridge</button>'
)
s = s.replace(
    '<div class="print3d-simple-note strong"><b>V3.14o · Windows RepairAsync pipeline</b><br>Při exportu se vždy pošle přesná STL z vieweru do Bridge. Bridge ji převede do 3MF, načte ji do nativního WinRT <code>InMemoryRandomAccessStream</code>, spustí Windows <code>RepairAsync()</code>, převede opravený model zpět na STL a až potom ho slicuje PrusaSlicerem. Tím se neopíráme o slabší CLI <code>--repair</code> ani o .NET stream adaptér bez <code>CloneStream()</code>.</div>',
    '<div class="print3d-simple-note strong"><b>V3.14o · Native WinRT repair + automatické aktualizace</b><br>Bridge už nevolá Windows 3D API z PowerShellu. Používá typovaný C++/WinRT helper, který načte 3MF, zavolá <code>Printing3DModel.RepairAsync()</code> a vrátí opravený model PrusaSliceru. Bridge si zároveň umí z GitHubu zkontrolovat novou verzi, ověřit její SHA-256, ukončit starý proces a spustit nový.</div>'
)
s = s.replace(
    '<div class="print3d-estimate-note" style="margin-top:9px"><b>V3.14o používá skutečný nainstalovaný PrusaSlicer na tomto Windows PC.</b> Nový Bridge používá nainstalované MK3S profily a při exportu standardně slicuje původní STL přímo, nikoli předem exportovanou repair kopii. Web komunikuje pouze s <code>127.0.0.1:8091</code>. <b>Po jednorázovém spuštění nového EXE</b> se zaregistruje protokol <code>toolbox-prusa://</code> a příště lze Bridge zapnout přímo tlačítkem na webu.</div>',
    '<div class="print3d-estimate-note" style="margin-top:9px"><b>V3.14o používá skutečný nainstalovaný PrusaSlicer na tomto Windows PC.</b> Web komunikuje pouze s <code>127.0.0.1:8091</code>. <b>V3.14o je potřeba jednou ručně spustit</b>, protože starší Bridge ještě neumí bezpečný self-update. Od V3.14o dál už tlačítko na webu umí verzi zkontrolovat a Bridge se při dostupné novější verzi aktualizuje automaticky.</div>'
)
s = s.replace(
    '<div class="print3d-export-warning"><b>PRUSASLICER + WINDOWS REPAIR BACKEND V3.14o:</b> finální G-code vytváří <b>skutečný lokální PrusaSlicer</b>. Před slicingem ale model projde <b>Windows.Graphics.Printing3D.RepairAsync</b>, tedy Windows 3D repair algoritmem. Bridge pracuje jen na <code>127.0.0.1</code>; model se nikam neuploaduje.</div>',
    '<div class="print3d-export-warning"><b>PRUSASLICER + NATIVE WINRT REPAIR V3.14o:</b> finální G-code vytváří <b>skutečný lokální PrusaSlicer</b>. Před slicingem model projde typovaným C++/WinRT voláním <b>Printing3DModel.RepairAsync</b>. Bridge pracuje jen na <code>127.0.0.1</code>; model se nikam neuploaduje.</div>'
)

start_marker = "const PRINT3D_PRUSA_BRIDGE_URL='http://127.0.0.1:8091';"
end_marker = 'function get3DPrintPrusaBridgeSettings(){'
start = s.index(start_marker)
end = s.index(end_marker, start)
new_js = r'''const PRINT3D_PRUSA_BRIDGE_URL='http://127.0.0.1:8091';
const PRINT3D_PRUSA_BRIDGE_EXPECTED='3.14o';
const PRINT3D_PRUSA_BRIDGE_DOWNLOAD='https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/PrusaBridge/20-20-PrusaBridge.exe';
function p3BridgeState(){
  if(!print3dState.prusaBridge)print3dState.prusaBridge={online:false,status:null,lastCheck:0,updating:false,autoTried:false};
  return print3dState.prusaBridge;
}
async function p3BridgeFetch(path,opts={},timeout=15000){
  const ctrl=new AbortController(),tm=setTimeout(()=>ctrl.abort(),timeout);
  try{return await fetch(PRINT3D_PRUSA_BRIDGE_URL+path,{...opts,signal:ctrl.signal,cache:'no-store'})}
  catch(e){if(e?.name==='AbortError')throw new Error('PrusaBridge neodpověděl v časovém limitu.');throw e}
  finally{clearTimeout(tm)}
}
async function p3BridgeError(resp){
  try{const j=await resp.json();return [j.error,j.detail].filter(Boolean).join('\n')||`HTTP ${resp.status}`}catch{return `HTTP ${resp.status}`}
}
function download3DPrintPrusaBridge(){
  const a=document.createElement('a');a.href=PRINT3D_PRUSA_BRIDGE_DOWNLOAD;a.download='20-20-PrusaBridge.exe';a.rel='noopener';document.body.appendChild(a);a.click();a.remove();
}
async function update3DPrintPrusaBridge(silent=false){
  const box=document.getElementById('print3d-prusa-bridge-status'),state=p3BridgeState();
  if(state.updating)return false;state.updating=true;
  if(box&&!silent){box.className='print3d-health warn';box.innerHTML='<b>↻ KONTROLUJI AKTUALIZACI PRUSABRIDGE…</b>'}
  try{
    let r;
    try{r=await p3BridgeFetch('/update',{method:'POST'},15000)}catch(e){r=null}
    if(!r||!r.ok){
      if(box){box.className='print3d-health warn';box.innerHTML=`<b>⚠ STARÝ BRIDGE NEUMÍ AUTOMATICKOU AKTUALIZACI</b><br>Stáhnu aktuální Bridge ${PRINT3D_PRUSA_BRIDGE_EXPECTED}. Jednou ho spusť; od této verze dál se aktualizace provedou automaticky.`}
      download3DPrintPrusaBridge();return false;
    }
    const j=await r.json().catch(()=>({}));
    if(box){box.className='print3d-health warn';box.innerHTML=`<b>↻ AKTUALIZUJI PRUSABRIDGE ${escapeHtml(j.from||'')} → ${escapeHtml(j.to||PRINT3D_PRUSA_BRIDGE_EXPECTED)}</b><br>Starý proces se ukončí a nový Bridge se znovu spustí. Čekám na připojení…`}
    let tries=0;await new Promise(resolve=>{const tick=async()=>{tries++;try{const ok=await check3DPrintPrusaBridge(true,true);if(ok){resolve();return}}catch{}if(tries<25)setTimeout(tick,500);else resolve()};setTimeout(tick,700)});
    return p3BridgeState().online;
  }finally{state.updating=false}
}
async function check3DPrintPrusaBridge(silent=true,fromUpdater=false){
  const box=document.getElementById('print3d-prusa-bridge-status'),state=p3BridgeState();
  if(box&&!silent){box.className='print3d-health warn';box.innerHTML='<b>Kontroluji PrusaBridge…</b>'}
  try{
    const r=await p3BridgeFetch('/status',{},5000);if(!r.ok)throw new Error(await p3BridgeError(r));const j=await r.json();state.online=!!j.ok;state.status=j;state.lastCheck=Date.now();
    if(box){
      if(j.ok){
        if(String(j.bridgeVersion||'')!==PRINT3D_PRUSA_BRIDGE_EXPECTED){
          box.className='print3d-health warn';box.innerHTML=`<b>↻ BĚŽÍ PRUSABRIDGE ${escapeHtml(j.bridgeVersion||'?')} · WEB POTŘEBUJE ${PRINT3D_PRUSA_BRIDGE_EXPECTED}</b><br>${j.updateSupported?'Bridge podporuje automatickou aktualizaci. Spouštím kontrolu nové verze…':'Tahle stará verze ještě neumí self-update. Klikni na ↻ Aktualizovat Bridge nebo stáhni nový EXE.'}`;
          if(!fromUpdater&&!state.autoTried){state.autoTried=true;setTimeout(()=>update3DPrintPrusaBridge(true),250)}
          return false
        }
        box.className='print3d-health ok';box.innerHTML=`<b>✓ PRUSASLICER + NATIVE WINRT REPAIR PŘIPOJEN</b><br>${escapeHtml(j.slicerVersion||'PrusaSlicer')} · Bridge ${escapeHtml(j.bridgeVersion||'')}${j.protocolRegistered?' · webové spuštění aktivní':''}${j.latestVersion?` · latest ${escapeHtml(j.latestVersion)}`:''}<br><b>Repair:</b> ${escapeHtml(j.repairEngine||'Native WinRT RepairAsync')}<br><span style="opacity:.75">${escapeHtml(j.slicerPath||'')}</span>`;
        state.autoTried=false;return true
      }
      box.className='print3d-health err';box.innerHTML=`<b>⚠ BRIDGE BĚŽÍ, ALE PRUSASLICER NENALEZEN</b><br>${escapeHtml(j.message||'Nastav cestu k prusa-slicer-console.exe v PrusaBridge.ini.')}`
    }
    return false
  }catch(e){state.online=false;state.status=null;state.lastCheck=Date.now();if(box){box.className='print3d-health err';box.innerHTML=`<b>⚠ PRUSABRIDGE NENÍ SPUŠTĚNÝ</b><br>Klikni <b>▶ Spustit PrusaBridge</b>. Pokud Bridge ještě není nainstalovaný, použij <b>↓ Bridge / instalace</b> a EXE jednou spusť.<br><span style="opacity:.75">${escapeHtml(e?.message||String(e))}</span>`}return false}
}
function poll3DPrintPrusaBridgeStart(){
  const box=document.getElementById('print3d-prusa-bridge-status');if(box){box.className='print3d-health warn';box.innerHTML='<b>Spouštím PrusaBridge…</b><br>Pokud se prohlížeč zeptá na otevření externí aplikace, potvrď ho. Bridge při startu sám zkontroluje aktuální verzi.'}
  let tries=0;const tick=async()=>{tries++;if(await check3DPrintPrusaBridge(true))return;if(tries<12)setTimeout(tick,650);else if(box){box.className='print3d-health err';box.innerHTML=`<b>⚠ BRIDGE SE NESPUSTIL</b><br>Stáhni aktuální <b>20-20-PrusaBridge.exe</b> a jednou ho spusť. Potom už webové spuštění i aktualizace fungují automaticky.`}};setTimeout(tick,650)
}
'''
s = s[:start] + new_js + s[end:]
s = s.replace(
    "throw new Error('PrusaBridge 3.14o není připravený. Klikni na „Spustit PrusaBridge“.');",
    "throw new Error('PrusaBridge 3.14o není připravený. Klikni na „Spustit PrusaBridge“ nebo „Aktualizovat Bridge“.');"
)

p.write_text(s, encoding='utf-8')
