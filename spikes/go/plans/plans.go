// Package plans finds planner plan folders under a parent directory.
//
// A plan folder is any directory matching docs/plans/*/ either directly under
// the parent, or under one of the parent's immediate child directories (the
// "several git repos in one folder" layout).
package plans

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"

	"strconv"
	"strings"
)

// File is one markdown file inside a plan folder.
type File struct {
	Name string // e.g. ITERATION-001.md
	Path string // absolute path
	Kind string // ITERATION, FINDINGS, PLAN, REVIEW, or "" for other files
	Seq  int    // the NNN number, 0 if none
}

// Editable reports whether the UI should allow editing this file. Only
// ITERATION files are user-authored; the rest are agent outputs.
func (f File) Editable() bool { return f.Kind == "ITERATION" }

// Folder is one plan folder, e.g. repo/docs/plans/20260101-foo/.
type Folder struct {
	Repo     string // repo directory name (the parent's own name if plans sit in the parent)
	RepoPath string // absolute path of the repo; used as the agent session cwd
	Name     string // folder base name
	Path     string
	Files    []File
}

// ID is a stable key for the folder, used by the UI tree.
func (f Folder) ID() string { return f.Path }

var kindRe = regexp.MustCompile(`^(ITERATION|FINDINGS|PLAN|REVIEW)-(\d+)\.md$`)

// Discover returns the plan folders found under parent, sorted by repo then
// folder name. Unreadable directories are skipped.
func Discover(parent string) ([]Folder, error) {
	parent, err := filepath.Abs(parent)
	if err != nil {
		return nil, err
	}
	if st, err := os.Stat(parent); err != nil {
		return nil, err
	} else if !st.IsDir() {
		return nil, fmt.Errorf("%s is not a directory", parent)
	}
	roots := []string{parent}
	entries, _ := os.ReadDir(parent)
	for _, e := range entries {
		if e.IsDir() && !strings.HasPrefix(e.Name(), ".") {
			roots = append(roots, filepath.Join(parent, e.Name()))
		}
	}
	var out []Folder
	for _, root := range roots {
		plansDir := filepath.Join(root, "docs", "plans")
		dirs, err := os.ReadDir(plansDir)
		if err != nil {
			continue
		}
		for _, d := range dirs {
			if !d.IsDir() || strings.HasPrefix(d.Name(), ".") {
				continue
			}
			p := filepath.Join(plansDir, d.Name())
			out = append(out, Folder{
				Repo:     filepath.Base(root),
				RepoPath: root,
				Name:     d.Name(),
				Path:     p,
				Files:    ListFiles(p),
			})
		}
	}
	// os.ReadDir returns names sorted, so the parent's own plans come first,
	// then each child repo alphabetically, each repo's folders by name.
	return out, nil
}

// ListFiles lists the markdown files in a plan folder, grouped by iteration
// number so ITERATION-001, FINDINGS-001, PLAN-001, REVIEW-001 sit together in
// the order the workflow produces them.
func ListFiles(dir string) []File {
	entries, _ := os.ReadDir(dir)
	var files []File
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".md") {
			continue
		}
		f := File{Name: e.Name(), Path: filepath.Join(dir, e.Name())}
		if m := kindRe.FindStringSubmatch(e.Name()); m != nil {
			f.Kind = m[1]
			f.Seq, _ = strconv.Atoi(m[2])
		}
		files = append(files, f)
	}
	order := map[string]int{"ITERATION": 0, "FINDINGS": 1, "PLAN": 2, "REVIEW": 3, "": 4}
	sort.Slice(files, func(i, j int) bool {
		a, b := files[i], files[j]
		if a.Seq != b.Seq {
			return a.Seq < b.Seq
		}
		if order[a.Kind] != order[b.Kind] {
			return order[a.Kind] < order[b.Kind]
		}
		return a.Name < b.Name
	})
	return files
}

// NextIterationName returns the file name for a new iteration in folder,
// e.g. ITERATION-003.md when ITERATION-002.md is the highest present.
func NextIterationName(f Folder) string {
	n := 0
	for _, file := range f.Files {
		if file.Kind == "ITERATION" && file.Seq > n {
			n = file.Seq
		}
	}
	return fmt.Sprintf("ITERATION-%03d.md", n+1)
}
