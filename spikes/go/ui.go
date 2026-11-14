package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/driver/desktop"
	"fyne.io/fyne/v2/theme"
	"fyne.io/fyne/v2/widget"

	"planner-desktop-spike/plans"
	"planner-desktop-spike/session"
)

type ui struct {
	app    fyne.App
	win    fyne.Window
	parent string
	agent  []string

	folders []plans.Folder
	tree    *widget.Tree

	sessions    []*session.Session
	sessionList *widget.List
	views       map[int]*sessionView
	selectedSes int // session id shown on the right, 0 if a document is shown

	// coalesce change callbacks: one pending fyne.Do per session at a time
	pendingMu sync.Mutex
	pending   map[int]bool

	right *fyne.Container // stack holding the current right-hand view
	doc   *docView

	// dispatch runs UI work on the main goroutine. fyne.Do in the app; tests
	// swap it for a queue they drain, because the test driver runs fyne.Do
	// inline on the calling goroutine.
	dispatch func(func())
}

func newUI(a fyne.App, w fyne.Window, parent string, agent []string) (*ui, error) {
	abs, err := filepath.Abs(parent)
	if err != nil {
		return nil, err
	}
	u := &ui{app: a, win: w, parent: abs, agent: agent, views: map[int]*sessionView{}, pending: map[int]bool{}, dispatch: fyne.Do}
	if err := u.reload(); err != nil {
		return nil, err
	}
	return u, nil
}

func (u *ui) reload() error {
	f, err := plans.Discover(u.parent)
	if err != nil {
		return err
	}
	u.folders = f
	if u.tree != nil {
		u.tree.Refresh()
	}
	return nil
}

// --- layout ---

func (u *ui) build() fyne.CanvasObject {
	u.tree = u.buildTree()
	u.sessionList = u.buildSessionList()

	refresh := widget.NewButtonWithIcon("", theme.ViewRefreshIcon(), func() {
		if err := u.reload(); err != nil {
			dialog.ShowError(err, u.win)
		}
	})
	newSession := widget.NewButtonWithIcon("New session", theme.ContentAddIcon(), func() { u.showNewSession(u.currentFolder()) })

	plansPane := container.NewBorder(
		container.NewBorder(nil, nil, heading("Plans"), refresh),
		nil, nil, nil, u.tree)
	sessionsPane := container.NewBorder(
		container.NewBorder(nil, nil, heading("Sessions"), newSession),
		nil, nil, nil, u.sessionList)
	left := container.NewVSplit(plansPane, sessionsPane)
	left.Offset = 0.6

	u.doc = newDocView(u)
	u.right = container.NewStack(u.welcome())
	split := container.NewHSplit(left, u.right)
	split.Offset = 0.26

	ctrlS := &desktop.CustomShortcut{KeyName: fyne.KeyS, Modifier: fyne.KeyModifierShortcutDefault}
	u.win.Canvas().AddShortcut(ctrlS, func(fyne.Shortcut) { u.doc.save() })
	return split
}

func (u *ui) menu() *fyne.MainMenu {
	save := fyne.NewMenuItem("Save", func() { u.doc.save() })
	save.Shortcut = &desktop.CustomShortcut{KeyName: fyne.KeyS, Modifier: fyne.KeyModifierShortcutDefault}
	newSes := fyne.NewMenuItem("New Session…", func() { u.showNewSession(u.currentFolder()) })
	newSes.Shortcut = &desktop.CustomShortcut{KeyName: fyne.KeyN, Modifier: fyne.KeyModifierShortcutDefault}
	return fyne.NewMainMenu(fyne.NewMenu("File", newSes, save))
}

func heading(s string) *widget.Label {
	return widget.NewLabelWithStyle(s, fyne.TextAlignLeading, fyne.TextStyle{Bold: true})
}

func (u *ui) welcome() fyne.CanvasObject {
	msg := fmt.Sprintf("**%d plan folders** found under `%s`.\n\nPick a file on the left, or start a session.\n\nAgent command: `%s`",
		len(u.folders), u.parent, strings.Join(u.agent, " "))
	rt := widget.NewRichTextFromMarkdown(msg)
	rt.Wrapping = fyne.TextWrapWord
	return container.NewPadded(rt)
}

