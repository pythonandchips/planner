// Package session drives one agent over the Agent Client Protocol and keeps a
// UI-agnostic transcript and status for it. The GUI only reads Snapshot() and
// calls Prompt/ResolvePermission/Cancel; it never touches ACP types.
package session

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"

	acp "github.com/coder/acp-go-sdk"
)

// Status is the session state shown as a badge in the UI.
type Status string

const (
	StatusStarting      Status = "starting"
	StatusRunning       Status = "running"
	StatusNeedsApproval Status = "needs approval"
	StatusAwaitingInput Status = "awaiting input"
	StatusQuestion      Status = "question" // awaiting input and the agent ended on a question
	StatusError         Status = "error"
	StatusExited        Status = "exited"
)

// NeedsUser reports whether the session is blocked on the user.
func (s Status) NeedsUser() bool {
	return s == StatusNeedsApproval || s == StatusAwaitingInput || s == StatusQuestion
}

// EntryKind classifies transcript entries.
type EntryKind string

const (
	EntryUser       EntryKind = "user"
	EntryAgent      EntryKind = "agent"
	EntryThought    EntryKind = "thought"
	EntryTool       EntryKind = "tool"
	EntryPermission EntryKind = "permission"
	EntrySystem     EntryKind = "system"
)

// Option is one permission choice.
type Option struct {
	ID   string
	Name string
	Kind string // allow_once, allow_always, reject_once, reject_always
}

// Entry is one transcript item. Rev increases whenever the entry changes so a
// UI can re-render only changed rows.
type Entry struct {
	Kind EntryKind
	Text string // markdown for user/agent/thought, title for tool/permission

	ToolID     string
	ToolKind   string
	ToolStatus string

	Options  []Option // permission entries only
	Chosen   string   // option name chosen, or "cancelled"; empty while pending
	Question bool     // agent entry that ended the turn with a question

	Rev int
}

// Snapshot is a copy of the session state safe to read from any goroutine.
type Snapshot struct {
	ID      int
	Title   string
	Cwd     string
	Status  Status
	Entries []Entry
	Stderr  string
}

// Config describes how to launch the agent.
type Config struct {
	Command []string // agent command and args, e.g. npx -y @agentclientprotocol/claude-agent-acp
	Cwd     string
	Title   string
	Env     []string // extra environment
}

// Session is one ACP agent process with one ACP session.
type Session struct {
	id  int
	cfg Config

	mu        sync.Mutex
	status    Status
	entries   []Entry
	toolIndex map[string]int
	pending   map[int]chan acp.RequestPermissionOutcome // entry index -> reply channel
	stderr    bytes.Buffer
	turnOpen  bool // an agent message is being streamed in the current turn
	onChange  func()

	cmd       *exec.Cmd
	conn      *acp.ClientSideConnection
	barrier   *notificationBarrier
	sessionID acp.SessionId
	ctx       context.Context
	cancel    context.CancelFunc
}

var (
	idMu   sync.Mutex
	nextID = 1
)

// New creates a session; call Start to launch it. onChange is called (from
// any goroutine) after every state change; the UI should marshal to its main
// thread.
func New(cfg Config, onChange func()) *Session {
	idMu.Lock()
	id := nextID
	nextID++
	idMu.Unlock()
	if onChange == nil {
		onChange = func() {}
	}
	return &Session{id: id, cfg: cfg, status: StatusStarting, toolIndex: map[string]int{},
		pending: map[int]chan acp.RequestPermissionOutcome{}, onChange: onChange}
}

func (s *Session) ID() int { return s.id }

// Snapshot returns a deep-enough copy of the session for rendering.
func (s *Session) Snapshot() Snapshot {
	s.mu.Lock()
	defer s.mu.Unlock()
	entries := make([]Entry, len(s.entries))
	copy(entries, s.entries)
	return Snapshot{ID: s.id, Title: s.cfg.Title, Cwd: s.cfg.Cwd, Status: s.status, Entries: entries, Stderr: s.stderr.String()}
}

func (s *Session) changed() { s.onChange() }

func (s *Session) setStatus(st Status) {
	s.mu.Lock()
	s.status = st
	s.mu.Unlock()
	s.changed()
}

func (s *Session) appendEntry(e Entry) int {
	s.mu.Lock()
	e.Rev = 1
	s.entries = append(s.entries, e)
	i := len(s.entries) - 1
	s.mu.Unlock()
	s.changed()
	return i
}

func (s *Session) system(format string, args ...any) {
	s.appendEntry(Entry{Kind: EntrySystem, Text: fmt.Sprintf(format, args...)})
}

// lockedWriter guards the stderr buffer.
type lockedWriter struct{ s *Session }

func (w lockedWriter) Write(p []byte) (int, error) {
	w.s.mu.Lock()
	defer w.s.mu.Unlock()
	if w.s.stderr.Len() < 64*1024 {
		w.s.stderr.Write(p)
	}
	return len(p), nil
}

