package main

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	_ "embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

const bridgeVersion = "3.14w"
const latestJSONURL = "https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/PrusaBridge/latest.json"
const prusaLatestReleaseAPI = "https://api.github.com/repos/prusa3d/PrusaSlicer/releases/latest"
const prusaFallbackZipURL = "https://github.com/prusa3d/PrusaSlicer/releases/download/version_2.9.6/PrusaSlicer-2.9.6.zip"
const prusaFallbackZipSHA256 = "5aaf22e42f95accecfa122d23a835911f289ecc2ff606db3e83d637ddcc0a209"
const listenAddr = "127.0.0.1:8091"

var (
	slicerPath            string
	slicerGUI             string
	slicerVer             string
	installDir            string
	repairHelper          string
	updateMu              sync.Mutex
	runMu                 sync.Mutex
	slicerBootstrapMu     sync.Mutex
	slicerBootstrapping   bool
	slicerBootstrapStatus string
	slicerBootstrapError  string
	slicerManaged         bool
	slicerDataDir         string
	slicerDataMu          sync.Mutex
)

type latestInfo struct {
	Version string `json:"version"`
	URL     string `json:"url"`
	SHA256  string `json:"sha256"`
}

type prusaRelease struct {
	TagName string `json:"tag_name"`
	Name    string `json:"name"`
	Assets  []struct {
		Name               string `json:"name"`
		BrowserDownloadURL string `json:"browser_download_url"`
		Digest             string `json:"digest"`
		Size               int64  `json:"size"`
	} `json:"assets"`
}

//go:embed Win3DRepair.exe
var embeddedRepairHelper []byte

type statusResp struct {
	OK                    bool   `json:"ok"`
	BridgeVersion         string `json:"bridgeVersion"`
	SlicerFound           bool   `json:"slicerFound"`
	SlicerPath            string `json:"slicerPath,omitempty"`
	SlicerGUI             string `json:"slicerGUI,omitempty"`
	SlicerVersion         string `json:"slicerVersion,omitempty"`
	SlicerManaged         bool   `json:"slicerManaged"`
	SlicerBootstrapping   bool   `json:"slicerBootstrapping"`
	SlicerBootstrapStatus string `json:"slicerBootstrapStatus,omitempty"`
	SlicerBootstrapError  string `json:"slicerBootstrapError,omitempty"`
	ProtocolRegistered    bool   `json:"protocolRegistered"`
	WindowsRepair         bool   `json:"windowsRepair"`
	RepairEngine          string `json:"repairEngine,omitempty"`
	Message               string `json:"message,omitempty"`
	PID                   int    `json:"pid"`
	LatestVersion         string `json:"latestVersion,omitempty"`
	UpdateAvailable       bool   `json:"updateAvailable"`
	UpdateSupported       bool   `json:"updateSupported"`
	DownloadURL           string `json:"downloadUrl,omitempty"`
}

type SliceSettings struct {
	Printer          string  `json:"printer"`
	Material         string  `json:"material"`
	Nozzle           float64 `json:"nozzle"`
	LayerHeight      float64 `json:"layerHeight"`
	FirstLayer       float64 `json:"firstLayer"`
	Perimeters       int     `json:"perimeters"`
	Infill           int     `json:"infill"`
	InfillPattern    string  `json:"infillPattern"`
	Supports         string  `json:"supports"`
	Brim             float64 `json:"brim"`
	TopSolid         int     `json:"topSolid"`
	BottomSolid      int     `json:"bottomSolid"`
	Retract          float64 `json:"retract"`
	ZHop             float64 `json:"zHop"`
	SupportInterface int     `json:"supportInterface"`
	NozzleFirst      int     `json:"nozzleFirst"`
	NozzleTemp       int     `json:"nozzleTemp"`
	BedFirst         int     `json:"bedFirst"`
	BedTemp          int     `json:"bedTemp"`
	Fan              int     `json:"fan"`
	SpeedPerimeter   float64 `json:"speedPerimeter"`
	SpeedInfill      float64 `json:"speedInfill"`
	SpeedTravel      float64 `json:"speedTravel"`
	ScaleLabel       string  `json:"scaleLabel"`
	SourceMode       string  `json:"sourceMode"`
}

