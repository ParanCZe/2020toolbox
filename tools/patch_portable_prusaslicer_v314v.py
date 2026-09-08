from pathlib import Path

MAIN = Path('PrusaBridge/src/main.go')
INDEX = Path('index.html')

s = MAIN.read_text(encoding='utf-8-sig')

if '"archive/zip"' not in s:
    s = s.replace('import (\n\t"bytes"', 'import (\n\t"archive/zip"\n\t"bytes"', 1)

s = s.replace('const bridgeVersion = "3.14s"', 'const bridgeVersion = "3.14t"', 1)
if 'prusaLatestReleaseAPI' not in s:
    s = s.replace(
        'const latestJSONURL = "https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/PrusaBridge/latest.json"',
        'const latestJSONURL = "https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/PrusaBridge/latest.json"\n'
        'const prusaLatestReleaseAPI = "https://api.github.com/repos/prusa3d/PrusaSlicer/releases/latest"\n'
        'const prusaFallbackZipURL = "https://github.com/prusa3d/PrusaSlicer/releases/download/version_2.9.6/PrusaSlicer-2.9.6.zip"\n'
        'const prusaFallbackZipSHA256 = "5aaf22e42f95accecfa122d23a835911f289ecc2ff606db3e83d637ddcc0a209"',
        1,
    )

old_globals = '''\trepairHelper string
\tupdateMu     sync.Mutex
\trunMu        sync.Mutex
)'''
new_globals = '''\trepairHelper string
\tupdateMu     sync.Mutex
\trunMu        sync.Mutex
\tslicerBootstrapMu     sync.Mutex
\tslicerBootstrapping   bool
\tslicerBootstrapStatus string
\tslicerBootstrapError  string
\tslicerManaged         bool
)'''
if old_globals in s:
    s = s.replace(old_globals, new_globals, 1)

latest_anchor = '''type latestInfo struct {
\tVersion string `json:"version"`
\tURL     string `json:"url"`
\tSHA256  string `json:"sha256"`
}
'''
release_types = latest_anchor + '''
type prusaRelease struct {
\tTagName string `json:"tag_name"`
\tName    string `json:"name"`
\tAssets  []struct {
\t\tName               string `json:"name"`
\t\tBrowserDownloadURL string `json:"browser_download_url"`
\t\tDigest             string `json:"digest"`
\t\tSize               int64  `json:"size"`
\t} `json:"assets"`
}
'''
if 'type prusaRelease struct' not in s:
    if latest_anchor not in s:
        raise SystemExit('latestInfo anchor not found')
    s = s.replace(latest_anchor, release_types, 1)

status_old = '''\tSlicerVersion      string `json:"slicerVersion,omitempty"`
\tProtocolRegistered bool   `json:"protocolRegistered"`'''
status_new = '''\tSlicerVersion      string `json:"slicerVersion,omitempty"`
\tSlicerManaged      bool   `json:"slicerManaged"`
\tSlicerBootstrapping bool  `json:"slicerBootstrapping"`
\tSlicerBootstrapStatus string `json:"slicerBootstrapStatus,omitempty"`
\tSlicerBootstrapError string `json:"slicerBootstrapError,omitempty"`
\tProtocolRegistered bool   `json:"protocolRegistered"`'''
if status_old in s:
    s = s.replace(status_old, status_new, 1)

serve_old = '''\tif args[0] == "--serve" {
\t\tensureInstalledArtifacts()
\t\tregisterProtocol()
\t\tfindSlicer()
\t\tif started, _ := maybeAutoUpdate(); started {
\t\t\treturn
\t\t}
\t\tserve()
\t\treturn
\t}'''
serve_new = '''\tif args[0] == "--serve" {
\t\tensureInstalledArtifacts()
\t\tregisterProtocol()
\t\tfindSlicer()
\t\tif slicerPath == "" {
\t\t\tstartPortableSlicerBootstrap()
\t\t}
\t\tif started, _ := maybeAutoUpdate(); started {
\t\t\treturn
\t\t}
\t\tserve()
\t\treturn
\t}'''
if serve_old in s:
    s = s.replace(serve_old, serve_new, 1)