// Start launches the agent process, initializes ACP, creates a session and
// sends the first prompt. It returns once the session exists; the first turn
// runs in the background.
func (s *Session) Start(firstPrompt string) error {
	if len(s.cfg.Command) == 0 {
		return errors.New("empty agent command")
	}
	s.ctx, s.cancel = context.WithCancel(context.Background())
	cmd := exec.CommandContext(s.ctx, s.cfg.Command[0], s.cfg.Command[1:]...)
	cmd.Dir = s.cfg.Cwd
	cmd.Env = append(os.Environ(), s.cfg.Env...)
	cmd.Stderr = lockedWriter{s}
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return s.fail(err)
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return s.fail(err)
	}
	if err := cmd.Start(); err != nil {
		return s.fail(fmt.Errorf("start %s: %w", strings.Join(s.cfg.Command, " "), err))
	}
	s.cmd = cmd
	s.barrier = newNotificationBarrier()
	s.conn = acp.NewClientSideConnection(&client{s: s}, stdin, s.barrier.wrap(stdout))
	s.conn.SetLogger(slog.New(slog.DiscardHandler))
	go s.watchExit()

	ctx, cancel := context.WithTimeout(s.ctx, 2*time.Minute) // npx may download on first run
	defer cancel()
	if _, err := s.conn.Initialize(ctx, acp.InitializeRequest{
		ProtocolVersion: acp.ProtocolVersionNumber,
		ClientCapabilities: acp.ClientCapabilities{
			Fs:       acp.FileSystemCapabilities{ReadTextFile: true, WriteTextFile: true},
			Terminal: false,
		},
	}); err != nil {
		return s.fail(fmt.Errorf("initialize: %w", err))
	}
	ns, err := s.conn.NewSession(ctx, acp.NewSessionRequest{Cwd: s.cfg.Cwd, McpServers: []acp.McpServer{}})
	if err != nil {
		return s.fail(fmt.Errorf("session/new: %w", err))
	}
	s.sessionID = ns.SessionId
	s.system("Session `%s` started in `%s`", ns.SessionId, s.cfg.Cwd)
	return s.Prompt(firstPrompt)
}

func (s *Session) fail(err error) error {
	s.system("Error: %v", err)
	s.setStatus(StatusError)
	return err
}

func (s *Session) watchExit() {
	err := s.cmd.Wait()
	s.mu.Lock()
	st := s.status
	s.mu.Unlock()
	if st == StatusExited {
		return
	}
	if err != nil && s.ctx.Err() == nil {
		s.system("Agent process exited: %v", err)
		s.setStatus(StatusError)
		return
	}
	s.setStatus(StatusExited)
}

// Prompt sends a user message as a new turn. It returns immediately; the turn
// streams in the background. It is an error to prompt while a turn is running.
func (s *Session) Prompt(text string) error {
	s.mu.Lock()
	if s.status == StatusRunning || s.status == StatusNeedsApproval {
		s.mu.Unlock()
		return errors.New("a turn is already running")
	}
	if s.conn == nil || s.status == StatusExited || s.status == StatusError {
		s.mu.Unlock()
		return errors.New("session is not running")
	}
	s.status = StatusRunning
	s.turnOpen = false
	s.mu.Unlock()
	s.appendEntry(Entry{Kind: EntryUser, Text: text})

	go func() {
		resp, err := s.conn.Prompt(s.ctx, acp.PromptRequest{
			SessionId: s.sessionID,
			Prompt:    []acp.ContentBlock{acp.TextBlock(text)},
		})
		if err != nil {
			if s.ctx.Err() != nil {
				return
			}
			s.fail(fmt.Errorf("session/prompt: %w", err))
			return
		}
		s.endTurn(resp.StopReason)
	}()
	return nil
}

// endTurn marks the session as waiting for the user. If the last agent
// message ends with a question, the entry and the status say so, so the UI
// can surface it like a question rather than just "done".
func (s *Session) endTurn(reason acp.StopReason) {
	s.mu.Lock()
	st := StatusAwaitingInput
	for i := len(s.entries) - 1; i >= 0; i-- {
		e := &s.entries[i]
		if e.Kind == EntryUser {
			break
		}
		if e.Kind == EntryAgent {
			if IsQuestion(e.Text) {
				e.Question = true
				e.Rev++
				st = StatusQuestion
			}
			break
		}
	}
	s.status = st
	s.turnOpen = false
	s.mu.Unlock()
	if reason != acp.StopReasonEndTurn {
		s.system("Turn ended: %s", reason)
	} else {
		s.changed()
	}
}