func main() {
	if runtime.GOOS != "windows" {
		fmt.Println("20-20 PrusaBridge is intended for Windows.")
	}
	var err error
	installDir, err = localInstallDir()
	if err != nil {
		fatal(err)
	}
	repairHelper = filepath.Join(installDir, "Win3DRepair.exe")

	args := os.Args[1:]
	if len(args) == 0 || (len(args) > 0 && strings.HasPrefix(strings.ToLower(args[0]), "toolbox-prusa://")) {
		if err := installAndLaunch(); err != nil {
			fatal(err)
		}
		return
	}
	if args[0] == "--install" {
		if err := installAndLaunch(); err != nil {
			fatal(err)
		}
		return
	}
	if args[0] == "--serve" {
		ensureInstalledArtifacts()
		registerProtocol()
		findSlicer()
		if slicerPath == "" {
			startPortableSlicerBootstrap()
		}
		if started, _ := maybeAutoUpdate(); started {
			return
		}
		serve()
		return
	}
	if args[0] == "--replace" && len(args) >= 3 {
		pid, _ := strconv.Atoi(args[1])
		if err := replaceRunningBridge(pid, args[2]); err != nil {
			fatal(err)
		}
		return
	}
	if err := installAndLaunch(); err != nil {
		fatal(err)
	}
}

func localInstallDir() (string, error) {
	root := os.Getenv("LOCALAPPDATA")
	if root == "" {
		return "", errors.New("LOCALAPPDATA is not available")
	}
	return filepath.Join(root, "20-20-TOOLBOX", "PrusaBridge"), nil
}

func installAndLaunch() error {
	if err := os.MkdirAll(installDir, 0755); err != nil {
		return err
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	exe, _ = filepath.Abs(exe)
	target := filepath.Join(installDir, "20-20-PrusaBridge.exe")

	// If an older Bridge owns port 8091, stop exactly that PID before replacing the installed EXE.
	if pid := bridgeListenerPID(); pid > 0 && pid != os.Getpid() {
		_ = killPID(pid)
		waitPIDGone(pid, 5*time.Second)
	}
	if !samePath(exe, target) {
		if err := copyFileRetry(exe, target, 20, 150*time.Millisecond); err != nil {
			return fmt.Errorf("copy bridge: %w", err)
		}
	}
	ensureInstalledArtifacts()
	if err := registerProtocolPath(target); err != nil {
		return err
	}
	cmd := exec.Command(target, "--serve")
	cmd.Dir = installDir
	hideWindow(cmd)
	if err := cmd.Start(); err != nil {
		return err
	}
	time.Sleep(700 * time.Millisecond)
	openBrowser("http://127.0.0.1:8091/")
	return nil
}

func ensureInstalledArtifacts() {
	_ = os.MkdirAll(installDir, 0755)
	if len(embeddedRepairHelper) > 0 {
		_ = os.WriteFile(repairHelper, embeddedRepairHelper, 0755)
	}
	ini := filepath.Join(installDir, "PrusaBridge.ini")
	if _, err := os.Stat(ini); os.IsNotExist(err) {
		_ = os.WriteFile(ini, []byte("# Optional override\r\n# SlicerPath=C:\\Program Files\\Prusa3D\\PrusaSlicer\\prusa-slicer-console.exe\r\n"), 0644)
	}
}

func registerProtocol() error {
	exe := filepath.Join(installDir, "20-20-PrusaBridge.exe")
	if _, err := os.Stat(exe); err != nil {
		current, _ := os.Executable()
		exe = current
	}
	return registerProtocolPath(exe)
}

func registerProtocolPath(exe string) error {
	commands := [][]string{
		{"add", `HKCU\Software\Classes\toolbox-prusa`, "/ve", "/d", "URL:20-20 PrusaBridge", "/f"},
		{"add", `HKCU\Software\Classes\toolbox-prusa`, "/v", "URL Protocol", "/d", "", "/f"},
		{"add", `HKCU\Software\Classes\toolbox-prusa\DefaultIcon`, "/ve", "/d", exe + ",0", "/f"},
		{"add", `HKCU\Software\Classes\toolbox-prusa\shell\open\command`, "/ve", "/d", fmt.Sprintf(`"%s" --serve "%%1"`, exe), "/f"},
	}
	for _, a := range commands {
		c := exec.Command("reg.exe", a...)
		hideWindow(c)
		if out, err := c.CombinedOutput(); err != nil {
			return fmt.Errorf("register protocol: %v: %s", err, strings.TrimSpace(string(out)))
		}
	}
	return nil
}

func protocolRegistered() bool {
	c := exec.Command("reg.exe", "query", `HKCU\Software\Classes\toolbox-prusa\shell\open\command`, "/ve")
	hideWindow(c)
	return c.Run() == nil
}

func pingBridge() bool {
	client := http.Client{Timeout: 500 * time.Millisecond}
	r, err := client.Get("http://127.0.0.1:8091/status")
	if err != nil {
		return false
	}
	defer r.Body.Close()
	return r.StatusCode == 200
}

func findSlicer() {
	slicerPath = ""
	slicerGUI = ""
	slicerVer = ""
	slicerManaged = false
	slicerDataDir = ""
	var candidates []string
	// ini override
	iniPaths := []string{filepath.Join(installDir, "PrusaBridge.ini")}
	if exe, err := os.Executable(); err == nil {
		iniPaths = append(iniPaths, filepath.Join(filepath.Dir(exe), "PrusaBridge.ini"))
	}
	for _, p := range iniPaths {
		if b, err := os.ReadFile(p); err == nil {
			for _, line := range strings.Split(string(b), "\n") {
				line = strings.TrimSpace(line)
				if strings.HasPrefix(strings.ToLower(line), "slicerpath=") {
					candidates = append(candidates, strings.Trim(strings.TrimSpace(strings.SplitN(line, "=", 2)[1]), `"`))
				}
			}
		}
	}
	if p := findPortableSlicer(); p != "" {
		candidates = append(candidates, p)
	}
	pf := os.Getenv("ProgramFiles")
	pfx86 := os.Getenv("ProgramFiles(x86)")
	la := os.Getenv("LOCALAPPDATA")
	roots := []string{pf, pfx86, filepath.Join(la, "Programs")}
	fixed := []string{
		filepath.Join(pf, "Prusa3D", "PrusaSlicer", "prusa-slicer-console.exe"),
		filepath.Join(pf, "PrusaSlicer", "prusa-slicer-console.exe"),
		filepath.Join(la, "Programs", "PrusaSlicer", "prusa-slicer-console.exe"),
	}
	candidates = append(candidates, fixed...)
	for _, root := range roots {
		if root == "" {
			continue
		}
		for _, base := range []string{filepath.Join(root, "Prusa3D"), root} {
			entries, _ := os.ReadDir(base)
			for _, e := range entries {
				if !e.IsDir() {
					continue
				}
				n := strings.ToLower(e.Name())
				if strings.Contains(n, "prusa") && strings.Contains(n, "slicer") {
					candidates = append(candidates, filepath.Join(base, e.Name(), "prusa-slicer-console.exe"))
				}
			}
		}
	}
	seen := map[string]bool{}
	for _, p := range candidates {
		if p == "" {
			continue
		}
		ap, _ := filepath.Abs(p)
		key := strings.ToLower(ap)
		if seen[key] {
			continue
		}
		seen[key] = true
		if st, err := os.Stat(ap); err == nil && !st.IsDir() {
			slicerPath = ap
			slicerManaged = pathWithin(ap, filepath.Join(installDir, "Slicer"))
			if slicerManaged {
				if err := ensureManagedSlicerData(ap); err != nil {
					slicerPath = ""
					slicerManaged = false
					slicerDataDir = ""
					continue
				}
			}
			slicerGUI = filepath.Join(filepath.Dir(ap), "prusa-slicer.exe")
			if _, err := os.Stat(slicerGUI); err != nil {
				slicerGUI = ap
			}
			out, _ := runCmd(20*time.Second, ap, "--version")
			slicerVer = strings.TrimSpace(firstNonEmptyLine(out))
			if slicerVer == "" {
				slicerVer = "PrusaSlicer"
			}
			return
		}
	}
}

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

func addSketchupCORS(w http.ResponseWriter) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type, X-File-Name, X-20-20-Source")
	w.Header().Set("Access-Control-Expose-Headers", "X-File-Name")
}

