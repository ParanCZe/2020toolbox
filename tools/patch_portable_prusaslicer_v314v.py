from pathlib import Path
import re

MAIN = Path('PrusaBridge/src/main.go')
INDEX = Path('index.html')

s = MAIN.read_text(encoding='utf-8-sig')

# Bridge V3.14v is the first release that owns a complete portable PrusaSlicer
# runtime + its own isolated PrusaSlicer datadir. No system installation is required.
s = s.replace('const bridgeVersion = "3.14t"', 'const bridgeVersion = "3.14v"', 1)

if 'slicerDataDir' not in s:
    s = s.replace(
        '\tslicerManaged         bool\n)',
        '\tslicerManaged         bool\n\tslicerDataDir         string\n\tslicerDataMu          sync.Mutex\n)',
        1,
    )

managed_helpers = r'''
func ensureManagedSlicerData(consolePath string) error {
	slicerDataMu.Lock()
	defer slicerDataMu.Unlock()

	runtimeDir := filepath.Dir(consolePath)
	profilesDir := filepath.Join(runtimeDir, "resources", "profiles")
	dataDir := filepath.Join(installDir, "PrusaData")
	vendorDir := filepath.Join(dataDir, "vendor")
	if err := os.MkdirAll(vendorDir, 0755); err != nil {
		return fmt.Errorf("vytvoření PrusaData: %w", err)
	}

	for _, name := range []string{"PrusaResearch.ini", "PrusaResearch.idx"} {
		src := filepath.Join(profilesDir, name)
		dst := filepath.Join(vendorDir, name)
		ss, err := os.Stat(src)
		if err != nil {
			return fmt.Errorf("portable profil %s chybí: %w", name, err)
		}
		if ds, err := os.Stat(dst); err == nil && ds.Size() == ss.Size() {
			continue
		}
		if err := copyFile(src, dst); err != nil {
			return fmt.Errorf("kopie profilu %s: %w", name, err)
		}
	}

	cfg := "[presets]\r\n" +
		"filament = Prusament PLA\r\n" +
		"print = 0.20mm QUALITY @MK3\r\n" +
		"printer = Original Prusa i3 MK3S & MK3S+\r\n\r\n" +
		"[vendor:PrusaResearch]\r\n" +
		"model:MK3S = 0.4\r\n"
	cfgPath := filepath.Join(dataDir, "PrusaSlicer.ini")
	if old, err := os.ReadFile(cfgPath); err != nil || string(old) != cfg {
		// os.WriteFile writes raw UTF-8 bytes without a BOM. PrusaSlicer rejects a BOM
		// before the first INI section on a clean portable installation.
		if err := os.WriteFile(cfgPath, []byte(cfg), 0644); err != nil {
			return fmt.Errorf("zápis PrusaSlicer.ini: %w", err)
		}
	}
	slicerDataDir = dataDir
	return nil
}

func slicerCLIArgs(args ...string) []string {
	if slicerManaged && slicerDataDir != "" {
		out := make([]string, 0, len(args)+2)
		out = append(out, "--datadir", slicerDataDir)
		out = append(out, args...)
		return out
	}
	return args
}

func runSlicer(timeout time.Duration, args ...string) (string, error) {
	return runCmd(timeout, slicerPath, slicerCLIArgs(args...)...)
}

'''
if 'func ensureManagedSlicerData(' not in s:
    anchor = 'func setSlicerBootstrapState(running bool, status, errText string) {'
    if anchor not in s:
        raise SystemExit('managed-datadir insertion anchor not found')
    s = s.replace(anchor, managed_helpers + anchor, 1)

# Reset the managed datadir whenever discovery starts.
if '\tslicerDataDir = ""\n\tvar candidates []string' not in s:
    s = s.replace(
        '\tslicerManaged = false\n\tvar candidates []string',
        '\tslicerManaged = false\n\tslicerDataDir = ""\n\tvar candidates []string',
        1,
    )

# A portable executable is only considered usable after its bundled vendor
# profiles have been installed into the Bridge-owned datadir.
old_pick = '''\t\t\tslicerPath = ap
\t\t\tslicerManaged = pathWithin(ap, filepath.Join(installDir, "Slicer"))
\t\t\tslicerGUI = filepath.Join(filepath.Dir(ap), "prusa-slicer.exe")'''
new_pick = '''\t\t\tslicerPath = ap
\t\t\tslicerManaged = pathWithin(ap, filepath.Join(installDir, "Slicer"))
\t\t\tif slicerManaged {
\t\t\t\tif err := ensureManagedSlicerData(ap); err != nil {
\t\t\t\t\tslicerPath = ""
\t\t\t\t\tslicerManaged = false
\t\t\t\t\tslicerDataDir = ""
\t\t\t\t\tcontinue
\t\t\t\t}
\t\t\t}
\t\t\tslicerGUI = filepath.Join(filepath.Dir(ap), "prusa-slicer.exe")'''
if old_pick in s:
    s = s.replace(old_pick, new_pick, 1)

