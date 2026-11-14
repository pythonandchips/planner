package main

import (
	"image/png"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/test"
	"fyne.io/fyne/v2/theme"
	"fyne.io/fyne/v2/widget"

	"planner-desktop-spike/session"
)

// These tests drive the real UI code with Fyne's headless test driver. Set
// SHOTS=dir to write PNG captures of the window at each step.

func write(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func fixture(t *testing.T) string {
	parent := t.TempDir()
	dir := filepath.Join(parent, "alpha/docs/plans/20261101-desktop-view")
	write(t, filepath.Join(dir, "ITERATION-001.md"), "# Iteration 1\n\nBuild a **desktop view** for planner.\n\n- list plan folders\n- run sessions\n")
	write(t, filepath.Join(dir, "FINDINGS-001.md"), "# Findings\n\n## Options\n\n1. GPUI\n2. SwiftUI\n3. Fyne\n\n```go\nfunc main() {}\n```\n")
	write(t, filepath.Join(parent, "beta/docs/plans/20261102-other/ITERATION-001.md"), "# Other\n")
	return parent
}

type harness struct {
	t     *testing.T
	u     *ui
	w     fyne.Window
	mu    sync.Mutex
	queue []func()
	shots string
}

func newHarness(t *testing.T) *harness {
	a := test.NewTempApp(t)
	a.Settings().SetTheme(theme.DefaultTheme())
	w := a.NewWindow("Planner")
	agent := filepath.Join(t.TempDir(), "mockagent")
	if out, err := exec.Command("go", "build", "-o", agent, "./cmd/mockagent").CombinedOutput(); err != nil {
		t.Fatalf("build mock agent: %v\n%s", err, out)
	}
	u, err := newUI(a, w, fixture(t), []string{agent})
	if err != nil {
		t.Fatal(err)
	}
	h := &harness{t: t, u: u, w: w, shots: os.Getenv("SHOTS")}
	u.dispatch = func(f func()) {
		h.mu.Lock()
		h.queue = append(h.queue, f)
		h.mu.Unlock()
	}
	w.SetContent(u.build())
	w.Resize(fyne.NewSize(1280, 820))
	t.Cleanup(u.closeAll)
	return h
}

// pump runs queued UI work on the test goroutine.
func (h *harness) pump() {
	h.mu.Lock()
	q := h.queue
	h.queue = nil
	h.mu.Unlock()
	for _, f := range q {
		f()
	}
}

func (h *harness) waitStatus(s *session.Session, want session.Status) {
	h.t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		h.pump()
		if s.Snapshot().Status == want {
			time.Sleep(20 * time.Millisecond)
			h.pump()
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	h.t.Fatalf("timeout waiting for %s, have %s: %+v", want, s.Snapshot().Status, s.Snapshot().Entries)
}

func (h *harness) shot(name string) {
	if h.shots == "" {
		return
	}
	img := h.w.Canvas().Capture()
	f, err := os.Create(filepath.Join(h.shots, name+".png"))
	if err != nil {
		h.t.Fatal(err)
	}
	defer f.Close()
	if err := png.Encode(f, img); err != nil {
		h.t.Fatal(err)
	}
}

// findButtons walks the object tree collecting buttons by label.
func findButtons(o fyne.CanvasObject, out map[string]*widget.Button) {
	switch x := o.(type) {
	case *widget.Button:
		out[x.Text] = x
	case *fyne.Container:
		for _, c := range x.Objects {
			findButtons(c, out)
		}
	}
}

func TestEditAndSaveIteration(t *testing.T) {
	h := newHarness(t)
	f := h.u.folders[0]
	if f.Repo != "alpha" || len(f.Files) != 2 {
		t.Fatalf("unexpected folders %+v", h.u.folders)
	}
	iter := f.Files[0].Path
	h.u.tree.OpenBranch("dir:" + f.Path)
	h.u.tree.Select("file:" + iter)
	if h.u.doc.path != iter || !h.u.doc.editable {
		t.Fatalf("doc not opened as editable: %+v", h.u.doc.path)
	}
	h.shot("1-preview")

	h.u.doc.setEditing(true)
	test.Type(h.u.doc.editor, "\nAdded from the GUI.\n")
	if !h.u.doc.dirty || h.u.doc.state.Text != "edited" {
		t.Fatal("typing should mark the doc dirty")
	}
	h.shot("2-editing")
	h.u.doc.save()
	b, _ := os.ReadFile(iter)
	if !strings.Contains(string(b), "Added from the GUI.") {
		t.Fatalf("not saved: %q", b)
	}
	if h.u.doc.state.Text != "saved" {
		t.Fatal("state should be saved")
	}

	// Findings are read only.
	h.u.tree.Select("file:" + f.Files[1].Path)
	if h.u.doc.editable || h.u.doc.saveBtn.Visible() {
		t.Fatal("FINDINGS should be read only")
	}
	h.shot("3-findings-readonly")
}

func TestTwoSessionsPermissionQuestionReply(t *testing.T) {
	h := newHarness(t)
	folder := h.u.folders[0]

	h.u.startSession(session.Config{Command: h.u.agent, Cwd: folder.RepoPath, Title: "explore · " + folder.Name}, defaultPrompt("explore", &folder))
	h.u.startSession(session.Config{Command: h.u.agent, Cwd: folder.RepoPath, Title: "plan · " + folder.Name}, defaultPrompt("plan", &folder))
	a, b := h.u.sessions[0], h.u.sessions[1]
	h.waitStatus(a, session.StatusNeedsApproval)
	h.waitStatus(b, session.StatusNeedsApproval)
	if h.w.Title() != "Planner — 2 waiting for you" {
		t.Fatalf("window title %q", h.w.Title())
	}

	// Session b is shown (last started). Approve via the rendered button.
	if h.u.selectedSes != b.ID() {
		t.Fatalf("selected %d", h.u.selectedSes)
	}
	h.shot("4-permission")
	btns := map[string]*widget.Button{}
	findButtons(h.u.views[b.ID()].transcript, btns)
	allow, ok := btns["Allow"]
	if !ok || len(btns) != 3 {
		t.Fatalf("permission buttons: %v", btns)
	}
	test.Tap(allow)
	h.waitStatus(b, session.StatusQuestion)
	v := h.u.views[b.ID()]
	if v.reply.Disabled() || !strings.Contains(v.hint.Text, "asked a question") {
		t.Fatalf("reply box should be enabled for a question; hint %q", v.hint.Text)
	}
	h.shot("5-question")

	test.Type(v.reply, "Keep it as one")
	test.Tap(v.send)
	h.waitStatus(b, session.StatusAwaitingInput)
	last := b.Snapshot().Entries
	if !strings.Contains(last[len(last)-1].Text, "Keep it as one") {
		t.Fatalf("reply not echoed: %+v", last[len(last)-1])
	}
	h.shot("6-replied")

	// Session a is still waiting; switch to it from the list and reject.
	h.u.sessionList.Select(0)
	if h.u.selectedSes != a.ID() || a.Snapshot().Status != session.StatusNeedsApproval {
		t.Fatal("session a should still need approval")
	}
	btns = map[string]*widget.Button{}
	findButtons(h.u.views[a.ID()].transcript, btns)
	test.Tap(btns["Reject"])
	h.waitStatus(a, session.StatusQuestion)
	h.shot("7-other-session-rejected")
}