func newSketchupToken() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func sketchupIncomingDir() string {
	return filepath.Join(installDir, "SketchUpIncoming")
}

func handleSketchupImport(w http.ResponseWriter, r *http.Request) {
	addSketchupCORS(w)
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, 300<<20)
	defer r.Body.Close()
	name := filepath.Base(strings.TrimSpace(r.Header.Get("X-File-Name")))
	if name == "." || name == "" {
		name = "sketchup-model.stl"
	}
	if strings.ToLower(filepath.Ext(name)) != ".stl" {
		http.Error(w, "only STL is accepted", http.StatusBadRequest)
		return
	}

	token, err := newSketchupToken()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	dir := sketchupIncomingDir()
	if err := os.MkdirAll(dir, 0755); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	path := filepath.Join(dir, token+".stl")
	f, err := os.Create(path)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	n, copyErr := io.Copy(f, r.Body)
	closeErr := f.Close()
	if copyErr != nil || closeErr != nil || n <= 0 {
		_ = os.Remove(path)
		if copyErr != nil {
			http.Error(w, copyErr.Error(), http.StatusBadRequest)
		} else {
			http.Error(w, "empty STL", http.StatusBadRequest)
		}
		return
	}
	_ = os.WriteFile(filepath.Join(dir, token+".name"), []byte(name), 0644)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"ok": true, "token": token, "name": name, "bytes": n})
}

