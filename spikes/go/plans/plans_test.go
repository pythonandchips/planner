package plans

import (
	"os"
	"path/filepath"
	"testing"
)

func touch(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("# x\n"), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestDiscover(t *testing.T) {
	parent := t.TempDir()
	// Plans directly in the parent.
	touch(t, filepath.Join(parent, "docs/plans/20260101-root/ITERATION-001.md"))
	// Two child repos.
	touch(t, filepath.Join(parent, "alpha/docs/plans/20260201-feature/REVIEW-001.md"))
	touch(t, filepath.Join(parent, "alpha/docs/plans/20260201-feature/PLAN-001.md"))
	touch(t, filepath.Join(parent, "alpha/docs/plans/20260201-feature/ITERATION-002.md"))
	touch(t, filepath.Join(parent, "alpha/docs/plans/20260201-feature/FINDINGS-001.md"))
	touch(t, filepath.Join(parent, "alpha/docs/plans/20260201-feature/ITERATION-001.md"))
	touch(t, filepath.Join(parent, "alpha/docs/plans/20260201-feature/notes.txt"))
	touch(t, filepath.Join(parent, "beta/docs/plans/20260301-other/ITERATION-001.md"))
	// Not plan folders: too deep, hidden, or a stray file.
	touch(t, filepath.Join(parent, "alpha/vendor/x/docs/plans/nope/ITERATION-001.md"))
	touch(t, filepath.Join(parent, ".hidden/docs/plans/nope/ITERATION-001.md"))
	touch(t, filepath.Join(parent, "beta/docs/plans/README.md"))
	// A child that is not a repo with plans.
	touch(t, filepath.Join(parent, "gamma/README.md"))

	got, err := Discover(parent)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, f := range got {
		names = append(names, f.Repo+"/"+f.Name)
	}
	want := []string{filepath.Base(parent) + "/20260101-root", "alpha/20260201-feature", "beta/20260301-other"}
	if len(names) != len(want) {
		t.Fatalf("got %v want %v", names, want)
	}
	for i := range want {
		if names[i] != want[i] {
			t.Fatalf("got %v want %v", names, want)
		}
	}

	alpha := got[1]
	var files []string
	for _, f := range alpha.Files {
		files = append(files, f.Name)
	}
	wantFiles := []string{"ITERATION-001.md", "FINDINGS-001.md", "PLAN-001.md", "REVIEW-001.md", "ITERATION-002.md"}
	if len(files) != len(wantFiles) {
		t.Fatalf("files %v want %v", files, wantFiles)
	}
	for i := range wantFiles {
		if files[i] != wantFiles[i] {
			t.Fatalf("files %v want %v", files, wantFiles)
		}
	}
	if !alpha.Files[0].Editable() || alpha.Files[1].Editable() {
		t.Fatal("only ITERATION files should be editable")
	}
	if alpha.RepoPath != filepath.Join(parent, "alpha") {
		t.Fatalf("repo path %s", alpha.RepoPath)
	}
	if n := NextIterationName(alpha); n != "ITERATION-003.md" {
		t.Fatalf("next iteration %s", n)
	}
}

func TestDiscoverMissingParent(t *testing.T) {
	if _, err := Discover(filepath.Join(t.TempDir(), "missing")); err == nil {
		t.Fatal("expected error for missing parent")
	}
}
