package service

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"hash"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func validID(s string) bool {
	if len(s) != 32 {
		return false
	}
	_, e := hex.DecodeString(s)
	return e == nil
}
func safeName(s string) bool {
	return len(s) > 0 && len(s) < 240 && s != "." && s != ".." && filepath.Base(s) == s && !strings.ContainsAny(s, "/\\\x00\n\r")
}
func (e *Engine) begin(r Request, owner string) (any, error) {
	if unfinishedJobs(e.state.Jobs) >= MaxJobs || len(r.Resources) < 1 || len(r.Resources) > 2 {
		return nil, errRequest
	}
	if !validQuality(r.Quality) || r.Account == "" {
		return nil, errRequest
	}
	seen := map[string]bool{}
	var total int64
	for _, f := range r.Resources {
		if !safeName(f.Name) || seen[strings.ToLower(f.Name)] || f.Size <= 0 || f.Size > 100<<30 {
			return nil, errRequest
		}
		seen[strings.ToLower(f.Name)] = true
		total += f.Size
	}
	idb := make([]byte, 16)
	if _, err := rand.Read(idb); err != nil {
		return nil, err
	}
	id := hex.EncodeToString(idb)
	if err := os.Mkdir(e.jobDir(id), 0700); err != nil {
		return nil, err
	}
	j := &Job{ID: id, Account: r.Account, Quality: r.Quality, Resources: r.Resources, State: "importing", Created: time.Now().Unix(), Timestamp: r.Timestamp, Total: total, Owner: owner}
	for _, f := range r.Resources {
		file, err := os.OpenFile(filepath.Join(e.jobDir(id), f.Name), os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
		if err != nil {
			_ = os.RemoveAll(e.jobDir(id))
			return nil, err
		}
		file.Close()
	}
	e.importHashes[id] = make([]hash.Hash, len(r.Resources))
	for i := range r.Resources {
		e.importHashes[id][i] = sha256.New()
	}
	e.state.Jobs = append(e.state.Jobs, j)
	e.jobsByID[id] = j
	if err := e.save(); err != nil {
		return nil, err
	}
	return map[string]any{"id": id}, nil
}
func (e *Engine) appendChunk(j *Job, r Request) error {
	if j.State != "importing" || r.Index < 0 || r.Index >= len(j.Resources) || len(r.Data) == 0 || len(r.Data) > MaxChunk {
		return errRequest
	}
	f, err := os.OpenFile(filepath.Join(e.jobDir(j.ID), j.Resources[r.Index].Name), os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		return err
	}
	if st.Size() != r.Offset || r.Offset+int64(len(r.Data)) > j.Resources[r.Index].Size {
		return errRequest
	}
	n, err := f.WriteAt(r.Data, r.Offset)
	if n > 0 {
		e.importHashes[j.ID][r.Index].Write(r.Data[:n])
	}
	if err == nil && n != len(r.Data) {
		err = io.ErrShortWrite
	}
	return err // Durability is required at seal, not each IPC chunk.
}
func (e *Engine) seal(j *Job) (any, error) {
	if j.State != "importing" {
		return nil, errRequest
	}
	h := sha256.New()
	fmt.Fprintf(h, "%s\x00%s\x00", j.Account, j.Quality)
	for index, res := range j.Resources {
		f, err := os.OpenFile(filepath.Join(e.jobDir(j.ID), res.Name), os.O_RDWR, 0600)
		if err != nil {
			return nil, err
		}
		st, err := f.Stat()
		if err != nil || st.Size() != res.Size {
			f.Close()
			return nil, errRequest
		}
		fmt.Fprintf(h, "%d\x00", res.Size)
		h.Write(e.importHashes[j.ID][index].Sum(nil))
		err = f.Sync()
		f.Close()
		if err != nil {
			return nil, err
		}
		if j.Timestamp > 0 {
			t := time.Unix(j.Timestamp, 0)
			if err = os.Chtimes(filepath.Join(e.jobDir(j.ID), res.Name), t, t); err != nil {
				return nil, err
			}
		}
	}
	fingerprint := hex.EncodeToString(h.Sum(nil))
	delete(e.importHashes, j.ID)
	for _, old := range e.state.Jobs {
		// Older builds could mark original completed from a saver hash match.
		// Do not reuse that unverified completion for a new original request.
		if j.Quality == "original" && old.State == "completed" && old.OriginalPolicy == 0 {
			continue
		}
		if old.ID != j.ID && old.Fingerprint == fingerprint && old.State != "cancelled" {
			j.State = "cancelled"
			if err := e.save(); err != nil {
				return nil, err
			}
			_ = os.RemoveAll(e.jobDir(j.ID))
			return map[string]any{"id": old.ID, "duplicate": true}, nil
		}
	}
	j.Fingerprint = fingerprint
	j.State = "pending"
	if err := e.save(); err != nil {
		return nil, err
	}
	return map[string]any{"id": j.ID}, nil
}
