from pathlib import Path

MAIN=Path('PrusaBridge/src/main.go')
INDEX=Path('index.html')

s=MAIN.read_text(encoding='utf-8-sig')

s=s.replace('const bridgeVersion = "3.14v"','const bridgeVersion = "3.14w"',1)

if '"crypto/rand"' not in s:
    s=s.replace('\t"context"\n\t"crypto/sha256"','\t"context"\n\t"crypto/rand"\n\t"crypto/sha256"',1)

handlers=r'''
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
	if r.Method == http.MethodOptions { w.WriteHeader(http.StatusNoContent); return }
	if r.Method != http.MethodPost { http.Error(w, "method not allowed", http.StatusMethodNotAllowed); return }

	r.Body = http.MaxBytesReader(w, r.Body, 300<<20)
	defer r.Body.Close()
	name := filepath.Base(strings.TrimSpace(r.Header.Get("X-File-Name")))
	if name == "." || name == "" { name = "sketchup-model.stl" }
	if strings.ToLower(filepath.Ext(name)) != ".stl" { http.Error(w, "only STL is accepted", http.StatusBadRequest); return }

	token, err := newSketchupToken()
	if err != nil { http.Error(w, err.Error(), http.StatusInternalServerError); return }
	dir := sketchupIncomingDir()
	if err := os.MkdirAll(dir, 0755); err != nil { http.Error(w, err.Error(), http.StatusInternalServerError); return }
	path := filepath.Join(dir, token+".stl")
	f, err := os.Create(path)
	if err != nil { http.Error(w, err.Error(), http.StatusInternalServerError); return }
	n, copyErr := io.Copy(f, r.Body)
	closeErr := f.Close()
	if copyErr != nil || closeErr != nil || n <= 0 {
		_ = os.Remove(path)
		if copyErr != nil { http.Error(w, copyErr.Error(), http.StatusBadRequest) } else { http.Error(w, "empty STL", http.StatusBadRequest) }
		return
	}
	_ = os.WriteFile(filepath.Join(dir, token+".name"), []byte(name), 0644)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"ok":true,"token":token,"name":name,"bytes":n})
}

func handleSketchupFile(w http.ResponseWriter, r *http.Request) {
	addSketchupCORS(w)
	if r.Method == http.MethodOptions { w.WriteHeader(http.StatusNoContent); return }
	if r.Method != http.MethodGet { http.Error(w, "method not allowed", http.StatusMethodNotAllowed); return }
	token := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("token")))
	if len(token) != 32 {
		http.Error(w, "invalid token", http.StatusBadRequest); return
	}
	for _, ch := range token { if !((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f')) { http.Error(w, "invalid token", http.StatusBadRequest); return } }
	dir := sketchupIncomingDir()
	path := filepath.Join(dir, token+".stl")
	b, err := os.ReadFile(path)
	if err != nil { http.Error(w, "model not found", http.StatusNotFound); return }
	name := "sketchup-model.stl"
	if nb, err := os.ReadFile(filepath.Join(dir, token+".name")); err == nil && strings.TrimSpace(string(nb)) != "" { name = filepath.Base(strings.TrimSpace(string(nb))) }
	w.Header().Set("Content-Type", "model/stl")
	w.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename="%s"`, strings.ReplaceAll(name, `"`, "")))
	w.Header().Set("X-File-Name", name)
	w.Header().Set("Cache-Control", "no-store")
	_, _ = w.Write(b)
	_ = os.Remove(path)
	_ = os.Remove(filepath.Join(dir, token+".name"))
}

'''
if 'func handleSketchupImport(' not in s:
    anchor='func serve() {'
    if anchor not in s: raise SystemExit('serve anchor not found')
    s=s.replace(anchor,handlers+anchor,1)

if 'mux.HandleFunc("/sketchup-import", handleSketchupImport)' not in s:
    anchor='\tmux.HandleFunc("/slice", handleSlice)'
    if anchor not in s: raise SystemExit('route anchor not found')
    s=s.replace(anchor,anchor+'\n\tmux.HandleFunc("/sketchup-import", handleSketchupImport)\n\tmux.HandleFunc("/sketchup-file", handleSketchupFile)',1)

for needle in ['const bridgeVersion = "3.14w"','func handleSketchupImport(','func handleSketchupFile(','mux.HandleFunc("/sketchup-import", handleSketchupImport)']:
    if needle not in s: raise SystemExit('SketchUp Bridge patch incomplete: '+needle)
MAIN.write_text(s,encoding='utf-8',newline='\n')

h=INDEX.read_text(encoding='utf-8-sig')
h=h.replace("PRINT3D_PRUSA_BRIDGE_EXPECTED='3.14v'","PRINT3D_PRUSA_BRIDGE_EXPECTED='3.14w'",1)
INDEX.write_text(h,encoding='utf-8',newline='\n')
print('V3.14w SketchUp handoff patched')
