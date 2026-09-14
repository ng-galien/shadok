package gateway

import (
	"bytes"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRequestDiagnostics(t *testing.T) {
	var output bytes.Buffer
	previous := slog.Default()
	slog.SetDefault(slog.New(slog.NewJSONHandler(&output, nil)))
	defer slog.SetDefault(previous)
	handler := LogRequests(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "receiver unavailable", 503)
	}))
	request := httptest.NewRequest("POST", "/sessions/team/app/apply?token=hidden-query", strings.NewReader("hidden-upload"))
	request.Header.Set("Authorization", "Bearer hidden-token")
	handler.ServeHTTP(httptest.NewRecorder(), request)
	for _, want := range []string{"receiver unavailable", "/sessions/team/app/apply", "503", "duration"} {
		if !strings.Contains(output.String(), want) {
			t.Fatalf("missing %s: %s", want, output.String())
		}
	}
	for _, secret := range []string{"hidden-query", "hidden-upload", "hidden-token"} {
		if strings.Contains(output.String(), secret) {
			t.Fatalf("logged secret %s", secret)
		}
	}
}