// IsQuestion is a heuristic: a sentence in the agent's last paragraph ends
// with "?". Checking only the final character missed real Claude output such
// as "What would you like to do instead? I could try X, or you could allow Y."
func IsQuestion(markdown string) bool {
	t := strings.TrimSpace(markdown)
	if i := strings.LastIndex(t, "\n\n"); i >= 0 {
		t = t[i+2:]
	}
	t = strings.NewReplacer("*", "", "_", "", "`", "").Replace(t)
	for i := strings.Index(t, "?"); i >= 0; {
		rest := t[i+1:]
		if rest == "" || rest[0] == ' ' || rest[0] == '\n' || rest[0] == ')' || rest[0] == '"' {
			return true
		}
		j := strings.Index(rest, "?")
		if j < 0 {
			break
		}
		i += j + 1
	}
	return false
}

// PendingPermission returns the transcript index of the oldest unanswered
// permission request, or -1.
func (s *Session) PendingPermission() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	best := -1
	for i := range s.pending {
		if best == -1 || i < best {
			best = i
		}
	}
	return best
}

// ResolvePermission answers the permission request at transcript index idx.
func (s *Session) ResolvePermission(idx int, optionID string) error {
	s.mu.Lock()
	ch, ok := s.pending[idx]
	if !ok {
		s.mu.Unlock()
		return fmt.Errorf("no pending permission at %d", idx)
	}
	delete(s.pending, idx)
	e := &s.entries[idx]
	for _, o := range e.Options {
		if o.ID == optionID {
			e.Chosen = o.Name
		}
	}
	e.Rev++
	if len(s.pending) == 0 && s.status == StatusNeedsApproval {
		s.status = StatusRunning
	}
	s.mu.Unlock()
	ch <- acp.RequestPermissionOutcome{Selected: &acp.RequestPermissionOutcomeSelected{OptionId: acp.PermissionOptionId(optionID)}}
	s.changed()
	return nil
}

// Cancel asks the agent to stop the current turn and answers any pending
// permission requests with "cancelled", as the protocol requires.
func (s *Session) Cancel() {
	s.mu.Lock()
	for idx, ch := range s.pending {
		s.entries[idx].Chosen = "cancelled"
		s.entries[idx].Rev++
		ch <- acp.RequestPermissionOutcome{Cancelled: &acp.RequestPermissionOutcomeCancelled{}}
		delete(s.pending, idx)
	}
	conn, sid := s.conn, s.sessionID
	s.mu.Unlock()
	if conn != nil {
		_ = conn.Cancel(context.Background(), acp.CancelNotification{SessionId: sid})
	}
	s.changed()
}

// Close kills the agent process.
func (s *Session) Close() {
	s.mu.Lock()
	s.status = StatusExited
	s.mu.Unlock()
	if s.cancel != nil {
		s.cancel()
	}
	s.changed()
}

// --- ACP client callbacks ---

type client struct{ s *Session }

var _ acp.Client = (*client)(nil)

func (c *client) SessionUpdate(ctx context.Context, n acp.SessionNotification) error {
	s := c.s
	defer s.barrier.done()
	u := n.Update
	switch {
	case u.AgentMessageChunk != nil:
		if t := u.AgentMessageChunk.Content.Text; t != nil {
			s.appendChunk(EntryAgent, t.Text)
		}
	case u.AgentThoughtChunk != nil:
		if t := u.AgentThoughtChunk.Content.Text; t != nil {
			s.appendChunk(EntryThought, t.Text)
		}
	case u.ToolCall != nil:
		tc := u.ToolCall
		s.upsertTool(string(tc.ToolCallId), &tc.Title, string(tc.Kind), statusPtr(tc.Status))
	case u.ToolCallUpdate != nil:
		tu := u.ToolCallUpdate
		kind := ""
		if tu.Kind != nil {
			kind = string(*tu.Kind)
		}
		s.upsertTool(string(tu.ToolCallId), tu.Title, kind, tu.Status)
	case u.Plan != nil:
		var b strings.Builder
		b.WriteString("**Plan**\n\n")
		for _, e := range u.Plan.Entries {
			mark := " "
			if e.Status == acp.PlanEntryStatusCompleted {
				mark = "x"
			}
			fmt.Fprintf(&b, "- [%s] %s\n", mark, e.Content)
		}
		s.appendEntry(Entry{Kind: EntrySystem, Text: b.String()})
	}
	return nil
}

func statusPtr(st acp.ToolCallStatus) *acp.ToolCallStatus {
	if st == "" {
		return nil
	}
	return &st
}

// appendChunk extends the last entry if it is the same kind and still part of
// the current streaming run, otherwise starts a new entry.
func (s *Session) appendChunk(kind EntryKind, text string) {
	s.mu.Lock()
	n := len(s.entries)
	if n > 0 && s.entries[n-1].Kind == kind && s.turnOpen {
		s.entries[n-1].Text += text
		s.entries[n-1].Rev++
	} else {
		s.entries = append(s.entries, Entry{Kind: kind, Text: text, Rev: 1})
	}
	s.turnOpen = true
	s.mu.Unlock()
	s.changed()
}