func handleSketchupFile(w http.ResponseWriter, r *http.Request) {
	addSketchupCORS(w)
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	token := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("token")))
	if len(token) != 32 {
		http.Error(w, "invalid token", http.StatusBadRequest)
		return
	}
	for _, ch := range token {
		if !((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f')) {
			http.Error(w, "invalid token", http.StatusBadRequest)
			return
		}
	}
	dir := sketchupIncomingDir()
	path := filepath.Join(dir, token+".stl")
	b, err := os.ReadFile(path)
	if err != nil {
		http.Error(w, "model not found", http.StatusNotFound)
		return
	}
	name := "sketchup-model.stl"
	if nb, err := os.ReadFile(filepath.Join(dir, token+".name")); err == nil && strings.TrimSpace(string(nb)) != "" {
		name = filepath.Base(strings.TrimSpace(string(nb)))
	}
	w.Header().Set("Content-Type", "model/stl")
	w.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename="%s"`, strings.ReplaceAll(name, `"`, "")))
	w.Header().Set("X-File-Name", name)
	w.Header().Set("Cache-Control", "no-store")
	_, _ = w.Write(b)
	_ = os.Remove(path)
	_ = os.Remove(filepath.Join(dir, token+".name"))
}

func serve() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", handleRoot)
	mux.HandleFunc("/status", handleStatus)
	mux.HandleFunc("/repair", handleRepair)
	mux.HandleFunc("/slice", handleSlice)
	mux.HandleFunc("/sketchup-import", handleSketchupImport)
	mux.HandleFunc("/sketchup-file", handleSketchupFile)
	mux.HandleFunc("/open", handleOpen)
	mux.HandleFunc("/update", handleUpdate)
	srv := &http.Server{Addr: listenAddr, Handler: cors(mux), ReadHeaderTimeout: 10 * time.Second, ReadTimeout: 20 * time.Minute, WriteTimeout: 20 * time.Minute}
	fmt.Println("20-20 PrusaBridge", bridgeVersion, "listening on", listenAddr)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		fatal(err)
	}
}

func cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		w.Header().Set("Access-Control-Expose-Headers", "X-PrusaSlicer-Version,X-Prusa-Repair-Mode,X-Prusa-Slice-Mode,X-Repair-Engine")
		w.Header().Set("Access-Control-Allow-Private-Network", "true")
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	findSlicer()
	ok := slicerPath != ""
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprintf(w, `<!doctype html><meta charset="utf-8"><title>20-20 PrusaBridge</title><style>body{font:15px system-ui;margin:32px;max-width:850px}code{background:#eee;padding:2px 5px} .ok{color:#167a39}.bad{color:#b42318}</style><h1>20-20 PrusaBridge %s</h1>`, bridgeVersion)
	if ok {
		if slicerManaged {
			fmt.Fprintf(w, `<p class="ok"><b>✓ Bridge běží s vlastním portable PrusaSlicerem.</b></p><p>Samostatná instalace PrusaSliceru není potřeba.</p><p>%s</p><p>Repair engine: <b>Native WinRT Printing3DModel.RepairAsync</b> → PrusaSlicer.</p>`, htmlEscape(slicerPath))
		} else {
			fmt.Fprintf(w, `<p class="ok"><b>✓ Bridge běží a PrusaSlicer byl nalezen.</b></p><p>%s</p><p>Repair engine: <b>Native WinRT Printing3DModel.RepairAsync</b> → PrusaSlicer.</p>`, htmlEscape(slicerPath))
		}
	} else {
		fmt.Fprintf(w, `<p class="bad"><b>PrusaSlicer nebyl nalezen.</b></p><p>Nastav <code>SlicerPath=...</code> v <code>%s</code> a Bridge restartuj.</p>`, htmlEscape(filepath.Join(installDir, "PrusaBridge.ini")))
	}
	fmt.Fprint(w, `<p>Tuto stránku můžeš zavřít. Bridge poslouchá pouze na <code>127.0.0.1:8091</code>.</p>`)
}

func handleStatus(w http.ResponseWriter, r *http.Request) {
	if slicerPath == "" {
		findSlicer()
		if slicerPath == "" {
			startPortableSlicerBootstrap()
		}
	}
	booting, bootStatus, bootErr := slicerBootstrapSnapshot()
	li, _ := fetchLatestInfo(2500 * time.Millisecond)
	resp := statusResp{OK: slicerPath != "", BridgeVersion: bridgeVersion, SlicerFound: slicerPath != "", SlicerPath: slicerPath, SlicerGUI: slicerGUI, SlicerVersion: slicerVer, SlicerManaged: slicerManaged, SlicerBootstrapping: booting, SlicerBootstrapStatus: bootStatus, SlicerBootstrapError: bootErr, ProtocolRegistered: protocolRegistered(), WindowsRepair: true, RepairEngine: "Native WinRT Printing3DModel.RepairAsync", PID: os.Getpid(), UpdateSupported: true}
	if li.Version != "" {
		resp.LatestVersion = li.Version
		resp.UpdateAvailable = li.Version != bridgeVersion
		resp.DownloadURL = li.URL
	}
	if slicerPath != "" && slicerManaged {
		resp.Message = "Portable PrusaSlicer je připravený. Samostatná instalace PrusaSliceru není potřeba."
	}
	if slicerPath == "" {
		if booting {
			resp.Message = bootStatus
		} else if bootErr != "" {
			resp.Message = "Portable PrusaSlicer se nepodařilo připravit: " + bootErr
		} else {
			resp.Message = "PrusaSlicer zatím není připravený. Bridge ho automaticky stáhne z oficiálního GitHub Releases."
		}
	}
	writeJSON(w, http.StatusOK, resp)
}

