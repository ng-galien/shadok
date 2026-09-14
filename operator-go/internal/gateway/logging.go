package gateway

import (
	"log/slog"
	"net/http"
	"strings"
	"time"
)

// LogRequests records requests without logging headers, query parameters or uploads.
func LogRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		result := &diagnosticWriter{ResponseWriter: w}
		next.ServeHTTP(result, r)
		if result.status >= 400 {
			slog.Warn("sync request failed", "method", r.Method, "path", r.URL.EscapedPath(), "status", result.status, "duration", time.Since(started).String(), "error", strings.TrimSpace(result.message.String()))
		} else if r.URL.Path != "/healthz" && r.URL.Path != "/readyz" {
			slog.Info("sync request completed", "method", r.Method, "path", r.URL.EscapedPath(), "status", result.status, "duration", time.Since(started).String())
		}
	})
}

type diagnosticWriter struct {
	http.ResponseWriter
	status  int
	message strings.Builder
}

func (w *diagnosticWriter) WriteHeader(status int) {
	if w.status != 0 {
		return
	}
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}
func (w *diagnosticWriter) Write(b []byte) (int, error) {
	if w.status == 0 {
		w.WriteHeader(http.StatusOK)
	}
	if w.status >= 400 && w.message.Len() < 4096 {
		n := min(len(b), 4096-w.message.Len())
		w.message.Write(b[:n])
	}
	return w.ResponseWriter.Write(b)
}