func (u *ui) show(o fyne.CanvasObject) {
	u.right.Objects = []fyne.CanvasObject{o}
	u.right.Refresh()
}

// --- plan tree ---
// Node IDs: "" root; "repo:<path>"; "dir:<path>"; "file:<path>".

func (u *ui) buildTree() *widget.Tree {
	children := func(id widget.TreeNodeID) []widget.TreeNodeID {
		var out []string
		switch {
		case id == "":
			seen := map[string]bool{}
			for _, f := range u.folders {
				if !seen[f.RepoPath] {
					seen[f.RepoPath] = true
					out = append(out, "repo:"+f.RepoPath)
				}
			}
		case strings.HasPrefix(id, "repo:"):
			for _, f := range u.folders {
				if "repo:"+f.RepoPath == id {
					out = append(out, "dir:"+f.Path)
				}
			}
		case strings.HasPrefix(id, "dir:"):
			if f, ok := u.folderByPath(strings.TrimPrefix(id, "dir:")); ok {
				for _, file := range f.Files {
					out = append(out, "file:"+file.Path)
				}
			}
		}
		return out
	}
	isBranch := func(id widget.TreeNodeID) bool { return !strings.HasPrefix(id, "file:") }
	create := func(branch bool) fyne.CanvasObject {
		return container.NewHBox(widget.NewIcon(theme.FolderIcon()), widget.NewLabel(""))
	}
	update := func(id widget.TreeNodeID, branch bool, o fyne.CanvasObject) {
		box := o.(*fyne.Container)
		icon, label := box.Objects[0].(*widget.Icon), box.Objects[1].(*widget.Label)
		_, rest, _ := strings.Cut(id, ":")
		label.SetText(filepath.Base(rest))
		label.TextStyle = fyne.TextStyle{}
		switch {
		case strings.HasPrefix(id, "repo:"):
			icon.SetResource(theme.StorageIcon())
			label.TextStyle = fyne.TextStyle{Bold: true}
		case strings.HasPrefix(id, "dir:"):
			icon.SetResource(theme.FolderIcon())
		case strings.HasPrefix(filepath.Base(rest), "ITERATION-"):
			icon.SetResource(theme.DocumentCreateIcon())
		default:
			icon.SetResource(theme.FileTextIcon())
		}
		label.Refresh()
	}
	t := widget.NewTree(children, isBranch, create, update)
	t.OnSelected = func(id widget.TreeNodeID) {
		switch {
		case strings.HasPrefix(id, "file:"):
			u.openFile(strings.TrimPrefix(id, "file:"))
		case strings.HasPrefix(id, "dir:"):
			if f, ok := u.folderByPath(strings.TrimPrefix(id, "dir:")); ok {
				u.showFolder(f)
			}
		}
	}
	// Open every repo so plan folders are visible at a glance.
	for _, f := range u.folders {
		t.OpenBranch("repo:" + f.RepoPath)
	}
	return t
}

func (u *ui) folderByPath(p string) (plans.Folder, bool) {
	for _, f := range u.folders {
		if f.Path == p {
			return f, true
		}
	}
	return plans.Folder{}, false
}

// currentFolder is the plan folder of the open document, if any.
func (u *ui) currentFolder() *plans.Folder {
	if u.doc != nil && u.doc.path != "" {
		if f, ok := u.folderByPath(filepath.Dir(u.doc.path)); ok {
			return &f
		}
	}
	return nil
}

func (u *ui) openFile(path string) {
	if !u.doc.confirmDiscard() {
		return
	}
	u.selectedSes = 0
	u.sessionList.UnselectAll()
	if err := u.doc.load(path); err != nil {
		dialog.ShowError(err, u.win)
		return
	}
	u.show(u.doc.root)
}