func handleRepair(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST only", 405)
		return
	}
	if slicerPath == "" {
		findSlicer()
		if slicerPath == "" {
			startPortableSlicerBootstrap()
		}
	}
	if slicerPath == "" {
		booting, status, bootErr := slicerBootstrapSnapshot()
		detail := status
		if bootErr != "" {
			detail = bootErr
		}
		if booting {
			writeErr(w, 503, "Portable PrusaSlicer se právě automaticky stahuje a připravuje.", detail)
		} else {
			writeErr(w, 500, "Portable PrusaSlicer není dostupný.", detail)
		}
		return
	}
	data, err := io.ReadAll(io.LimitReader(r.Body, 500<<20))
	if err != nil {
		writeErr(w, 500, "STL se nepodařilo načíst.", err.Error())
		return
	}
	if len(data) < 84 {
		writeErr(w, 400, "STL je prázdný nebo příliš malý.", "")
		return
	}
	runMu.Lock()
	defer runMu.Unlock()
	out, mode, err := repairWithWindows(data)
	if err != nil {
		writeErr(w, 500, "Windows/PrusaSlicer repair selhal.", err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/sla")
	w.Header().Set("X-PrusaSlicer-Version", slicerVer)
	w.Header().Set("X-Prusa-Repair-Mode", mode)
	w.Header().Set("X-Repair-Engine", "Native WinRT Printing3DModel.RepairAsync")
	w.Write(out)
}

func handleSlice(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST only", 405)
		return
	}
	if slicerPath == "" {
		findSlicer()
		if slicerPath == "" {
			startPortableSlicerBootstrap()
		}
	}
	if slicerPath == "" {
		booting, status, bootErr := slicerBootstrapSnapshot()
		detail := status
		if bootErr != "" {
			detail = bootErr
		}
		if booting {
			writeErr(w, 503, "Portable PrusaSlicer se právě automaticky stahuje a připravuje.", detail)
		} else {
			writeErr(w, 500, "Portable PrusaSlicer není dostupný.", detail)
		}
		return
	}
	if err := r.ParseMultipartForm(520 << 20); err != nil {
		writeErr(w, 400, "Neplatný upload pro slicing.", err.Error())
		return
	}
	file, _, err := r.FormFile("file")
	if err != nil {
		writeErr(w, 400, "Chybí STL soubor.", err.Error())
		return
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, 500<<20))
	if err != nil {
		writeErr(w, 500, "STL se nepodařilo načíst.", err.Error())
		return
	}
	var settings SliceSettings
	if s := r.FormValue("settings"); s != "" {
		_ = json.Unmarshal([]byte(s), &settings)
	}
	runMu.Lock()
	defer runMu.Unlock()
	repaired, repairMode, err := repairWithWindows(data)
	if err != nil {
		writeErr(w, 500, "Windows repair před slicingem selhal.", err.Error())
		return
	}
	gcode, sliceMode, err := sliceWithPrusa(repaired, settings)
	if err != nil {
		writeErr(w, 500, "PrusaSlicer slicing selhal.", err.Error())
		return
	}
	w.Header().Set("Content-Type", "text/x-gcode; charset=utf-8")
	w.Header().Set("X-PrusaSlicer-Version", slicerVer)
	w.Header().Set("X-Prusa-Repair-Mode", repairMode)
	w.Header().Set("X-Prusa-Slice-Mode", sliceMode)
	w.Header().Set("X-Repair-Engine", "Native WinRT Printing3DModel.RepairAsync")
	w.Write(gcode)
}

func handleOpen(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST only", 405)
		return
	}
	if slicerGUI == "" {
		findSlicer()
	}
	if slicerGUI == "" {
		writeErr(w, 500, "PrusaSlicer GUI nebyl nalezen.", "")
		return
	}
	data, err := io.ReadAll(io.LimitReader(r.Body, 500<<20))
	if err != nil {
		writeErr(w, 500, "STL se nepodařilo načíst.", err.Error())
		return
	}
	dir := filepath.Join(os.TempDir(), "20-20-PrusaBridge-open")
	_ = os.MkdirAll(dir, 0755)
	path := filepath.Join(dir, fmt.Sprintf("toolbox_%d.stl", time.Now().UnixNano()))
	if err := os.WriteFile(path, data, 0644); err != nil {
		writeErr(w, 500, "STL nelze uložit.", err.Error())
		return
	}
	c := exec.Command(slicerGUI, path)
	hideWindow(c)
	if err := c.Start(); err != nil {
		writeErr(w, 500, "PrusaSlicer GUI se nepodařilo spustit.", err.Error())
		return
	}
	writeJSON(w, 200, map[string]any{"ok": true})
}

