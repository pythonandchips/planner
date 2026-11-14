package main

import (
	"os"
	"path/filepath"
	"strings"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/theme"
	"fyne.io/fyne/v2/widget"

	"planner-desktop-spike/plans"
)

// docView shows one markdown file: a rendered preview, and for ITERATION
// files an editor tab with save.
type docView struct {
	u        *ui
	path     string
	editable bool
	dirty    bool

	root    fyne.CanvasObject
	title   *widget.Label
	state   *widget.Label
	preview *widget.RichText
	editor  *widget.Entry
	tabs    *container.AppTabs
	saveBtn *widget.Button
}

func newDocView(u *ui) *docView {
	d := &docView{u: u}
	d.title = heading("")
	d.state = widget.NewLabel("")
	d.state.Importance = widget.LowImportance
	d.preview = widget.NewRichText()
	d.preview.Wrapping = fyne.TextWrapWord
	d.editor = widget.NewMultiLineEntry()
	d.editor.Wrapping = fyne.TextWrapWord
	d.editor.TextStyle = fyne.TextStyle{Monospace: true}
	d.editor.OnChanged = func(string) {
		if !d.dirty {
			d.dirty = true
			d.updateState()
		}
	}
	d.saveBtn = widget.NewButtonWithIcon("Save", theme.DocumentSaveIcon(), d.save)
	d.saveBtn.Importance = widget.HighImportance
	d.tabs = container.NewAppTabs(
		container.NewTabItemWithIcon("Preview", theme.VisibilityIcon(), container.NewVScroll(container.NewPadded(d.preview))),
		container.NewTabItemWithIcon("Edit", theme.DocumentCreateIcon(), d.editor),
	)
	d.tabs.OnSelected = func(t *container.TabItem) {
		if t.Text == "Preview" {
			d.preview.ParseMarkdown(d.editor.Text)
		} else {
			d.editor.CursorRow = strings.Count(d.editor.Text, "\n")
			d.editor.CursorColumn = 0
			d.editor.Refresh()
			d.u.win.Canvas().Focus(d.editor)
		}
	}
	session := widget.NewButtonWithIcon("Start session…", theme.MediaPlayIcon(), func() { u.showNewSession(u.currentFolder()) })
	header := container.NewBorder(nil, nil, d.title, container.NewHBox(d.state, d.saveBtn, session))
	d.root = container.NewBorder(header, nil, nil, nil, d.tabs)
	return d
}

func (d *docView) load(path string) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	d.path = path
	d.editable = plans.File{Name: filepath.Base(path), Kind: kindOf(path)}.Editable()
	d.title.SetText(filepath.Base(filepath.Dir(path)) + " / " + filepath.Base(path))
	d.editor.SetText(string(b))
	d.preview.ParseMarkdown(string(b))
	d.dirty = false
	if d.editable {
		d.tabs.EnableIndex(1)
		d.saveBtn.Show()
	} else {
		d.tabs.DisableIndex(1)
		d.saveBtn.Hide()
	}
	d.tabs.SelectIndex(0)
	d.updateState()
	return nil
}

func kindOf(path string) string {
	for _, f := range plans.ListFiles(filepath.Dir(path)) {
		if f.Path == path {
			return f.Kind
		}
	}
	return ""
}

func (d *docView) setEditing(on bool) {
	if on && d.editable {
		d.tabs.SelectIndex(1)
	}
}

func (d *docView) updateState() {
	switch {
	case !d.editable:
		d.state.SetText("read only")
	case d.dirty:
		d.state.SetText("edited")
	default:
		d.state.SetText("saved")
	}
}

func (d *docView) save() {
	if d.path == "" || !d.editable || !d.dirty {
		return
	}
	if err := os.WriteFile(d.path, []byte(d.editor.Text), 0o644); err != nil {
		dialog.ShowError(err, d.u.win)
		return
	}
	d.dirty = false
	d.preview.ParseMarkdown(d.editor.Text)
	d.updateState()
}

// confirmDiscard is called before navigating away. Fyne dialogs are
// asynchronous, so rather than a blocking "save changes?" prompt the spike
// autosaves the ITERATION file, like Xcode or Notes.
func (d *docView) confirmDiscard() bool {
	if d.dirty {
		d.save()
	}
	return !d.dirty
}
