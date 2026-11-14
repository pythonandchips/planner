package session

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

var mockAgent string

func TestMain(m *testing.M) {
	dir, err := os.MkdirTemp("", "mockagent")
	if err != nil {
		panic(err)
	}
	mockAgent = filepath.Join(dir, "mockagent")
	build := exec.Command("go", "build", "-o", mockAgent, "../cmd/mockagent")
	build.Stdout, build.Stderr = os.Stdout, os.Stderr
	if err := build.Run(); err != nil {
		panic(err)
	}
	code := m.Run()
	os.RemoveAll(dir)
	os.Exit(code)
}

// watcher records every status the session passes through and lets a test
// block until a condition holds.
type watcher struct {
	mu   sync.Mutex
	cond *sync.Cond
	s    *Session
}

func newWatched(t *testing.T, title string) (*Session, *watcher) {
	w := &watcher{}
	w.cond = sync.NewCond(&w.mu)
	s := New(Config{Command: []string{mockAgent}, Cwd: t.TempDir(), Title: title}, func() {
		w.mu.Lock()
		w.cond.Broadcast()
		w.mu.Unlock()
	})
	w.mu.Lock()
	w.s = s
	w.mu.Unlock()
	t.Cleanup(s.Close)
	return s, w
}

func (w *watcher) waitFor(t *testing.T, want Status) Snapshot {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	go func() { time.Sleep(10 * time.Second); w.cond.Broadcast() }()
	w.mu.Lock()
	defer w.mu.Unlock()
	for {
		snap := w.s.Snapshot()
		if snap.Status == want {
			return snap
		}
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for %q; status %q; entries %+v; stderr %s", want, snap.Status, snap.Entries, snap.Stderr)
		}
		w.cond.Wait()
	}
}

func find(entries []Entry, kind EntryKind) []Entry {
	var out []Entry
	for _, e := range entries {
		if e.Kind == kind {
			out = append(out, e)
		}
	}
	return out
}

func TestTurnWithPermissionQuestionAndReply(t *testing.T) {
	s, w := newWatched(t, "explore")
	if err := s.Start("Explore the plan"); err != nil {
		t.Fatal(err)
	}

	snap := w.waitFor(t, StatusNeedsApproval)
	agent := find(snap.Entries, EntryAgent)
	if len(agent) != 1 || agent[0].Text != "I'll look at the plan folder first.\n\n" {
		t.Fatalf("streamed chunks not merged into one message: %+v", agent)
	}
	tools := find(snap.Entries, EntryTool)
	if len(tools) != 1 || tools[0].ToolStatus != "pending" || !strings.Contains(tools[0].Text, "ITERATION-001.md") {
		t.Fatalf("tool call: %+v", tools)
	}
	perms := find(snap.Entries, EntryPermission)
	if len(perms) != 1 || len(perms[0].Options) != 3 || perms[0].Chosen != "" {
		t.Fatalf("permission: %+v", perms)
	}
	idx := s.PendingPermission()
	if idx < 0 {
		t.Fatal("no pending permission")
	}
	if err := s.ResolvePermission(idx, "allow"); err != nil {
		t.Fatal(err)
	}

	snap = w.waitFor(t, StatusQuestion)
	tools = find(snap.Entries, EntryTool)
	if tools[0].ToolStatus != "completed" {
		t.Fatalf("tool not completed: %+v", tools[0])
	}
	if p := find(snap.Entries, EntryPermission)[0]; p.Chosen != "Allow" {
		t.Fatalf("chosen option not recorded: %+v", p)
	}
	agent = find(snap.Entries, EntryAgent)
	last := agent[len(agent)-1]
	if !last.Question || !strings.HasSuffix(last.Text, "or keep it as one?") {
		t.Fatalf("question not detected: %+v", last)
	}
	if !snap.Status.NeedsUser() {
		t.Fatal("question status should need the user")
	}

	if err := s.Prompt("Keep it as one"); err != nil {
		t.Fatal(err)
	}
	snap = w.waitFor(t, StatusAwaitingInput)
	agent = find(snap.Entries, EntryAgent)
	last = agent[len(agent)-1]
	if last.Question || !strings.Contains(last.Text, "*Keep it as one*") {
		t.Fatalf("reply turn: %+v", last)
	}
	users := find(snap.Entries, EntryUser)
	if len(users) != 2 {
		t.Fatalf("user entries: %+v", users)
	}

	// Transcript order matches wire order: the permission card sits after
	// the text and tool call the agent sent before asking.
	var kinds []string
	for _, e := range snap.Entries {
		kinds = append(kinds, string(e.Kind))
	}
	want := "system user agent tool permission agent user agent"
	if got := strings.Join(kinds, " "); got != want {
		t.Fatalf("transcript order %q want %q", got, want)
	}
}