func (u *ui) showFolder(f plans.Folder) {
	var b strings.Builder
	fmt.Fprintf(&b, "# %s\n\nRepo: `%s`\n\n", f.Name, f.RepoPath)
	for _, file := range f.Files {
		fmt.Fprintf(&b, "- %s\n", file.Name)
	}
	rt := widget.NewRichTextFromMarkdown(b.String())
	rt.Wrapping = fyne.TextWrapWord
	newIter := widget.NewButtonWithIcon("New iteration", theme.DocumentCreateIcon(), func() {
		name := plans.NextIterationName(f)
		p := filepath.Join(f.Path, name)
		if err := os.WriteFile(p, []byte("# "+strings.TrimSuffix(name, ".md")+"\n\n"), 0o644); err != nil {
			dialog.ShowError(err, u.win)
			return
		}
		u.reload()
		u.tree.OpenBranch("dir:" + f.Path)
		u.tree.Select("file:" + p)
		u.doc.setEditing(true)
	})
	start := widget.NewButtonWithIcon("Start session…", theme.MediaPlayIcon(), func() { u.showNewSession(&f) })
	start.Importance = widget.HighImportance
	u.show(container.NewBorder(container.NewHBox(newIter, start), nil, nil, nil, container.NewVScroll(rt)))
}

// --- sessions ---

func (u *ui) buildSessionList() *widget.List {
	l := widget.NewList(
		func() int { return len(u.sessions) },
		func() fyne.CanvasObject {
			badge := widget.NewLabel("")
			badge.TextStyle = fyne.TextStyle{Bold: true}
			title := widget.NewLabel("")
			title.Truncation = fyne.TextTruncateEllipsis
			return container.NewBorder(nil, nil, nil, badge, title)
		},
		func(i widget.ListItemID, o fyne.CanvasObject) {
			snap := u.sessions[i].Snapshot()
			box := o.(*fyne.Container)
			title, badge := box.Objects[0].(*widget.Label), box.Objects[1].(*widget.Label)
			title.SetText(snap.Title)
			badge.SetText(badgeText(snap.Status))
			badge.Importance = badgeImportance(snap.Status)
			badge.Refresh()
			box.Refresh() // re-run the Border layout: the badge width changed
		})
	l.OnSelected = func(i widget.ListItemID) {
		if !u.doc.confirmDiscard() {
			l.UnselectAll()
			return
		}
		s := u.sessions[i]
		u.selectedSes = s.ID()
		u.tree.UnselectAll()
		u.show(u.viewFor(s).root)
	}
	return l
}

func badgeText(s session.Status) string {
	// Plain text: Fyne's bundled Noto Sans lacks symbols such as U+2691 (flag),
	// which render as a replacement box. Colour carries the urgency instead.
	if s == session.StatusQuestion {
		return "asked a question"
	}
	return string(s)
}

func badgeImportance(s session.Status) widget.Importance {
	switch s {
	case session.StatusRunning, session.StatusStarting:
		return widget.HighImportance
	case session.StatusNeedsApproval, session.StatusQuestion:
		return widget.WarningImportance
	case session.StatusAwaitingInput:
		return widget.SuccessImportance
	case session.StatusError:
		return widget.DangerImportance
	default:
		return widget.LowImportance
	}
}

func (u *ui) viewFor(s *session.Session) *sessionView {
	v, ok := u.views[s.ID()]
	if !ok {
		v = newSessionView(u, s)
		u.views[s.ID()] = v
	}
	return v
}

var sessionKinds = []string{"explore", "plan", "run"}

func defaultPrompt(kind string, folder *plans.Folder) string {
	target := "the current plan"
	if folder != nil {
		target = "`" + folder.Path + "`"
		for i := len(folder.Files) - 1; i >= 0; i-- {
			if folder.Files[i].Kind == "ITERATION" {
				target = "`" + folder.Files[i].Path + "`"
				break
			}
		}
	}
	switch kind {
	case "plan":
		return "Write a PLAN for " + target + " using its FINDINGS. Ask me if anything is unclear."
	case "run":
		return "Carry out the PLAN for " + target + ", then write a REVIEW."
	default:
		return "Read " + target + " and explore the codebase. Write FINDINGS next to it. Ask me questions where the iteration is unclear."
	}
}

