package main

import (
	"image/color"
	"strings"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/theme"
	"fyne.io/fyne/v2/widget"

	"planner-desktop-spike/session"
)

// sessionView renders one session: header with status, transcript, the
// pending-permission bar, and the reply box.
//
// The transcript is a VBox inside a scroll container, not a widget.List:
// rows are variable-height wrapped markdown, which List handles poorly
// (it needs SetItemHeight per row after measuring). Rows are cached by
// entry revision so streaming only re-parses the entry that changed.
type sessionView struct {
	u *ui
	s *session.Session

	root       fyne.CanvasObject
	header     *fyne.Container
	title      *widget.Label
	status     *widget.Label
	activity   *widget.Activity
	cwd        *widget.Label
	transcript *fyne.Container
	scroll     *container.Scroll
	reply      *widget.Entry
	send       *widget.Button
	stop       *widget.Button
	hint       *widget.Label

	revs []int
}

func newSessionView(u *ui, s *session.Session) *sessionView {
	v := &sessionView{u: u, s: s}
	v.title = heading("")
	v.status = widget.NewLabel("")
	v.status.TextStyle = fyne.TextStyle{Bold: true}
	v.activity = widget.NewActivity()
	v.cwd = widget.NewLabel("")
	v.cwd.Importance = widget.LowImportance
	v.cwd.Truncation = fyne.TextTruncateEllipsis
	v.stop = widget.NewButtonWithIcon("Stop", theme.MediaStopIcon(), s.Cancel)
	closeBtn := widget.NewButtonWithIcon("End", theme.CancelIcon(), s.Close)

	v.transcript = container.NewVBox()
	v.scroll = container.NewVScroll(container.NewPadded(v.transcript))

	v.reply = widget.NewMultiLineEntry()
	v.reply.Wrapping = fyne.TextWrapWord
	v.reply.SetMinRowsVisible(3)
	v.reply.OnSubmitted = func(string) { v.submit() } // Shift+Enter submits in a multi-line Entry
	v.send = widget.NewButtonWithIcon("Send", theme.MailSendIcon(), v.submit)
	v.send.Importance = widget.HighImportance
	v.hint = widget.NewLabel("")
	v.hint.Importance = widget.LowImportance

	v.title.Truncation = fyne.TextTruncateEllipsis
	v.header = container.NewVBox(
		container.NewBorder(nil, nil, nil, container.NewHBox(v.activity, v.status, v.stop, closeBtn), v.title),
		v.cwd,
		widget.NewSeparator(),
	)
	footer := container.NewVBox(
		widget.NewSeparator(),
		v.hint,
		container.NewBorder(nil, nil, nil, v.send, v.reply),
	)
	v.root = container.NewBorder(v.header, footer, nil, nil, v.scroll)
	v.refresh()
	return v
}

func (v *sessionView) submit() {
	text := v.reply.Text
	if text == "" {
		return
	}
	if err := v.s.Prompt(text); err != nil {
		v.hint.SetText(err.Error())
		return
	}
	v.reply.SetText("")
}

// refresh must run on the Fyne main goroutine.
func (v *sessionView) refresh() {
	snap := v.s.Snapshot()
	v.title.SetText(snap.Title)
	v.cwd.SetText(snap.Cwd)
	v.status.SetText(badgeText(snap.Status))
	v.status.Importance = badgeImportance(snap.Status)
	v.status.Refresh()
	running := snap.Status == session.StatusRunning || snap.Status == session.StatusStarting
	if running {
		v.activity.Show()
		v.activity.Start()
		v.stop.Enable()
	} else {
		v.activity.Stop()
		v.activity.Hide()
		v.stop.Disable()
	}
	// Labels changing width do not re-layout their parent container in Fyne;
	// refresh the header so the status badge is not clipped.
	v.header.Refresh()
	for _, o := range v.header.Objects {
		o.Refresh()
	}

	canReply := snap.Status == session.StatusAwaitingInput || snap.Status == session.StatusQuestion
	switch snap.Status {
	case session.StatusQuestion:
		v.hint.SetText("The agent asked a question. Your answer goes back as the next prompt (Shift+Enter to send).")
		v.reply.SetPlaceHolder("Answer the agent…")
	case session.StatusAwaitingInput:
		v.hint.SetText("Turn finished. Reply to continue (Shift+Enter to send).")
		v.reply.SetPlaceHolder("Reply…")
	case session.StatusNeedsApproval:
		v.hint.SetText("Waiting for you to approve or reject a tool call above.")
		v.reply.SetPlaceHolder("")
	case session.StatusError, session.StatusExited:
		v.hint.SetText("Session ended.")
		v.reply.SetPlaceHolder("")
	default:
		v.hint.SetText("Agent is working…")
		v.reply.SetPlaceHolder("")
	}
	if canReply {
		v.reply.Enable()
		v.send.Enable()
	} else {
		v.reply.Disable()
		v.send.Disable()
	}

	atBottom := v.scroll.Offset.Y+v.scroll.Size().Height >= v.scroll.Content.MinSize().Height-40
	grew := false
	for i, e := range snap.Entries {
		if i < len(v.revs) && v.revs[i] == e.Rev {
			continue
		}
		row := v.renderEntry(i, e)
		if i < len(v.revs) {
			v.transcript.Objects[i] = row
			v.revs[i] = e.Rev
		} else {
			v.transcript.Add(row)
			v.revs = append(v.revs, e.Rev)
		}
		grew = true
	}
	if grew {
		v.transcript.Refresh()
		// Follow the stream, unless the user has scrolled up to read.
		if atBottom {
			v.scroll.ScrollToBottom()
		}
	}
	if canReply && v.u.selectedSes == v.s.ID() {
		v.u.win.Canvas().Focus(v.reply)
	}
}