func repairWithWindows(stl []byte) ([]byte, string, error) {
	dir, err := os.MkdirTemp("", "20-20-prusabridge-repair-")
	if err != nil {
		return nil, "", err
	}
	defer os.RemoveAll(dir)
	inputSTL := filepath.Join(dir, "input.stl")
	input3MF := filepath.Join(dir, "input.3mf")
	fixed3MF := filepath.Join(dir, "fixed.3mf")
	fixedSTL := filepath.Join(dir, "fixed.stl")
	if err := os.WriteFile(inputSTL, stl, 0644); err != nil {
		return nil, "", err
	}
	if out, err := runSlicer(180*time.Second, "--export-3mf", "-o", input3MF, inputSTL); err != nil {
		return nil, "", fmt.Errorf("STL→3MF: %v\n%s", err, trimLog(out))
	}
	if _, err := os.Stat(repairHelper); err != nil {
		ensureInstalledArtifacts()
	}
	if out, err := runCmd(300*time.Second, repairHelper, input3MF, fixed3MF); err != nil {
		return nil, "", fmt.Errorf("Native Windows RepairAsync: %v\n%s", err, trimLog(out))
	}
	if _, err := os.Stat(fixed3MF); err != nil {
		return nil, "", fmt.Errorf("Windows RepairAsync nevytvořil 3MF: %w", err)
	}
	if out, err := runSlicer(180*time.Second, "--export-stl", "-o", fixedSTL, fixed3MF); err != nil {
		return nil, "", fmt.Errorf("3MF→STL: %v\n%s", err, trimLog(out))
	}
	b, err := os.ReadFile(fixedSTL)
	if err != nil {
		return nil, "", err
	}
	if len(b) < 84 {
		return nil, "", errors.New("opravený STL je prázdný")
	}
	return b, "Native WinRT RepairAsync (typed C++ helper)", nil
}

func sliceWithPrusa(stl []byte, s SliceSettings) ([]byte, string, error) {
	dir, err := os.MkdirTemp("", "20-20-prusabridge-slice-")
	if err != nil {
		return nil, "", err
	}
	defer os.RemoveAll(dir)
	input := filepath.Join(dir, "repaired.stl")
	outG := filepath.Join(dir, "output.gcode")
	if err := os.WriteFile(input, stl, 0644); err != nil {
		return nil, "", err
	}
	printer := "Original Prusa i3 MK3S & MK3S+"
	printProfile := closestPrintProfile(s.LayerHeight)
	args := []string{"-g", "--printer-profile", printer, "--print-profile", printProfile, "-o", outG}
	// CLI material profile is unreliable on some single-material versions. Use it as hint, then override actual temperatures below.
	if mat := materialProfile(s.Material); mat != "" {
		args = append(args, "--material-profile", mat)
	}
	add := func(flag, value string) {
		if value != "" {
			args = append(args, flag, value)
		}
	}
	if s.LayerHeight > 0 {
		add("--layer-height", f(s.LayerHeight))
	}
	if s.FirstLayer > 0 {
		add("--first-layer-height", f(s.FirstLayer))
	}
	if s.Perimeters > 0 {
		add("--perimeters", strconv.Itoa(s.Perimeters))
	}
	if s.Infill >= 0 {
		add("--fill-density", fmt.Sprintf("%d%%", clampInt(s.Infill, 0, 100)))
	}
	if p := cleanPattern(s.InfillPattern); p != "" {
		add("--fill-pattern", p)
	}
	if s.TopSolid > 0 {
		add("--top-solid-layers", strconv.Itoa(s.TopSolid))
	}
	if s.BottomSolid > 0 {
		add("--bottom-solid-layers", strconv.Itoa(s.BottomSolid))
	}
	if s.Brim > 0 {
		add("--brim-width", f(s.Brim))
	}
	switch strings.ToLower(s.Supports) {
	case "buildplate":
		args = append(args, "--support-material", "--support-material-buildplate-only")
	case "everywhere":
		args = append(args, "--support-material")
	default:
		// support disabled: no boolean CLI flag
	}
	if s.SupportInterface >= 0 {
		add("--support-material-interface-layers", strconv.Itoa(s.SupportInterface))
	}
	if s.Retract > 0 {
		add("--retract-length", f(s.Retract))
	}
	if s.ZHop >= 0 {
		add("--retract-lift", f(s.ZHop))
	}
	if s.SpeedPerimeter > 0 {
		add("--perimeter-speed", f(s.SpeedPerimeter))
	}
	if s.SpeedInfill > 0 {
		add("--infill-speed", f(s.SpeedInfill))
	}
	if s.SpeedTravel > 0 {
		add("--travel-speed", f(s.SpeedTravel))
	}
	if s.NozzleTemp > 0 {
		add("--temperature", strconv.Itoa(s.NozzleTemp))
	}
	if s.NozzleFirst > 0 {
		add("--first-layer-temperature", strconv.Itoa(s.NozzleFirst))
	}
	if s.BedTemp > 0 {
		add("--bed-temperature", strconv.Itoa(s.BedTemp))
	}
	if s.BedFirst > 0 {
		add("--first-layer-bed-temperature", strconv.Itoa(s.BedFirst))
	}
	args = append(args, input)
	log, err := runSlicer(10*time.Minute, args...)
	if err != nil {
		return nil, "", fmt.Errorf("%v\n%s", err, trimLog(log))
	}
	g, err := os.ReadFile(outG)
	if err != nil {
		return nil, "", fmt.Errorf("G-code nebyl vytvořen: %w\n%s", err, trimLog(log))
	}
	if len(g) < 300 {
		return nil, "", errors.New("PrusaSlicer vytvořil podezřele krátký G-code")
	}
	mode := fmt.Sprintf("Windows RepairAsync → %s → %s", printer, printProfile)
	return g, mode, nil
}