func (s *Session) upsertTool(id string, title *string, kind string, status *acp.ToolCallStatus) {
	s.mu.Lock()
	idx, ok := s.toolIndex[id]
	if !ok {
		s.entries = append(s.entries, Entry{Kind: EntryTool, ToolID: id, ToolStatus: "pending"})
		idx = len(s.entries) - 1
		s.toolIndex[id] = idx
	}
	e := &s.entries[idx]
	if title != nil && *title != "" {
		e.Text = *title
	}
	if kind != "" {
		e.ToolKind = kind
	}
	if status != nil {
		e.ToolStatus = string(*status)
	}
	e.Rev++
	s.turnOpen = false // text after a tool call starts a new agent entry
	s.mu.Unlock()
	s.changed()
}

func (c *client) RequestPermission(ctx context.Context, p acp.RequestPermissionRequest) (acp.RequestPermissionResponse, error) {
	s := c.s
	// Let session/update notifications sent before this request land first.
	s.barrier.wait(2 * time.Second)
	title := "Permission requested"
	if p.ToolCall.Title != nil {
		title = *p.ToolCall.Title
	} else if i, ok := s.toolTitle(string(p.ToolCall.ToolCallId)); ok {
		title = i
	}
	opts := make([]Option, len(p.Options))
	for i, o := range p.Options {
		opts[i] = Option{ID: string(o.OptionId), Name: o.Name, Kind: string(o.Kind)}
	}
	ch := make(chan acp.RequestPermissionOutcome, 1)
	s.mu.Lock()
	s.entries = append(s.entries, Entry{Kind: EntryPermission, Text: title, ToolID: string(p.ToolCall.ToolCallId), Options: opts, Rev: 1})
	idx := len(s.entries) - 1
	s.pending[idx] = ch
	s.status = StatusNeedsApproval
	s.turnOpen = false
	s.mu.Unlock()
	s.changed()

	select {
	case out := <-ch:
		return acp.RequestPermissionResponse{Outcome: out}, nil
	case <-ctx.Done():
		return acp.RequestPermissionResponse{Outcome: acp.RequestPermissionOutcome{Cancelled: &acp.RequestPermissionOutcomeCancelled{}}}, nil
	}
}

func (s *Session) toolTitle(id string) (string, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if i, ok := s.toolIndex[id]; ok && s.entries[i].Text != "" {
		return s.entries[i].Text, true
	}
	return "", false
}

func (c *client) ReadTextFile(ctx context.Context, p acp.ReadTextFileRequest) (acp.ReadTextFileResponse, error) {
	b, err := os.ReadFile(p.Path)
	if err != nil {
		return acp.ReadTextFileResponse{}, err
	}
	content := string(b)
	if p.Line != nil || p.Limit != nil {
		lines := strings.Split(content, "\n")
		start := 0
		if p.Line != nil && *p.Line > 0 {
			start = min(*p.Line-1, len(lines))
		}
		end := len(lines)
		if p.Limit != nil && *p.Limit > 0 && start+*p.Limit < end {
			end = start + *p.Limit
		}
		content = strings.Join(lines[start:end], "\n")
	}
	return acp.ReadTextFileResponse{Content: content}, nil
}

func (c *client) WriteTextFile(ctx context.Context, p acp.WriteTextFileRequest) (acp.WriteTextFileResponse, error) {
	return acp.WriteTextFileResponse{}, os.WriteFile(p.Path, []byte(p.Content), 0o644)
}

var errNoTerminal = errors.New("terminal not supported by this client")

func (c *client) CreateTerminal(context.Context, acp.CreateTerminalRequest) (acp.CreateTerminalResponse, error) {
	return acp.CreateTerminalResponse{}, errNoTerminal
}
func (c *client) KillTerminal(context.Context, acp.KillTerminalRequest) (acp.KillTerminalResponse, error) {
	return acp.KillTerminalResponse{}, errNoTerminal
}
func (c *client) TerminalOutput(context.Context, acp.TerminalOutputRequest) (acp.TerminalOutputResponse, error) {
	return acp.TerminalOutputResponse{}, errNoTerminal
}
func (c *client) ReleaseTerminal(context.Context, acp.ReleaseTerminalRequest) (acp.ReleaseTerminalResponse, error) {
	return acp.ReleaseTerminalResponse{}, errNoTerminal
}
func (c *client) WaitForTerminalExit(context.Context, acp.WaitForTerminalExitRequest) (acp.WaitForTerminalExitResponse, error) {
	return acp.WaitForTerminalExitResponse{}, errNoTerminal
}

var _ io.Writer = lockedWriter{}
