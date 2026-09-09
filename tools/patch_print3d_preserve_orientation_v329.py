from pathlib import Path

INDEX = Path('index.html')
s = INDEX.read_text(encoding='utf-8-sig')

old_load = "invalidate3DPrintSliceCache();update3DPrintTransform();await autoAlign3DPrintModel(true);fit3DPrintView(true);setTimeout(()=>fit3DPrintView(true),60);render3DPrintLoaded();"
new_load = "invalidate3DPrintSliceCache();update3DPrintTransform();place3DPrintOnBed();fit3DPrintView(true);setTimeout(()=>fit3DPrintView(true),60);render3DPrintLoaded();"
if old_load in s:
    s = s.replace(old_load, new_load, 1)
elif new_load not in s:
    raise SystemExit('3D print load-orientation anchor not found')

old_prepare = "try{await autoAlign3DPrintModel(true);apply3DPrintRecommendedSettings(false);print3dState.simplePrepared=true;"
new_prepare = "try{place3DPrintOnBed();apply3DPrintRecommendedSettings(false);print3dState.simplePrepared=true;"
if old_prepare in s:
    s = s.replace(old_prepare, new_prepare, 1)
elif new_prepare not in s:
    raise SystemExit('3D print simple-prepare orientation anchor not found')

old_note = "Při načtení se model zkusí automaticky srovnat podle dominantních rovin. Kdyby orientace neseděla, stále můžeš použít X/Y/Z +90° nebo reset natočení."
new_note = "Orientace modelu se při načtení ani při Nastavit pro tisk automaticky nemění. Ručně nastavené natočení zůstane zachované až do G-code. Automatické srovnání použij jen ručně, pokud ho opravdu chceš."
if old_note in s:
    s = s.replace(old_note, new_note, 1)

old_status = "Model a tiskové parametry byly automaticky nastaveny."
new_status = "Tiskové parametry byly nastaveny; ruční orientace modelu zůstala zachovaná."
if old_status in s:
    s = s.replace(old_status, new_status, 1)

required = [
    'update3DPrintTransform();place3DPrintOnBed();fit3DPrintView(true)',
    'try{place3DPrintOnBed();apply3DPrintRecommendedSettings(false)',
    'ruční orientace modelu zůstala zachovaná',
]
for needle in required:
    if needle not in s:
        raise SystemExit(f'orientation patch incomplete: {needle}')

INDEX.write_text(s, encoding='utf-8', newline='\n')
print('V3.29: 3D print preserves user model orientation through prepare and G-code workflow.')