func closestPrintProfile(h float64) string {
	if h <= 0 {
		h = .20
	}
	switch {
	case h <= .11:
		return "0.10mm DETAIL @MK3"
	case h <= .17:
		return "0.15mm QUALITY @MK3"
	case h <= .24:
		return "0.20mm QUALITY @MK3"
	default:
		return "0.30mm DRAFT @MK3"
	}
}
func materialProfile(m string) string {
	switch strings.ToUpper(strings.TrimSpace(m)) {
	case "PLA":
		return "Prusament PLA"
	case "PETG":
		return "Prusament PETG"
	case "ASA":
		return "Prusament ASA"
	case "ABS":
		return "Generic ABS"
	default:
		return ""
	}
}
func cleanPattern(p string) string {
	p = strings.ToLower(strings.TrimSpace(p))
	switch p {
	case "gyroid", "grid", "rectilinear":
		return p
	}
	return "gyroid"
}

func hideWindow(c *exec.Cmd) {
	c.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
}
func runCmd(timeout time.Duration, name string, args ...string) (string, error) {
	ctx, cancel := contextWithTimeout(timeout)
	defer cancel()
	c := exec.CommandContext(ctx, name, args...)
	hideWindow(c)
	var buf bytes.Buffer
	c.Stdout = &buf
	c.Stderr = &buf
	err := c.Run()
	if ctx.Err() != nil {
		return buf.String(), fmt.Errorf("timeout after %s", timeout)
	}
	return buf.String(), err
}

// tiny context wrapper kept local so bridge has no external deps
func contextWithTimeout(d time.Duration) (ctx context.Context, cancel context.CancelFunc) {
	return context.WithTimeout(context.Background(), d)
}