# All profile-dependent PrusaSlicer calls use our isolated datadir when the
# managed runtime is active. Existing user-installed PrusaSlicer remains untouched.
s = s.replace('runCmd(180*time.Second, slicerPath, "--export-3mf",', 'runSlicer(180*time.Second, "--export-3mf",')
s = s.replace('runCmd(180*time.Second, slicerPath, "--export-stl",', 'runSlicer(180*time.Second, "--export-stl",')
s = s.replace('runCmd(10*time.Minute, slicerPath, args...)', 'runSlicer(10*time.Minute, args...)')

# Make the status endpoint explicit so the web app can tell the user that no
# separate PrusaSlicer installation is required.
status_anchor = '''\tif li.Version != "" {
\t\tresp.LatestVersion = li.Version
\t\tresp.UpdateAvailable = li.Version != bridgeVersion
\t\tresp.DownloadURL = li.URL
\t}
\tif slicerPath == "" {'''
status_new = '''\tif li.Version != "" {
\t\tresp.LatestVersion = li.Version
\t\tresp.UpdateAvailable = li.Version != bridgeVersion
\t\tresp.DownloadURL = li.URL
\t}
\tif slicerPath != "" && slicerManaged {
\t\tresp.Message = "Portable PrusaSlicer je připravený. Samostatná instalace PrusaSliceru není potřeba."
\t}
\tif slicerPath == "" {'''
if status_anchor in s:
    s = s.replace(status_anchor, status_new, 1)

# Root diagnostics page: distinguish the Toolbox-managed runtime.
root_old = '''\tif ok {
\t\tfmt.Fprintf(w, `<p class="ok"><b>✓ Bridge běží a PrusaSlicer byl nalezen.</b></p><p>%s</p><p>Repair engine: <b>Native WinRT Printing3DModel.RepairAsync</b> → PrusaSlicer.</p>`, htmlEscape(slicerPath))
\t} else {'''
root_new = '''\tif ok {
\t\tif slicerManaged {
\t\t\tfmt.Fprintf(w, `<p class="ok"><b>✓ Bridge běží s vlastním portable PrusaSlicerem.</b></p><p>Samostatná instalace PrusaSliceru není potřeba.</p><p>%s</p><p>Repair engine: <b>Native WinRT Printing3DModel.RepairAsync</b> → PrusaSlicer.</p>`, htmlEscape(slicerPath))
\t\t} else {
\t\t\tfmt.Fprintf(w, `<p class="ok"><b>✓ Bridge běží a PrusaSlicer byl nalezen.</b></p><p>%s</p><p>Repair engine: <b>Native WinRT Printing3DModel.RepairAsync</b> → PrusaSlicer.</p>`, htmlEscape(slicerPath))
\t\t}
\t} else {'''
if root_old in s:
    s = s.replace(root_old, root_new, 1)

required = [
    'const bridgeVersion = "3.14v"',
    'func ensureManagedSlicerData(',
    'func runSlicer(',
    'model:MK3S = 0.4',
    'Portable PrusaSlicer je připravený. Samostatná instalace PrusaSliceru není potřeba.',
]
for needle in required:
    if needle not in s:
        raise SystemExit(f'main.go V3.14v patch incomplete: {needle}')
MAIN.write_text(s, encoding='utf-8', newline='\n')

# Web app: keep the application on V3.14v and require the new Bridge. The first
# run may download ~100 MB of the official PrusaSlicer portable package.
h = INDEX.read_text(encoding='utf-8-sig')
h = h.replace('V3.14u', 'V3.14v')
h = re.sub(r"PRINT3D_PRUSA_BRIDGE_EXPECTED='[^']+'", "PRINT3D_PRUSA_BRIDGE_EXPECTED='3.14v'", h, count=1)
h = h.replace('PrusaSlicer musí být nainstalovaný', 'PrusaSlicer se při prvním použití připraví automaticky')
h = h.replace('PrusaSlicer musí být nainstalován', 'PrusaSlicer se při prvním použití připraví automaticky')
INDEX.write_text(h, encoding='utf-8', newline='\n')

print('V3.14v: portable PrusaSlicer runtime + isolated managed datadir patched.')
