// Command noxos-server serves NoxOS OTA update manifests and the signed
// OTA package files themselves. It has no build system, no signing, and
// no device management UI — those live in other NoxOS repos. This is just
// the update-check API + static file serving.
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strings"
)

// Build describes a single OTA package available for download, matching
// the shape returned by the manifest API.
type Build struct {
	Device      string `json:"device"`
	Type        string `json:"type"`
	Incremental string `json:"incremental"`
	Filename    string `json:"filename"`
	Timestamp   int64  `json:"timestamp"`
	Size        int64  `json:"size"`
	SHA256      string `json:"sha256"`
	Version     string `json:"version"`
	URL         string `json:"url"`
}

// index is the on-disk build metadata format loaded from builds/index.json.
type index struct {
	Builds []Build `json:"builds"`
}

// manifestResponse is what the /api/v1/{device}/{type}/{incremental}
// endpoint returns.
type manifestResponse struct {
	Response []Build `json:"response"`
}

func loadIndex(path string) (*index, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var idx index
	if err := json.Unmarshal(data, &idx); err != nil {
		return nil, err
	}
	return &idx, nil
}

// manifestHandler implements GET /api/v1/{device}/{type}/{incremental},
// following the LineageOS updater API shape: it returns the builds
// available for the given device/channel, excluding any build the client
// already has installed (matched by incremental).
func manifestHandler(indexPath string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		parts := strings.Split(strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/"), "/"), "/")
		if len(parts) != 3 || parts[0] == "" || parts[1] == "" || parts[2] == "" {
			http.Error(w, "expected /api/v1/{device}/{type}/{incremental}", http.StatusBadRequest)
			return
		}
		device, buildType, incremental := parts[0], parts[1], parts[2]

		idx, err := loadIndex(indexPath)
		if err != nil {
			http.Error(w, "could not load build index", http.StatusInternalServerError)
			return
		}

		resp := manifestResponse{Response: []Build{}}
		for _, b := range idx.Builds {
			if b.Device == device && b.Type == buildType && b.Incremental != incremental {
				resp.Response = append(resp.Response, b)
			}
		}

		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(resp); err != nil {
			log.Printf("encode manifest response: %v", err)
		}
	}
}

func healthzHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	w.Write([]byte("ok"))
}

func main() {
	addr := os.Getenv("NOXOS_SERVER_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	buildsDir := os.Getenv("NOXOS_BUILDS_DIR")
	if buildsDir == "" {
		buildsDir = "builds"
	}
	indexPath := buildsDir + "/index.json"

	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/", manifestHandler(indexPath))
	mux.HandleFunc("/healthz", healthzHandler)
	mux.Handle("/builds/", http.StripPrefix("/builds/", http.FileServer(http.Dir(buildsDir))))

	log.Printf("noxos-server listening on %s (builds dir: %s)", addr, buildsDir)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}
