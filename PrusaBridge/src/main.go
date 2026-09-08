package main

import (
	"bytes"
	"context"
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

const bridgeVersion = "3.14p"
const latestJSONURL = "https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/PrusaBridge/latest.json"
const listenAddr = "127.0.0.1:8091"

var (
	slicerPath   string
	slicerGUI    string
	slicerVer    string
	installDir   string
	repairHelper string
	updateMu     sync.Mutex
	runMu        sync.Mutex
)

type latestInfo struct {
	Version string `json:"version"`
	URL     string `json:"url"`
	SHA256  string `json:"sha256"`
}

//go:embed Win3DRepair.exe
var embeddedRepairHelper []byte

type statusResp struct {
	OK                 bool   `json:"ok"`
	BridgeVersion      string `json:"bridgeVersion"`
	SlicerFound        bool   `json:"slicerFound"`
	SlicerPath         string `json:"slicerPath,omitempty"`
	SlicerGUI          string `json:"slicerGUI,omitempty"`
	SlicerVersion      string `json:"slicerVersion,omitempty"`
	ProtocolRegistered bool   `json:"protocolRegistered"`
	WindowsRepair      bool   `json:"windowsRepair"`
	RepairEngine       string `json:"repairEngine,omitempty"`
	Message            string `json:"message,omitempty"`
	PID                int    `json:"pid"`
	LatestVersion      string `json:"latestVersion,omitempty"`
	UpdateAvailable    bool   `json:"updateAvailable"`
	UpdateSupported    bool   `json:"updateSupported"`
	DownloadURL        string `json:"downloadUrl,omitempty"`
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

func serve() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", handleRoot)
	mux.HandleFunc("/status", handleStatus)
	mux.HandleFunc("/repair", handleRepair)
	mux.HandleFunc("/slice", handleSlice)
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
		fmt.Fprintf(w, `<p class="ok"><b>✓ Bridge běží a PrusaSlicer byl nalezen.</b></p><p>%s</p><p>Repair engine: <b>Native WinRT Printing3DModel.RepairAsync</b> → PrusaSlicer.</p>`, htmlEscape(slicerPath))
	} else {
		fmt.Fprintf(w, `<p class="bad"><b>PrusaSlicer nebyl nalezen.</b></p><p>Nastav <code>SlicerPath=...</code> v <code>%s</code> a Bridge restartuj.</p>`, htmlEscape(filepath.Join(installDir, "PrusaBridge.ini")))
	}
	fmt.Fprint(w, `<p>Tuto stránku můžeš zavřít. Bridge poslouchá pouze na <code>127.0.0.1:8091</code>.</p>`)
}

func handleStatus(w http.ResponseWriter, r *http.Request) {
	if slicerPath == "" {
		findSlicer()
	}
	li, _ := fetchLatestInfo(2500 * time.Millisecond)
	resp := statusResp{OK: slicerPath != "", BridgeVersion: bridgeVersion, SlicerFound: slicerPath != "", SlicerPath: slicerPath, SlicerGUI: slicerGUI, SlicerVersion: slicerVer, ProtocolRegistered: protocolRegistered(), WindowsRepair: true, RepairEngine: "Native WinRT Printing3DModel.RepairAsync", PID: os.Getpid(), UpdateSupported: true}
	if li.Version != "" {
		resp.LatestVersion = li.Version
		resp.UpdateAvailable = li.Version != bridgeVersion
		resp.DownloadURL = li.URL
	}
	if slicerPath == "" {
		resp.Message = "PrusaSlicer nebyl nalezen. Nastav SlicerPath v PrusaBridge.ini."
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
	}
	if slicerPath == "" {
		writeErr(w, 500, "PrusaSlicer není dostupný.", "")
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
	}
	if slicerPath == "" {
		writeErr(w, 500, "PrusaSlicer není dostupný.", "")
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
	if out, err := runCmd(180*time.Second, slicerPath, "--export-3mf", "-o", input3MF, inputSTL); err != nil {
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
	if out, err := runCmd(180*time.Second, slicerPath, "--export-stl", "-o", fixedSTL, fixed3MF); err != nil {
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
		args = append(args, "--support-material", "1", "--support-material-buildplate-only", "1")
	case "everywhere":
		args = append(args, "--support-material", "1", "--support-material-buildplate-only", "0")
	default:
		args = append(args, "--support-material", "0")
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
	log, err := runCmd(10*time.Minute, slicerPath, args...)
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