find_anchor = '''func findSlicer() {
\tvar candidates []string
\t// ini override'''
find_new = '''func findSlicer() {
\tslicerPath = ""
\tslicerGUI = ""
\tslicerVer = ""
\tslicerManaged = false
\tvar candidates []string
\t// ini override'''
if find_anchor in s:
    s = s.replace(find_anchor, find_new, 1)

portable_candidate_anchor = '''\tpf := os.Getenv("ProgramFiles")
\tpfx86 := os.Getenv("ProgramFiles(x86)")'''
portable_candidate_new = '''\tif p := findPortableSlicer(); p != "" {
\t\tcandidates = append(candidates, p)
\t}
\tpf := os.Getenv("ProgramFiles")
\tpfx86 := os.Getenv("ProgramFiles(x86)")'''
if portable_candidate_anchor in s and 'if p := findPortableSlicer(); p != ""' not in s:
    s = s.replace(portable_candidate_anchor, portable_candidate_new, 1)

managed_anchor = '''\t\t\tslicerPath = ap
\t\t\tslicerGUI = filepath.Join(filepath.Dir(ap), "prusa-slicer.exe")'''
managed_new = '''\t\t\tslicerPath = ap
\t\t\tslicerManaged = pathWithin(ap, filepath.Join(installDir, "Slicer"))
\t\t\tslicerGUI = filepath.Join(filepath.Dir(ap), "prusa-slicer.exe")'''
if managed_anchor in s:
    s = s.replace(managed_anchor, managed_new, 1)

