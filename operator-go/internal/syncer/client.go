package syncer

import (
	"archive/tar"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
)

func Send(ctx context.Context, client *http.Client, url, token string, s *Snapshot) (Ack, error) {
	raw, _ := json.Marshal(s.Manifest)
	req, err := http.NewRequestWithContext(ctx, "POST", url+"/plan", bytes.NewReader(raw))
	if err != nil {
		return Ack{}, fmt.Errorf("plan: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	res, err := client.Do(req)
	if err != nil {
		return Ack{}, fmt.Errorf("plan: %w", err)
	}
	var p Plan
	err = decode(res, &p)
	if err != nil {
		return Ack{}, fmt.Errorf("plan: %w", err)
	}
	reader, writer := io.Pipe()
	done := make(chan error, 1)
	go func() {
		tw := tar.NewWriter(writer)
		err := tw.WriteHeader(&tar.Header{Name: "manifest.json", Mode: 0600, Size: int64(len(raw))})
		if err == nil {
			_, err = tw.Write(raw)
		}
		needed := map[string]bool{}
		for _, name := range p.Needed {
			needed[name] = true
		}
		for _, e := range s.Manifest.Files {
			if err != nil {
				break
			}
			if !needed[e.Name] {
				continue
			}
			err = tw.WriteHeader(&tar.Header{Name: e.Name, Mode: int64(e.Mode), Size: e.Size})
			if err != nil {
				break
			}
			var f *os.File
			f, err = os.Open(filepath.Join(s.Dir, filepath.FromSlash(e.Name)))
			if err == nil {
				_, err = io.Copy(tw, f)
				f.Close()
			}
		}
		if ce := tw.Close(); err == nil {
			err = ce
		}
		writer.CloseWithError(err)
		done <- err
	}()
	req, err = http.NewRequestWithContext(ctx, "POST", url+"/apply", reader)
	if err != nil {
		reader.CloseWithError(err)
		return Ack{}, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	res, err = client.Do(req)
	reader.Close()
	sendErr := <-done
	if err != nil {
		return Ack{}, err
	}
	if res.StatusCode != http.StatusOK {
		return Ack{}, fmt.Errorf("apply: %w", decode(res, nil))
	}
	if sendErr != nil {
		res.Body.Close()
		return Ack{}, fmt.Errorf("apply upload: %w", sendErr)
	}
	var ack Ack
	if err = decode(res, &ack); err != nil {
		return Ack{}, fmt.Errorf("apply: %w", err)
	}
	if !ack.Applied || ack.Revision != s.Manifest.Revision || ack.Epoch != p.Epoch {
		return Ack{}, fmt.Errorf("receiver changed or invalid ACK")
	}
	return ack, nil
}
func decode(res *http.Response, dest any) error {
	defer res.Body.Close()
	if res.StatusCode != 200 {
		b, _ := io.ReadAll(io.LimitReader(res.Body, 4096))
		return fmt.Errorf("sync HTTP %d: %s", res.StatusCode, b)
	}
	return json.NewDecoder(io.LimitReader(res.Body, 8<<20)).Decode(dest)
}
