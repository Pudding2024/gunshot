package service

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
)

func atomicJSON(path string, v any) error {
	b, e := json.Marshal(v)
	if e != nil {
		return e
	}
	d := filepath.Dir(path)
	f, e := os.CreateTemp(d, ".write-*")
	if e != nil {
		return e
	}
	defer os.Remove(f.Name())
	if _, e = f.Write(b); e == nil {
		e = f.Sync()
	}
	ce := f.Close()
	if e != nil {
		return e
	}
	if ce != nil {
		return ce
	}
	if e = os.Rename(f.Name(), path); e != nil {
		return e
	}
	df, e := os.Open(d)
	if e != nil {
		return e
	}
	defer df.Close()
	return df.Sync()
}
func (e *Engine) save() error {
	err := atomicJSON(filepath.Join(e.root, "state.json"), e.state)
	if err != nil {
		e.fault = true
	}
	return err
}
func validateState(s State) error {
	if unfinishedJobs(s.Jobs) > MaxJobs {
		return errors.New("too many unfinished jobs")
	}
	seen := map[string]bool{}
	states := map[string]bool{"importing": true, "pending": true, "preparing": true, "uploading": true, "committing": true, "completed": true, "failed": true, "cancelled": true}
	for _, j := range s.Jobs {
		if j == nil || !validID(j.ID) || seen[j.ID] || !states[j.State] || !validQuality(j.Quality) || j.Account == "" || len(j.Resources) < 1 || len(j.Resources) > 2 || j.Attempts < 0 {
			return errors.New("invalid persisted job")
		}
		if j.Owner != "photos" && j.Owner != "googlephotos" {
			return errors.New("invalid job owner")
		}
		seen[j.ID] = true
		names := map[string]bool{}
		var total int64
		for _, r := range j.Resources {
			if !safeName(r.Name) || names[r.Name] || r.Size <= 0 || r.Size > 100<<30 {
				return errors.New("invalid persisted resource")
			}
			names[r.Name] = true
			total += r.Size
		}
		if j.Total != total {
			return errors.New("invalid persisted resource sizes")
		}
	}
	return nil
}

func unfinishedJobs(jobs []*Job) int {
	count := 0
	for _, j := range jobs {
		if j != nil && j.State != "completed" && j.State != "cancelled" {
			count++
		}
	}
	return count
}
