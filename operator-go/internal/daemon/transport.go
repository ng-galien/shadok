package daemon

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"shadok.org/operator/internal/syncer"
	"strings"
	"time"
)

func Deliver(ctx context.Context, d Destination, s *syncer.Snapshot) (syncer.Ack, error) {
	if d.URL == "" {
		return syncer.Ack{}, fmt.Errorf("HTTP sync URL required; no Kubernetes credentials are used")
	}
	endpoint := strings.TrimRight(d.URL, "/")
	if d.Session != "" {
		if d.Namespace == "" {
			return syncer.Ack{}, fmt.Errorf("namespace required")
		}
		endpoint += "/sessions/" + url.PathEscape(d.Namespace) + "/" + url.PathEscape(d.Session)
	} else if d.Deployment != "" {
		if d.Namespace == "" {
			return syncer.Ack{}, fmt.Errorf("namespace required")
		}
		endpoint += "/" + url.PathEscape(d.Namespace) + "/" + url.PathEscape(d.Deployment)
	}
	token := "" // Optional legacy local-test mechanism. The gateway contract requires no token.
	if d.TokenFile != "" {
		b, err := os.ReadFile(d.TokenFile)
		if err != nil {
			return syncer.Ack{}, err
		}
		token = strings.TrimSpace(string(b))
	}
	transport, err := httpTransport(d.CAFile)
	if err != nil {
		return syncer.Ack{}, err
	}
	defer transport.CloseIdleConnections()
	return syncer.Send(ctx, &http.Client{Timeout: 45 * time.Second, Transport: transport}, endpoint, token, s)
}

func httpTransport(caFile string) (*http.Transport, error) {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	if caFile != "" {
		roots, err := x509.SystemCertPool()
		if err != nil {
			roots = x509.NewCertPool()
		}
		pem, err := os.ReadFile(caFile)
		if err != nil {
			return nil, err
		}
		if !roots.AppendCertsFromPEM(pem) {
			return nil, fmt.Errorf("CA file has no certificates")
		}
		transport.TLSClientConfig = &tls.Config{RootCAs: roots, MinVersion: tls.VersionTLS12}
	}

	return transport, nil
}