func f(v float64) string { return strconv.FormatFloat(v, 'f', 3, 64) }
func clampInt(v, a, b int) int {
	if v < a {
		return a
	}
	if v > b {
		return b
	}
	return v
}
func trimLog(s string) string {
	s = strings.TrimSpace(s)
	if len(s) > 5000 {
		s = s[len(s)-5000:]
	}
	return s
}
func firstNonEmptyLine(s string) string {
	for _, l := range strings.Split(s, "\n") {
		l = strings.TrimSpace(l)
		if l != "" {
			return l
		}
	}
	return ""
}
func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	_, e := io.Copy(out, in)
	ce := out.Close()
	if e != nil {
		return e
	}
	return ce
}
func samePath(a, b string) bool {
	aa, _ := filepath.Abs(a)
	bb, _ := filepath.Abs(b)
	return strings.EqualFold(filepath.Clean(aa), filepath.Clean(bb))
}
func openBrowser(url string) {
	c := exec.Command("rundll32.exe", "url.dll,FileProtocolHandler", url)
	hideWindow(c)
	_ = c.Start()
}
func fatal(err error) { fmt.Fprintln(os.Stderr, err); time.Sleep(2 * time.Second); os.Exit(1) }
func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}
func writeErr(w http.ResponseWriter, code int, msg, detail string) {
	writeJSON(w, code, map[string]any{"error": msg, "detail": detail})
}
func htmlEscape(s string) string {
	r := strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", `"`, "&quot;")
	return r.Replace(s)
}

func readMultipartFile(f multipart.File) ([]byte, error) { return io.ReadAll(f) }

func handleUpdate(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST only", 405)
		return
	}
	updateMu.Lock()
	defer updateMu.Unlock()
	li, err := fetchLatestInfo(8 * time.Second)
	if err != nil {
		writeErr(w, 500, "Kontrola nové verze selhala.", err.Error())
		return
	}
	if li.Version == "" || li.Version == bridgeVersion {
		writeJSON(w, 200, map[string]any{"ok": true, "updated": false, "version": bridgeVersion})
		return
	}
	started, err := startSelfUpdate(li)
	if err != nil {
		writeErr(w, 500, "Automatická aktualizace Bridge selhala.", err.Error())
		return
	}
	writeJSON(w, 200, map[string]any{"ok": true, "updated": started, "from": bridgeVersion, "to": li.Version})
	if started {
		go func() { time.Sleep(250 * time.Millisecond); os.Exit(0) }()
	}
}

func fetchLatestInfo(timeout time.Duration) (latestInfo, error) {
	var li latestInfo
	client := &http.Client{Timeout: timeout}
	r, err := client.Get(latestJSONURL)
	if err != nil {
		return li, err
	}
	defer r.Body.Close()
	if r.StatusCode != 200 {
		return li, fmt.Errorf("latest.json HTTP %d", r.StatusCode)
	}
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&li); err != nil {
		return li, err
	}
	li.Version = strings.TrimSpace(li.Version)
	li.URL = strings.TrimSpace(li.URL)
	li.SHA256 = strings.ToLower(strings.TrimSpace(li.SHA256))
	if li.Version == "" || li.URL == "" || len(li.SHA256) != 64 {
		return latestInfo{}, errors.New("latest.json je neplatný")
	}
	return li, nil
}

func maybeAutoUpdate() (bool, error) {
	li, err := fetchLatestInfo(2500 * time.Millisecond)
	if err != nil {
		return false, nil
	}
	if li.Version == bridgeVersion {
		return false, nil
	}
	return startSelfUpdate(li)
}

func startSelfUpdate(li latestInfo) (bool, error) {
	target := filepath.Join(installDir, "20-20-PrusaBridge.exe")
	tmp := filepath.Join(installDir, "20-20-PrusaBridge.update.exe")
	client := &http.Client{Timeout: 2 * time.Minute}
	r, err := client.Get(li.URL)
	if err != nil {
		return false, err
	}
	defer r.Body.Close()
	if r.StatusCode != 200 {
		return false, fmt.Errorf("download HTTP %d", r.StatusCode)
	}
	b, err := io.ReadAll(io.LimitReader(r.Body, 100<<20))
	if err != nil {
		return false, err
	}
	sum := sha256.Sum256(b)
	got := hex.EncodeToString(sum[:])
	if got != li.SHA256 {
		return false, fmt.Errorf("SHA256 nesedí: %s", got)
	}
	if err := os.WriteFile(tmp, b, 0755); err != nil {
		return false, err
	}
	cmd := exec.Command(tmp, "--replace", strconv.Itoa(os.Getpid()), target)
	cmd.Dir = installDir
	hideWindow(cmd)
	if err := cmd.Start(); err != nil {
		return false, err
	}
	return true, nil
}

func replaceRunningBridge(oldPID int, target string) error {
	// Let the /update HTTP response reach the browser before the old server is terminated.
	time.Sleep(700 * time.Millisecond)
	if oldPID > 0 && oldPID != os.Getpid() {
		_ = killPID(oldPID)
		waitPIDGone(oldPID, 5*time.Second)
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	if err := copyFileRetry(exe, target, 30, 150*time.Millisecond); err != nil {
		return err
	}
	cmd := exec.Command(target, "--serve")
	cmd.Dir = filepath.Dir(target)
	hideWindow(cmd)
	return cmd.Start()
}

func bridgeListenerPID() int {
	c := exec.Command("netstat.exe", "-ano", "-p", "tcp")
	hideWindow(c)
	out, err := c.Output()
	if err != nil {
		return 0
	}
	for _, ln := range strings.Split(string(out), "\n") {
		f := strings.Fields(ln)
		if len(f) < 5 {
			continue
		}
		if strings.HasSuffix(f[1], ":8091") && strings.EqualFold(f[3], "LISTENING") {
			if p, e := strconv.Atoi(f[4]); e == nil {
				return p
			}
		}
	}
	return 0
}
func killPID(pid int) error {
	c := exec.Command("taskkill.exe", "/PID", strconv.Itoa(pid), "/F")
	hideWindow(c)
	return c.Run()
}
func waitPIDGone(pid int, timeout time.Duration) {
	end := time.Now().Add(timeout)
	for time.Now().Before(end) {
		c := exec.Command("tasklist.exe", "/FI", fmt.Sprintf("PID eq %d", pid))
		hideWindow(c)
		b, _ := c.Output()
		if !strings.Contains(string(b), strconv.Itoa(pid)) {
			return
		}
		time.Sleep(150 * time.Millisecond)
	}
}
func copyFileRetry(src, dst string, tries int, delay time.Duration) error {
	var last error
	for i := 0; i < tries; i++ {
		if err := copyFile(src, dst); err == nil {
			return nil
		} else {
			last = err
		}
		time.Sleep(delay)
	}
	return last
}
