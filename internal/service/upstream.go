package service

import (
	"app/backend"
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
)

var errRemoteComponentExists = backend.ErrGunshotRemoteComponentExists

func Initialize(root string) (*Engine, error) {
	e, err := Open(root, upload)
	if err != nil {
		return nil, err
	}
	if err = backend.LoadConfig(filepath.Join(root, "credentials.json")); err != nil {
		return nil, err
	}
	return e, nil
}
func accountExists(email string) bool {
	for _, a := range (&backend.ConfigManager{}).GetAccounts().Accounts {
		if a.Email == email {
			return true
		}
	}
	return false
}
func (e *Engine) accounts(r Request) (any, error) {
	g := &backend.ConfigManager{}
	switch r.Op {
	case "accounts":
		a := g.GetAccounts()
		return map[string]any{"accounts": a.Accounts, "selected": a.Selected, "nativeAuthorization": e.nativeAuthorization(a.Selected)}, nil
	case "account_native":
		if e.nativeRelay != nil {
			if err := e.nativeRelay.put(r.NativeID, r.Secret); err != nil {
				return nil, err
			}
		}
		err := g.AddNativeAccount(r.Account, r.NativeID)
		if err != nil && e.nativeRelay != nil {
			e.nativeRelay.clear()
		}
		return nil, err
	case "native_bearer":
		if e.nativeRelay == nil || backend.GunshotNativeAccountID(r.Account) != r.NativeID || r.NativeID == "" {
			return nil, errRequest
		}
		return nil, e.nativeRelay.put(r.NativeID, r.Secret)
	case "native_bearer_clear":
		if e.nativeRelay == nil {
			return nil, errRequest
		}
		e.nativeRelay.clear()
		return nil, nil
	case "account_add":
		if len(r.Secret) == 0 || len(r.Secret) > 32768 {
			return nil, errRequest
		}
		var err error
		if backend.LooksLikeAuthString(r.Secret) {
			err = g.AddCredentials(r.Secret)
		} else {
			_, err = g.AddGoogleAccountWithProxy(r.Secret, "")
		}
		return nil, err
	case "account_select":
		return nil, g.SelectAccount(r.Account)
	case "account_remove":
		for _, j := range e.state.Jobs {
			if j.Account == r.Account && j.State != "completed" && j.State != "cancelled" {
				return nil, errors.New("cancel account jobs first")
			}
		}
		err := g.RemoveCredentials(r.Account)
		if err == nil && e.nativeRelay != nil {
			e.nativeRelay.clear()
		}
		return nil, err
	}
	return nil, errRequest
}

type reporter struct {
	backend.NopReporter
	callback func(Progress)
	uploaded int64
	offset   int64
}

func (r *reporter) ThreadStatus(s backend.ThreadStatus) {
	phase := "preparing"
	switch s.Status {
	case "uploading":
		phase = "uploading"
	case "finalizing":
		phase = "committing"
	}
	// One reporter serves one work item. Upstream already aggregates Live Photo
	// components; phase-only notifications omit bytes and must preserve progress.
	if s.BytesTotal > 0 {
		r.uploaded = s.BytesUploaded
	}
	r.callback(Progress{State: phase, Uploaded: r.offset + r.uploaded})
}
func upload(ctx context.Context, paths []string, account, quality string, cb func(Progress)) (string, error) {
	opts := backend.UploadOptions{Api: backend.ApiOptions{Account: account, Saver: quality == "saver", UseQuota: quality == "quota"}, Threads: 1, ForceUpload: quality == "original", PairLivePhotos: len(paths) == 2, SkipIncompleteLivePhotos: true}
	if !rawJPEGPair(paths) {
		return backend.GunshotUpload(ctx, paths, opts, &reporter{callback: cb})
	}
	// RAW+JPEG are two independent photos, not a still/movie Live Photo pair.
	// Keep one durable job and report success only after both commits succeed.
	opts.PairLivePhotos = false
	var primaryKey string
	var completed int64
	for _, path := range paths {
		info, err := os.Stat(path)
		if err != nil {
			return "", err
		}
		key, err := backend.GunshotUpload(ctx, []string{path}, opts, &reporter{callback: cb, offset: completed})
		if err != nil {
			return "", err
		}
		if primaryKey == "" {
			primaryKey = key
		}
		completed += info.Size()
	}
	return primaryKey, nil
}

func rawJPEGPair(paths []string) bool {
	if len(paths) != 2 {
		return false
	}
	raw, rendered := 0, 0
	for _, path := range paths {
		switch strings.ToLower(filepath.Ext(path)) {
		case ".dng", ".cr2", ".cr3", ".nef", ".arw", ".orf", ".raf", ".rw2", ".pef", ".sr2":
			raw++
		case ".jpg", ".jpeg", ".heic", ".heif", ".png", ".tif", ".tiff", ".avif":
			rendered++
		}
	}
	return raw == 1 && rendered == 1
}