portable_code = r'''
func setSlicerBootstrapState(running bool, status, errText string) {
	slicerBootstrapMu.Lock()
	slicerBootstrapping = running
	slicerBootstrapStatus = status
	slicerBootstrapError = errText
	slicerBootstrapMu.Unlock()
}

func slicerBootstrapSnapshot() (bool, string, string) {
	slicerBootstrapMu.Lock()
	defer slicerBootstrapMu.Unlock()
	return slicerBootstrapping, slicerBootstrapStatus, slicerBootstrapError
}

func startPortableSlicerBootstrap() {
	slicerBootstrapMu.Lock()
	if slicerBootstrapping || slicerPath != "" {
		slicerBootstrapMu.Unlock()
		return
	}
	slicerBootstrapping = true
	slicerBootstrapStatus = "Připravuji automatické stažení portable PrusaSliceru…"
	slicerBootstrapError = ""
	slicerBootstrapMu.Unlock()
	go func() {
		err := ensurePortableSlicer()
		if err != nil {
			setSlicerBootstrapState(false, "Automatická instalace portable PrusaSliceru selhala.", err.Error())
			return
		}
		findSlicer()
		if slicerPath == "" {
			setSlicerBootstrapState(false, "Portable PrusaSlicer byl rozbalen, ale konzolový slicer nebyl nalezen.", "prusa-slicer-console.exe nebyl po rozbalení nalezen")
			return
		}
		setSlicerBootstrapState(false, "Portable PrusaSlicer je připravený.", "")
	}()
}

func fetchPrusaStableRelease() (prusaRelease, error) {
	var rel prusaRelease
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, prusaLatestReleaseAPI, nil)
	if err != nil {
		return rel, err
	}
	req.Header.Set("User-Agent", "20-20-PrusaBridge/"+bridgeVersion)
	req.Header.Set("Accept", "application/vnd.github+json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return rel, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return rel, fmt.Errorf("GitHub release API HTTP %d", resp.StatusCode)
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 4<<20)).Decode(&rel); err != nil {
		return rel, err
	}
	return rel, nil
}

func choosePrusaWindowsZip(rel prusaRelease) (name, url, digest string, size int64) {
	for _, a := range rel.Assets {
		n := strings.ToLower(a.Name)
		if strings.HasPrefix(n, "prusaslicer-") && strings.HasSuffix(n, ".zip") && a.BrowserDownloadURL != "" {
			return a.Name, a.BrowserDownloadURL, a.Digest, a.Size
		}
	}
	return "PrusaSlicer-2.9.6.zip", prusaFallbackZipURL, "sha256:" + prusaFallbackZipSHA256, 106598059
}

func ensurePortableSlicer() error {
	if p := findPortableSlicer(); p != "" {
		return nil
	}
	if err := os.MkdirAll(installDir, 0755); err != nil {
		return err
	}
	rel, relErr := fetchPrusaStableRelease()
	assetName, assetURL, digest, assetSize := choosePrusaWindowsZip(rel)
	if relErr != nil || assetURL == "" {
		assetName = "PrusaSlicer-2.9.6.zip"
		assetURL = prusaFallbackZipURL
		digest = "sha256:" + prusaFallbackZipSHA256
		assetSize = 106598059
	}
	label := rel.Name
	if label == "" {
		label = rel.TagName
	}
	if label == "" {
		label = "PrusaSlicer 2.9.6"
	}
	setSlicerBootstrapState(true, fmt.Sprintf("Stahuji %s z oficiálního GitHubu Prusa3D (%.1f MB)…", assetName, float64(assetSize)/(1024*1024)), "")
	zipPath := filepath.Join(installDir, "PrusaSlicer.download.zip")
	defer os.Remove(zipPath)
	if err := downloadPrusaAsset(assetURL, zipPath, digest); err != nil {
		return err
	}
	setSlicerBootstrapState(true, "Staženo. Ověřuji a rozbaluji portable PrusaSlicer…", "")
	newRoot := filepath.Join(installDir, "Slicer.new")
	_ = os.RemoveAll(newRoot)
	if err := os.MkdirAll(newRoot, 0755); err != nil {
		return err
	}
	if err := extractZipSafe(zipPath, newRoot); err != nil {
		_ = os.RemoveAll(newRoot)
		return err
	}
	if findFileNamed(newRoot, "prusa-slicer-console.exe") == "" {
		_ = os.RemoveAll(newRoot)
		return errors.New("oficiální ZIP neobsahuje prusa-slicer-console.exe")
	}
	runtimeRoot := filepath.Join(installDir, "Slicer")
	oldRoot := filepath.Join(installDir, "Slicer.old")
	_ = os.RemoveAll(oldRoot)
	if _, err := os.Stat(runtimeRoot); err == nil {
		if err := os.Rename(runtimeRoot, oldRoot); err != nil {
			_ = os.RemoveAll(runtimeRoot)
		}
	}
	if err := os.Rename(newRoot, runtimeRoot); err != nil {
		return fmt.Errorf("aktivace portable sliceru: %w", err)
	}
	_ = os.RemoveAll(oldRoot)
	notice := "20-20 Toolbox stáhl oficiální binární vydání " + label + " přímo z GitHub Releases projektu PrusaSlicer.\r\n" +
		"Zdroj: https://github.com/prusa3d/PrusaSlicer\r\n" +
		"Licence projektu: GNU Affero General Public License v3.0 (AGPL-3.0).\r\n" +
		"Toolbox tento balík nemodifikuje; používá jeho prusa-slicer-console.exe jako lokální slicovací engine.\r\n"
	_ = os.WriteFile(filepath.Join(runtimeRoot, "20-20-PRUSASLICER-NOTICE.txt"), []byte(notice), 0644)
	_ = os.WriteFile(filepath.Join(runtimeRoot, "20-20-runtime-version.txt"), []byte(label+"\r\n"), 0644)
	return nil
}

func downloadPrusaAsset(url, dst, digest string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Minute)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "20-20-PrusaBridge/"+bridgeVersion)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("stažení PrusaSliceru: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("stažení PrusaSliceru: HTTP %d", resp.StatusCode)
	}
	tmp := dst + ".part"
	_ = os.Remove(tmp)
	f, err := os.Create(tmp)
	if err != nil {
		return err
	}
	h := sha256.New()
	written, copyErr := io.Copy(io.MultiWriter(f, h), io.LimitReader(resp.Body, 400<<20))
	closeErr := f.Close()
	if copyErr != nil {
		_ = os.Remove(tmp)
		return copyErr
	}
	if closeErr != nil {
		_ = os.Remove(tmp)
		return closeErr
	}
	if written <= 0 || written >= 400<<20 {
		_ = os.Remove(tmp)
		return fmt.Errorf("neplatná velikost staženého ZIPu: %d B", written)
	}
	want := strings.ToLower(strings.TrimSpace(strings.TrimPrefix(digest, "sha256:")))
	got := hex.EncodeToString(h.Sum(nil))
	if want != "" && got != want {
		_ = os.Remove(tmp)
		return fmt.Errorf("SHA-256 portable PrusaSliceru nesedí: očekáváno %s, získáno %s", want, got)
	}
	_ = os.Remove(dst)
	if err := os.Rename(tmp, dst); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return nil
}

func extractZipSafe(zipPath, dst string) error {
	zr, err := zip.OpenReader(zipPath)
	if err != nil {
		return err
	}
	defer zr.Close()
	base, _ := filepath.Abs(dst)
	prefix := strings.ToLower(filepath.Clean(base) + string(os.PathSeparator))
	for _, zf := range zr.File {
		clean := filepath.Clean(strings.ReplaceAll(zf.Name, "/", string(os.PathSeparator)))
		if clean == "." || filepath.IsAbs(clean) || clean == ".." || strings.HasPrefix(clean, ".."+string(os.PathSeparator)) {
			return fmt.Errorf("nebezpečná cesta v ZIPu: %s", zf.Name)
		}
		target := filepath.Join(base, clean)
		absTarget, _ := filepath.Abs(target)
		if strings.ToLower(absTarget) != strings.ToLower(base) && !strings.HasPrefix(strings.ToLower(absTarget), prefix) {
			return fmt.Errorf("cesta mimo cílovou složku: %s", zf.Name)
		}
		if zf.FileInfo().IsDir() {
			if err := os.MkdirAll(absTarget, 0755); err != nil {
				return err
			}
			continue
		}
		if err := os.MkdirAll(filepath.Dir(absTarget), 0755); err != nil {
			return err
		}
		rc, err := zf.Open()
		if err != nil {
			return err
		}
		out, err := os.OpenFile(absTarget, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
		if err != nil {
			rc.Close()
			return err
		}
		_, copyErr := io.Copy(out, io.LimitReader(rc, 2<<30))
		closeErr := out.Close()
		rc.Close()
		if copyErr != nil {
			return copyErr
		}
		if closeErr != nil {
			return closeErr
		}
	}
	return nil
}

func findFileNamed(root, name string) string {
	var found string
	_ = filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil || info == nil {
			return nil
		}
		if !info.IsDir() && strings.EqualFold(info.Name(), name) {
			found = path
			return filepath.SkipAll
		}
		return nil
	})
	return found
}

func findPortableSlicer() string {
	if installDir == "" {
		return ""
	}
	return findFileNamed(filepath.Join(installDir, "Slicer"), "prusa-slicer-console.exe")
}

func pathWithin(path, root string) bool {
	ap, err1 := filepath.Abs(path)
	ar, err2 := filepath.Abs(root)
	if err1 != nil || err2 != nil {
		return false
	}
	rel, err := filepath.Rel(ar, ap)
	return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(os.PathSeparator))
}
'''

