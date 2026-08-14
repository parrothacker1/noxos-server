package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestManifestHandler(t *testing.T) {
	handler := manifestHandler("builds/index.json")

	req := httptest.NewRequest(http.MethodGet, "/api/v1/sunfish/nightly/none", nil)
	rr := httptest.NewRecorder()

	handler(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rr.Code)
	}

	ct := rr.Header().Get("Content-Type")
	if ct != "application/json" {
		t.Errorf("expected Content-Type application/json, got %q", ct)
	}

	var resp manifestResponse
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatalf("response is not valid JSON: %v", err)
	}

	if len(resp.Response) != 1 {
		t.Fatalf("expected 1 build for sunfish/nightly, got %d", len(resp.Response))
	}

	b := resp.Response[0]
	if b.Device != "sunfish" {
		t.Errorf("expected device sunfish, got %q", b.Device)
	}
	if b.Type != "nightly" {
		t.Errorf("expected type nightly, got %q", b.Type)
	}
	if b.Filename == "" {
		t.Error("expected non-empty filename")
	}
	if b.SHA256 == "" {
		t.Error("expected non-empty sha256")
	}
	if b.URL == "" {
		t.Error("expected non-empty url")
	}
}

func TestManifestHandlerNoMatch(t *testing.T) {
	handler := manifestHandler("builds/index.json")

	req := httptest.NewRequest(http.MethodGet, "/api/v1/nonexistent-device/nightly/none", nil)
	rr := httptest.NewRecorder()

	handler(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rr.Code)
	}

	var resp manifestResponse
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatalf("response is not valid JSON: %v", err)
	}

	if len(resp.Response) != 0 {
		t.Fatalf("expected 0 builds for unknown device, got %d", len(resp.Response))
	}
}

func TestManifestHandlerBadPath(t *testing.T) {
	handler := manifestHandler("builds/index.json")

	req := httptest.NewRequest(http.MethodGet, "/api/v1/sunfish", nil)
	rr := httptest.NewRecorder()

	handler(rr, req)

	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d", rr.Code)
	}
}

func TestHealthz(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rr := httptest.NewRecorder()

	healthzHandler(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rr.Code)
	}
	if rr.Body.String() != "ok" {
		t.Errorf("expected body %q, got %q", "ok", rr.Body.String())
	}
}