func TestTwoConcurrentSessions(t *testing.T) {
	a, wa := newWatched(t, "explore")
	b, wb := newWatched(t, "plan")
	var wg sync.WaitGroup
	for _, s := range []*Session{a, b} {
		wg.Add(1)
		go func(s *Session) {
			defer wg.Done()
			if err := s.Start("go"); err != nil {
				t.Error(err)
			}
		}(s)
	}
	wg.Wait()
	wa.waitFor(t, StatusNeedsApproval)
	wb.waitFor(t, StatusNeedsApproval)

	// Reject in b while a is still blocked: they must be independent.
	if err := b.ResolvePermission(b.PendingPermission(), "reject"); err != nil {
		t.Fatal(err)
	}
	snapB := wb.waitFor(t, StatusQuestion)
	if tool := find(snapB.Entries, EntryTool)[0]; tool.ToolStatus != "failed" {
		t.Fatalf("rejected tool should fail: %+v", tool)
	}
	if a.Snapshot().Status != StatusNeedsApproval {
		t.Fatalf("session a should still need approval, got %s", a.Snapshot().Status)
	}
	if err := a.ResolvePermission(a.PendingPermission(), "always"); err != nil {
		t.Fatal(err)
	}
	snapA := wa.waitFor(t, StatusQuestion)
	if p := find(snapA.Entries, EntryPermission)[0]; p.Chosen != "Always allow edits" {
		t.Fatalf("a chosen: %+v", p)
	}
}

func TestCancelWhileAwaitingPermission(t *testing.T) {
	s, w := newWatched(t, "run")
	if err := s.Start("go"); err != nil {
		t.Fatal(err)
	}
	w.waitFor(t, StatusNeedsApproval)
	s.Cancel()
	snap := w.waitFor(t, StatusAwaitingInput)
	if p := find(snap.Entries, EntryPermission)[0]; p.Chosen != "cancelled" {
		t.Fatalf("permission should be cancelled: %+v", p)
	}
	sys := find(snap.Entries, EntrySystem)
	if !strings.Contains(sys[len(sys)-1].Text, "cancelled") {
		t.Fatalf("expected cancelled stop reason in transcript: %+v", sys)
	}
}

func TestBadCommandSetsError(t *testing.T) {
	s, _ := newWatched(t, "bad")
	s.cfg.Command = []string{filepath.Join(t.TempDir(), "does-not-exist")}
	if err := s.Start("hi"); err == nil {
		t.Fatal("expected error")
	}
	if st := s.Snapshot().Status; st != StatusError {
		t.Fatalf("status %s", st)
	}
}

func TestIsQuestion(t *testing.T) {
	for in, want := range map[string]bool{
		"Done.":                                 false,
		"Which one?":                            true,
		"Should I continue?**\n\n":              true,
		"Is this `ok?`":                         true,
		"Asked earlier?\n\nNow it is finished.": false,
		"See https://x.test/?q=1 for details.":  false,
		// Real claude-agent-acp output from the spike run:
		"I wasn't allowed to run it. What would you like to do instead? I could try `top -l 1`, or you could allow `ps` for this session.": true,
	} {
		if IsQuestion(in) != want {
			t.Errorf("IsQuestion(%q) != %v", in, want)
		}
	}
}