if 'func startPortableSlicerBootstrap()' not in s:
    anchor = '\nfunc serve() {'
    if anchor not in s:
        raise SystemExit('serve anchor not found')
    s = s.replace(anchor, '\n' + portable_code + '\nfunc serve() {', 1)

handle_status_old = '''func handleStatus(w http.ResponseWriter, r *http.Request) {
\tif slicerPath == "" {
\t\tfindSlicer()
\t}
\tli, _ := fetchLatestInfo(2500 * time.Millisecond)
\tresp := statusResp{OK: slicerPath != "", BridgeVersion: bridgeVersion, SlicerFound: slicerPath != "", SlicerPath: slicerPath, SlicerGUI: slicerGUI, SlicerVersion: slicerVer, ProtocolRegistered: protocolRegistered(), WindowsRepair: true, RepairEngine: "Native WinRT Printing3DModel.RepairAsync", PID: os.Getpid(), UpdateSupported: true}'''
handle_status_new = '''func handleStatus(w http.ResponseWriter, r *http.Request) {
\tif slicerPath == "" {
\t\tfindSlicer()
\t\tif slicerPath == "" {
\t\t\tstartPortableSlicerBootstrap()
\t\t}
\t}
\tbooting, bootStatus, bootErr := slicerBootstrapSnapshot()
\tli, _ := fetchLatestInfo(2500 * time.Millisecond)
\tresp := statusResp{OK: slicerPath != "", BridgeVersion: bridgeVersion, SlicerFound: slicerPath != "", SlicerPath: slicerPath, SlicerGUI: slicerGUI, SlicerVersion: slicerVer, SlicerManaged: slicerManaged, SlicerBootstrapping: booting, SlicerBootstrapStatus: bootStatus, SlicerBootstrapError: bootErr, ProtocolRegistered: protocolRegistered(), WindowsRepair: true, RepairEngine: "Native WinRT Printing3DModel.RepairAsync", PID: os.Getpid(), UpdateSupported: true}'''
if handle_status_old in s:
    s = s.replace(handle_status_old, handle_status_new, 1)