func (u *ui) showNewSession(folder *plans.Folder) {
	kind := widget.NewSelect(sessionKinds, nil)
	prompt := widget.NewMultiLineEntry()
	prompt.Wrapping = fyne.TextWrapWord
	prompt.SetMinRowsVisible(6)
	kind.OnChanged = func(k string) { prompt.SetText(defaultPrompt(k, folder)) }
	kind.SetSelected("explore")

	var repoNames []string
	repoPaths := map[string]string{}
	for _, f := range u.folders {
		if _, ok := repoPaths[f.Repo]; !ok {
			repoNames = append(repoNames, f.Repo)
			repoPaths[f.Repo] = f.RepoPath
		}
	}
	if len(repoNames) == 0 {
		repoNames = []string{filepath.Base(u.parent)}
		repoPaths[repoNames[0]] = u.parent
	}
	repo := widget.NewSelect(repoNames, nil)
	if folder != nil {
		repo.SetSelected(folder.Repo)
	} else {
		repo.SetSelected(repoNames[0])
	}
	agent := widget.NewEntry()
	agent.SetText(strings.Join(u.agent, " "))

	items := []*widget.FormItem{
		widget.NewFormItem("Kind", kind),
		widget.NewFormItem("Repo", repo),
		widget.NewFormItem("Prompt", prompt),
		widget.NewFormItem("Agent", agent),
	}
	d := dialog.NewForm("New session", "Start", "Cancel", items, func(ok bool) {
		if !ok {
			return
		}
		title := kind.Selected
		if folder != nil {
			title += " · " + folder.Name
		} else {
			title += " · " + repo.Selected
		}
		u.startSession(session.Config{Command: strings.Fields(agent.Text), Cwd: repoPaths[repo.Selected], Title: title}, prompt.Text)
	}, u.win)
	d.Resize(fyne.NewSize(640, 420))
	d.Show()
}

func (u *ui) startSession(cfg session.Config, prompt string) {
	var s *session.Session
	s = session.New(cfg, func() { u.sessionChanged(s.ID()) })
	u.sessions = append(u.sessions, s)
	u.sessionList.Refresh()
	u.sessionList.Select(len(u.sessions) - 1)
	go func() {
		// Errors are already in the transcript and status badge.
		_ = s.Start(prompt)
	}()
}

// sessionChanged runs on any goroutine. It coalesces bursts of streamed
// chunks into one UI refresh on the main thread.
func (u *ui) sessionChanged(id int) {
	u.pendingMu.Lock()
	if u.pending[id] {
		u.pendingMu.Unlock()
		return
	}
	u.pending[id] = true
	u.pendingMu.Unlock()
	u.dispatch(func() {
		u.pendingMu.Lock()
		delete(u.pending, id)
		u.pendingMu.Unlock()
		u.sessionList.Refresh()
		u.updateTitle()
		if v, ok := u.views[id]; ok {
			v.refresh()
		}
		u.notifyIfNeeded(id)
	})
}

var lastNotified sync.Map // session id -> status already notified

func (u *ui) notifyIfNeeded(id int) {
	for _, s := range u.sessions {
		if s.ID() != id {
			continue
		}
		st := s.Snapshot().Status
		prev, _ := lastNotified.Load(id)
		if st.NeedsUser() && prev != st {
			snap := s.Snapshot()
			u.app.SendNotification(fyne.NewNotification(snap.Title, "Session "+string(st)))
		}
		lastNotified.Store(id, st)
	}
}

func (u *ui) updateTitle() {
	n := 0
	for _, s := range u.sessions {
		if s.Snapshot().Status.NeedsUser() {
			n++
		}
	}
	if n == 0 {
		u.win.SetTitle("Planner")
	} else {
		u.win.SetTitle(fmt.Sprintf("Planner — %d waiting for you", n))
	}
}

func (u *ui) closeAll() {
	for _, s := range u.sessions {
		s.Close()
	}
}
