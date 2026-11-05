package service

import (
	"app/generated"
	"context"
	"crypto/sha1"
	"crypto/x509"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"google.golang.org/protobuf/proto"
)

func TestRAWJPEGUploadsBothAsIndependentPhotos(t *testing.T) {
	for _, quality := range []string{"original", "saver", "quota"} {
		for _, failRAW := range []bool{false, true} {
			t.Run(quality+map[bool]string{false: "/success", true: "/raw-commit-failure"}[failRAW], func(t *testing.T) {
				var mu sync.Mutex
				var committed []string
				server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					body, _ := io.ReadAll(r.Body)
					var reply proto.Message
					switch {
					case strings.HasSuffix(r.URL.Path, "/5084965799730810217"):
						reply = &generated.RemoteMatches{}
					case r.Method == http.MethodPost && r.URL.Path == "/data/upload/uploadmedia/interactive":
						w.Header().Set("X-GUploader-UploadID", "fixture-upload")
						reply = &generated.CommitToken{}
					case r.Method == http.MethodPut:
						hash := sha1.Sum(body)
						reply = &generated.CommitToken{Field1: 2, Field2: hash[:]}
					case strings.HasSuffix(r.URL.Path, "/16538846908252377752"):
						var commit generated.CommitUpload
						if err := proto.Unmarshal(body, &commit); err != nil {
							t.Error(err)
						}
						name := commit.GetField1().GetFileName()
						if name != "preview.JPG" && name != "original.DNG" {
							t.Errorf("unexpected photo: %q", name)
						}
						policy, model := int64(3), "Pixel XL"
						if quality == "saver" {
							policy, model = 1, "Pixel 2"
						} else if quality == "quota" {
							model = "Pixel 8"
						}
						if commit.GetField1().GetQuality() != policy || commit.GetField2().GetModel() != model {
							t.Error("RAW/JPEG upload lost the selected quality profile")
						}
						mu.Lock()
						committed = append(committed, name)
						mu.Unlock()
						reply = &generated.CreateMediaItemsResponse{}
						if !failRAW || name != "original.DNG" {
							reply = &generated.CreateMediaItemsResponse{Item: []*generated.CreateMediaItemResponseItem{{ResultItem: &generated.CreateMediaItemResult{MediaKey: name + "-key"}}}}
						}
					default:
						t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
						w.WriteHeader(http.StatusBadRequest)
						return
					}
					data, _ := proto.Marshal(reply)
					w.Write(data)
				}))
				defer server.Close()
				previous := http.DefaultTransport
				transport := previous.(*http.Transport).Clone()
				transport.Proxy = nil
				transport.TLSClientConfig = server.Client().Transport.(*http.Transport).TLSClientConfig.Clone()
				transport.TLSClientConfig.InsecureSkipVerify = false
				transport.TLSClientConfig.ServerName = "127.0.0.1"
				transport.TLSClientConfig.RootCAs = x509.NewCertPool()
				transport.TLSClientConfig.RootCAs.AddCert(server.Certificate())
				transport.DialContext = func(ctx context.Context, network, _ string) (net.Conn, error) {
					return (&net.Dialer{}).DialContext(ctx, network, server.Listener.Addr().String())
				}
				http.DefaultTransport = transport
				defer func() { http.DefaultTransport = previous; transport.CloseIdleConnections() }()
				e := relayEngine(t, nil)
				relayRequest(t, e, "googlephotos", Request{Op: "account_native", Account: "a@example.com", NativeID: "raw-jpeg-fixture", Secret: "synthetic-native-bearer"}, true)
				paths := []string{filepath.Join(e.root, "preview.JPG"), filepath.Join(e.root, "original.DNG")}
				for i, path := range paths {
					if err := os.WriteFile(path, []byte(strings.Repeat("x", 11+i*6)), 0600); err != nil {
						t.Fatal(err)
					}
				}
				var last Progress
				sawRAWOffset := false
				key, err := upload(context.Background(), paths, "a@example.com", quality, func(p Progress) {
					last = p
					if p.State == "uploading" && p.Uploaded == 11 {
						sawRAWOffset = true
					}
				})
				if failRAW {
					if err == nil || key != "" || last.State != "committing" {
						t.Fatalf("partial/unknown commit reported success: key=%q err=%v phase=%s", key, err, last.State)
					}
				} else if err != nil || key != "preview.JPG-key" {
					t.Fatalf("both uploads did not complete: key=%q err=%v", key, err)
				}
				mu.Lock()
				defer mu.Unlock()
				if strings.Join(committed, ",") != "preview.JPG,original.DNG" || !sawRAWOffset || last.Uploaded != 28 {
					t.Fatalf("wrong files or aggregate progress: %v, %+v", committed, last)
				}
				for _, path := range paths {
					if _, err := os.Stat(path); err != nil {
						t.Fatal("local resource removed before queue completion:", err)
					}
				}
			})
		}
	}
}

func TestRAWJPEGClassification(t *testing.T) {
	for _, tc := range []struct {
		paths []string
		pair  bool
	}{
		{[]string{"image.JPG", "image.DNG"}, true},
		{[]string{"image.NEF", "edited.HEIC"}, true},
		{[]string{"image.HEIC", "image.MOV"}, false},
		{[]string{"image.DNG"}, false},
		{[]string{"a.JPG", "b.JPG"}, false},
	} {
		if rawJPEGPair(tc.paths) != tc.pair {
			t.Fatal(tc)
		}
	}
	if got := diagnosticMediaType([]Resource{{Name: "preview.JPG"}, {Name: "original.DNG"}}); got != "raw_jpeg" {
		t.Fatal("RAW+JPEG misreported as Live Photo:", got)
	}
}