msg_old = '''\tif slicerPath == "" {
\t\tresp.Message = "PrusaSlicer nebyl nalezen. Nastav SlicerPath v PrusaBridge.ini."
\t}'''
msg_new = '''\tif slicerPath == "" {
\t\tif booting {
\t\t\tresp.Message = bootStatus
\t\t} else if bootErr != "" {
\t\t\tresp.Message = "Portable PrusaSlicer se nepodařilo připravit: " + bootErr
\t\t} else {
\t\t\tresp.Message = "PrusaSlicer zatím není připravený. Bridge ho automaticky stáhne z oficiálního GitHub Releases."
\t\t}
\t}'''
if msg_old in s:
    s = s.replace(msg_old, msg_new, 1)

# If a request arrives while the first portable runtime is still downloading, trigger bootstrap and return a useful error instead of saying installation is required.
for func_name in ('handleRepair', 'handleSlice', 'handleOpen'):
    marker = f'func {func_name}(w http.ResponseWriter, r *http.Request) {{'
    pos = s.find(marker)
    if pos < 0:
        continue
    segment_end = s.find('\nfunc ', pos + len(marker))
    if segment_end < 0:
        segment_end = len(s)
    segment = s[pos:segment_end]
    old = '''\tif slicerPath == "" {
\t\tfindSlicer()
\t}
\tif slicerPath == "" {
\t\twriteErr(w, 500, "PrusaSlicer není dostupný.", "")
\t\treturn
\t}'''
    new = '''\tif slicerPath == "" {
\t\tfindSlicer()
\t\tif slicerPath == "" {
\t\t\tstartPortableSlicerBootstrap()
\t\t}
\t}
\tif slicerPath == "" {
\t\tbooting, status, bootErr := slicerBootstrapSnapshot()
\t\tdetail := status
\t\tif bootErr != "" { detail = bootErr }
\t\tif booting { writeErr(w, 503, "Portable PrusaSlicer se právě automaticky stahuje a připravuje.", detail) } else { writeErr(w, 500, "Portable PrusaSlicer není dostupný.", detail) }
\t\treturn
\t}'''
    if old in segment:
        segment = segment.replace(old, new, 1)
        s = s[:pos] + segment + s[segment_end:]

MAIN.write_text(s, encoding='utf-8')

h = INDEX.read_text(encoding='utf-8-sig')
h = h.replace('<div class="app-version" id="app-version">V3.14u</div>', '<div class="app-version" id="app-version">V3.14v</div>', 1)
h = h.replace("const PRINT3D_PRUSA_BRIDGE_EXPECTED='3.14s';", "const PRINT3D_PRUSA_BRIDGE_EXPECTED='3.14t';", 1)
h = h.replace('// 3D TISK — V3.14s · LOCAL PRUSASLICER BRIDGE', '// 3D TISK — V3.14t · SELF-CONTAINED PRUSASLICER BRIDGE', 1)
h = h.replace('<b>V3.14s · Native WinRT repair + automatické aktualizace</b>', '<b>V3.14t · Native WinRT repair + portable PrusaSlicer</b>', 1)
h = h.replace(
    '<div class="print3d-estimate-note" style="margin-top:9px"><b>V3.14s používá skutečný nainstalovaný PrusaSlicer na tomto Windows PC.</b> Web komunikuje pouze s <code>127.0.0.1:8091</code>. <b>V3.14s je potřeba jednou ručně spustit</b>, protože starší Bridge ještě neumí bezpečný self-update. Od V3.14s dál už tlačítko na webu umí verzi zkontrolovat a Bridge se při dostupné novější verzi aktualizuje automaticky.</div>',
    '<div class="print3d-estimate-note" style="margin-top:9px"><b>PrusaSlicer už nemusí být předem nainstalovaný.</b> Když ho Bridge nenajde, automaticky stáhne oficiální stabilní Windows ZIP přímo z GitHub Releases projektu Prusa3D, ověří jeho SHA-256 a rozbalí jej jako lokální portable runtime do <code>%LOCALAPPDATA%\\20-20-TOOLBOX\\PrusaBridge\\Slicer</code>. Stávající systémová instalace je stále podporovaná. Web komunikuje pouze s <code>127.0.0.1:8091</code>.</div>',
    1,
)