func markdown(text string) *widget.RichText {
	rt := widget.NewRichTextFromMarkdown(text)
	rt.Wrapping = fyne.TextWrapWord
	return rt
}

// tinted puts content on a rounded, lightly coloured panel.
func tinted(c color.Color, content fyne.CanvasObject) fyne.CanvasObject {
	bg := canvas.NewRectangle(c)
	bg.CornerRadius = theme.InputRadiusSize()
	return container.NewStack(bg, container.NewPadded(content))
}

func withAlpha(c color.Color, a uint8) color.Color {
	r, g, b, _ := c.RGBA()
	return color.NRGBA{R: uint8(r >> 8), G: uint8(g >> 8), B: uint8(b >> 8), A: a}
}

func (v *sessionView) renderEntry(idx int, e session.Entry) fyne.CanvasObject {
	switch e.Kind {
	case session.EntryUser:
		label := widget.NewLabelWithStyle("You", fyne.TextAlignLeading, fyne.TextStyle{Bold: true})
		return tinted(withAlpha(theme.Color(theme.ColorNamePrimary), 30), container.NewVBox(label, markdown(e.Text)))

	case session.EntryAgent:
		body := markdown(e.Text)
		if !e.Question {
			return body
		}
		// A question that ended the turn: make it stand out and point at the reply box.
		head := container.NewHBox(widget.NewIcon(theme.QuestionIcon()),
			widget.NewLabelWithStyle("The agent is asking you", fyne.TextAlignLeading, fyne.TextStyle{Bold: true}))
		return tinted(withAlpha(theme.Color(theme.ColorNameWarning), 45), container.NewVBox(head, body))

	case session.EntryThought:
		l := widget.NewLabelWithStyle(e.Text, fyne.TextAlignLeading, fyne.TextStyle{Italic: true})
		l.Wrapping = fyne.TextWrapWord
		l.Importance = widget.LowImportance
		return l

	case session.EntryTool:
		title := e.Text
		if title == "" {
			title = e.ToolID
		}
		icon := theme.SettingsIcon()
		imp := widget.MediumImportance
		switch e.ToolStatus {
		case "completed":
			icon, imp = theme.ConfirmIcon(), widget.SuccessImportance
		case "failed":
			icon, imp = theme.ErrorIcon(), widget.DangerImportance
		case "in_progress":
			icon = theme.MediaPlayIcon()
		}
		status := widget.NewLabel(e.ToolStatus)
		status.Importance = imp
		t := widget.NewRichTextFromMarkdown(title)
		t.Wrapping = fyne.TextWrapWord
		return tinted(withAlpha(theme.Color(theme.ColorNameInputBackground), 255),
			container.NewBorder(nil, nil, widget.NewIcon(icon), status, t))

	case session.EntryPermission:
		head := container.NewHBox(widget.NewIcon(theme.WarningIcon()),
			widget.NewLabelWithStyle("Permission needed", fyne.TextAlignLeading, fyne.TextStyle{Bold: true}))
		title := markdown(e.Text)
		var actions fyne.CanvasObject
		if e.Chosen != "" {
			l := widget.NewLabel("Permission: you chose " + e.Chosen)
			l.Importance = widget.LowImportance
			actions = l
			icon := theme.ConfirmIcon()
			if e.Chosen == "cancelled" || strings.HasPrefix(strings.ToLower(e.Chosen), "reject") {
				icon = theme.CancelIcon()
			}
			return tinted(withAlpha(theme.Color(theme.ColorNameInputBackground), 255),
				container.NewBorder(nil, nil, widget.NewIcon(icon), nil, container.NewVBox(title, actions)))
		}
		row := container.NewHBox()
		for _, o := range e.Options {
			o := o
			b := widget.NewButton(o.Name, func() { _ = v.s.ResolvePermission(idx, o.ID) })
			switch o.Kind {
			case "allow_once":
				b.Importance = widget.HighImportance
				b.SetIcon(theme.ConfirmIcon())
			case "allow_always":
				b.Importance = widget.SuccessImportance
			case "reject_once", "reject_always":
				b.Importance = widget.DangerImportance
				b.SetIcon(theme.CancelIcon())
			}
			row.Add(b)
		}
		return tinted(withAlpha(theme.Color(theme.ColorNameWarning), 60), container.NewVBox(head, title, row))

	default: // system
		l := markdown(e.Text)
		for _, seg := range l.Segments {
			if t, ok := seg.(*widget.TextSegment); ok {
				t.Style.ColorName = theme.ColorNamePlaceHolder
			}
		}
		return l
	}
}