old_status = '''      box.className='print3d-health err';box.innerHTML=`<b>⚠ BRIDGE BĚŽÍ, ALE PRUSASLICER NENALEZEN</b><br>${escapeHtml(j.message||'Nastav cestu k prusa-slicer-console.exe v PrusaBridge.ini.')}`'''
new_status = '''      if(j.slicerBootstrapping){box.className='print3d-health warn';box.innerHTML=`<b>↓ PŘIPRAVUJI PORTABLE PRUSASLICER…</b><br>${escapeHtml(j.slicerBootstrapStatus||j.message||'Stahuji oficiální PrusaSlicer z GitHub Releases. První spuštění může chvíli trvat.')}`;setTimeout(()=>check3DPrintPrusaBridge(true),1800);return false}
      box.className='print3d-health err';box.innerHTML=`<b>⚠ PORTABLE PRUSASLICER SE NEPODAŘILO PŘIPRAVIT</b><br>${escapeHtml(j.slicerBootstrapError||j.message||'Zkontroluj připojení k internetu a zkus Bridge restartovat.')}`'''
if old_status in h:
    h = h.replace(old_status, new_status, 1)

old_ok = '''box.className='print3d-health ok';box.innerHTML=`<b>✓ PRUSASLICER + NATIVE WINRT REPAIR PŘIPOJEN</b><br>${escapeHtml(j.slicerVersion||'PrusaSlicer')} · Bridge ${escapeHtml(j.bridgeVersion||'')}${j.protocolRegistered?' · webové spuštění aktivní':''}${j.latestVersion?` · latest ${escapeHtml(j.latestVersion)}`:''}<br><b>Repair:</b> ${escapeHtml(j.repairEngine||'Native WinRT RepairAsync')}<br><span style="opacity:.75">${escapeHtml(j.slicerPath||'')}</span>`;'''
new_ok = '''box.className='print3d-health ok';box.innerHTML=`<b>✓ PRUSASLICER + NATIVE WINRT REPAIR PŘIPOJEN</b><br>${escapeHtml(j.slicerVersion||'PrusaSlicer')} · Bridge ${escapeHtml(j.bridgeVersion||'')}${j.slicerManaged?' · portable runtime':''}${j.protocolRegistered?' · webové spuštění aktivní':''}${j.latestVersion?` · latest ${escapeHtml(j.latestVersion)}`:''}<br><b>Repair:</b> ${escapeHtml(j.repairEngine||'Native WinRT RepairAsync')}<br><span style="opacity:.75">${escapeHtml(j.slicerPath||'')}</span>`;'''
if old_ok in h:
    h = h.replace(old_ok, new_ok, 1)

INDEX.write_text(h, encoding='utf-8')

if 'const bridgeVersion = "3.14t"' not in MAIN.read_text(encoding='utf-8'):
    raise SystemExit('Bridge 3.14t patch failed')
if 'startPortableSlicerBootstrap' not in MAIN.read_text(encoding='utf-8'):
    raise SystemExit('Portable bootstrap code missing')
if 'V3.14v' not in INDEX.read_text(encoding='utf-8'):
    raise SystemExit('Web V3.14v patch failed')
if "PRINT3D_PRUSA_BRIDGE_EXPECTED='3.14t'" not in INDEX.read_text(encoding='utf-8'):
    raise SystemExit('Bridge expected version patch failed')

print('V3.14v portable PrusaSlicer bootstrap patched')
