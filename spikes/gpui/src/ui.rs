//! The window: plan folders on the left, the selected file in the middle,
//! agent sessions over ACP on the right.

use std::path::{Path, PathBuf};

use gpui_kit::component::button::{Button, ButtonVariants as _};
use gpui_kit::component::input::{Input, InputEvent, InputState, Textarea, TextareaState};
use gpui_kit::component::tag::Tag;
use gpui_kit::component::text::TextView;
use gpui_kit::component::{ActiveTheme as _, Disableable as _, Sizable as _, h_flex, v_flex};
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::TestSupportExt as _;
use gpui_kit::*;

use crate::acp::{self, PermissionRequest, SessionEvent, SessionHandle};
use crate::plans::{self, PlanFolder, file_name};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Status {
    Starting,
    Working,
    NeedsPermission,
    AwaitingInput,
    Closed,
    Failed,
}

impl Status {
    fn tag(self) -> Tag {
        let (tag, label) = match self {
            Status::Starting => (Tag::secondary(), "starting"),
            Status::Working => (Tag::info(), "working"),
            Status::NeedsPermission => (Tag::warning(), "needs permission"),
            Status::AwaitingInput => (Tag::success(), "awaiting input"),
            Status::Closed => (Tag::secondary(), "closed"),
            Status::Failed => (Tag::danger(), "failed"),
        };
        tag.xsmall().child(label)
    }

    fn is_live(self) -> bool {
        !matches!(self, Status::Closed | Status::Failed)
    }
}

enum Entry {
    User(String),
    Agent(String),
    Thought(String),
    Tool { id: String, title: String, status: String },
    Permission { request: PermissionRequest, answer: Option<String> },
    Notice(String),
}

struct Session {
    label: String,
    plan_path: PathBuf,
    handle: SessionHandle,
    status: Status,
    entries: Vec<Entry>,
    _pump: Task<()>,
}

#[derive(Clone, Copy)]
pub enum Mode {
    Explore,
    Plan,
    Run,
}

impl Mode {
    fn name(self) -> &'static str {
        match self {
            Mode::Explore => "explore",
            Mode::Plan => "plan",
            Mode::Run => "run",
        }
    }

    fn prompt(self, folder: &PlanFolder, file: Option<&Path>, extra: &str) -> String {
        let file = file
            .map(|f| f.display().to_string())
            .or_else(|| folder.latest_iteration().map(|f| f.display().to_string()))
            .unwrap_or_else(|| "(no iteration file yet)".into());
        let task = match self {
            Mode::Explore => "Explore the codebase for this iteration and write the next FINDINGS-NNN.md file.",
            Mode::Plan => "Write the next PLAN-NNN.md implementation plan for this iteration.",
            Mode::Run => "Carry out the latest PLAN-NNN.md for this iteration.",
        };
        let mut prompt = format!(
            "Plan folder: {}\nIteration file: {file}\n\n{task}\nIf you need a decision from me, ask a plain-text question at the end of your turn and stop.",
            folder.path.display()
        );
        if !extra.trim().is_empty() {
            prompt.push_str("\n\n");
            prompt.push_str(extra.trim());
        }
        prompt
    }
}

pub struct PlannerApp {
    parent: PathBuf,
    agent_command: String,
    folders: Vec<PlanFolder>,
    selected_folder: Option<usize>,
    selected_file: Option<PathBuf>,
    file_text: SharedString,
    editing: bool,
    editor: Entity<TextareaState>,
    status_line: SharedString,
    extra_prompt: Entity<InputState>,
    sessions: Vec<Session>,
    active_session: Option<usize>,
    reply: Entity<TextareaState>,
    transcript_scroll: ScrollHandle,
    _subscriptions: Vec<Subscription>,
}

impl PlannerApp {
    pub fn new(parent: PathBuf, agent_command: String, window: &mut Window, cx: &mut Context<Self>) -> Self {
        let editor = cx.new(|cx| TextareaState::new(window, cx));
        let extra_prompt = cx.new(|cx| {
            InputState::new(window, cx).placeholder("Extra instructions for the new session (optional)")
        });
        let reply = cx.new(|cx| {
            TextareaState::new(window, cx)
                .auto_grow(2, 8)
                .placeholder("Reply to the agent (Cmd+Enter to send)")
        });
        let subscriptions = vec![cx.subscribe_in(
            &reply,
            window,
            |this: &mut Self, _, event: &InputEvent, window, cx| {
                if let InputEvent::PressEnter { secondary: true, .. } = event {
                    this.send_reply(window, cx);
                }
            },
        )];
        let mut app = Self {
            folders: Vec::new(),
            parent,
            agent_command,
            selected_folder: None,
            selected_file: None,
            file_text: "".into(),
            editing: false,
            editor,
            status_line: "".into(),
            extra_prompt,
            sessions: Vec::new(),
            active_session: None,
            reply,
            transcript_scroll: ScrollHandle::new(),
            _subscriptions: subscriptions,
        };
        app.refresh();
        app
    }

    fn refresh(&mut self) {
        self.folders = plans::discover(&self.parent);
        self.status_line = format!(
            "{} plan folders under {}",
            self.folders.len(),
            self.parent.display()
        )
        .into();
    }

    pub fn select_file(&mut self, folder: usize, path: PathBuf, cx: &mut Context<Self>) {
        self.selected_folder = Some(folder);
        self.file_text = std::fs::read_to_string(&path)
            .unwrap_or_else(|e| format!("Could not read file: {e}"))
            .into();
        self.selected_file = Some(path);
        self.editing = false;
        cx.notify();
    }

    fn start_editing(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let text = self.file_text.clone();
        self.editor.update(cx, |e, cx| {
            e.set_value(text, window, cx);
            e.focus(window, cx);
        });
        self.editing = true;
        cx.notify();
    }

    fn save(&mut self, cx: &mut Context<Self>) {
        let Some(path) = self.selected_file.clone() else { return };
        let text = self.editor.read(cx).value();
        match std::fs::write(&path, text.as_ref()) {
            Ok(()) => {
                self.file_text = text;
                self.editing = false;
                self.status_line = format!("Saved {}", path.display()).into();
                self.refresh_keep_selection();
            }
            Err(e) => self.status_line = format!("Save failed: {e}").into(),
        }
        cx.notify();
    }

    fn refresh_keep_selection(&mut self) {
        let selected = self.selected_folder.map(|i| self.folders[i].path.clone());
        self.refresh();
        self.selected_folder = selected.and_then(|p| self.folders.iter().position(|f| f.path == p));
    }

    fn new_iteration(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(i) = self.selected_folder else { return };
        let path = plans::next_iteration_path(&self.folders[i]);
        let template = "# Iteration\n\n## Goal\n\n## Notes\n";
        if let Err(e) = std::fs::write(&path, template) {
            self.status_line = format!("Could not create {}: {e}", path.display()).into();
            return cx.notify();
        }
        self.refresh_keep_selection();
        if let Some(i) = self.selected_folder {
            self.select_file(i, path, cx);
            self.start_editing(window, cx);
        }
    }

    pub fn start_session(&mut self, mode: Mode, window: &mut Window, cx: &mut Context<Self>) {
        let Some(fi) = self.selected_folder else {
            self.status_line = "Select a plan folder first".into();
            return cx.notify();
        };
        let folder = self.folders[fi].clone();
        let extra = self.extra_prompt.read(cx).value().to_string();
        let prompt = mode.prompt(&folder, self.selected_file.as_deref(), &extra);
        let (handle, events) =
            match acp::start_session(&self.agent_command, folder.repo_path.clone(), prompt.clone()) {
                Ok(pair) => pair,
                Err(e) => {
                    self.status_line = format!("Could not start agent: {e}").into();
                    return cx.notify();
                }
            };
        let index = self.sessions.len();
        let pump = cx.spawn(async move |this, cx| {
            while let Ok(event) = events.recv().await {
                let alive = this.update(cx, |this, cx| {
                    this.apply_event(index, event);
                    cx.notify();
                });
                if alive.is_err() {
                    break;
                }
            }
        });
        self.sessions.push(Session {
            label: format!("{} · {}", mode.name(), folder.name),
            plan_path: folder.path.clone(),
            handle,
            status: Status::Starting,
            entries: vec![Entry::User(prompt)],
            _pump: pump,
        });
        self.active_session = Some(index);
        self.extra_prompt.update(cx, |s, cx| s.set_value("", window, cx));
        cx.notify();
    }

    fn apply_event(&mut self, index: usize, event: SessionEvent) {
        let is_active = self.active_session == Some(index);
        let session = &mut self.sessions[index];
        match event {
            SessionEvent::Ready { agent_name, .. } => {
                session.status = Status::Working;
                session.entries.push(Entry::Notice(format!(
                    "Connected to {}",
                    agent_name.unwrap_or_else(|| "agent".into())
                )));
            }
            SessionEvent::AgentText(text) => match session.entries.last_mut() {
                Some(Entry::Agent(buf)) => buf.push_str(&text),
                _ => session.entries.push(Entry::Agent(text)),
            },
            SessionEvent::Thought(text) => match session.entries.last_mut() {
                Some(Entry::Thought(buf)) => buf.push_str(&text),
                _ => session.entries.push(Entry::Thought(text)),
            },
            SessionEvent::ToolCall { id, title, status } => {
                session.entries.push(Entry::Tool { id, title, status })
            }
            SessionEvent::ToolCallUpdate { id, title, status } => {
                for entry in session.entries.iter_mut().rev() {
                    if let Entry::Tool { id: tid, title: t, status: s } = entry
                        && *tid == id
                    {
                        if let Some(title) = title {
                            *t = title;
                        }
                        if let Some(status) = status {
                            *s = status;
                        }
                        break;
                    }
                }
            }
            SessionEvent::Plan(items) => {
                session.entries.push(Entry::Notice(format!("Plan:\n- {}", items.join("\n- "))))
            }
            SessionEvent::Permission(request) => {
                session.status = Status::NeedsPermission;
                session.entries.push(Entry::Permission { request, answer: None });
            }
            SessionEvent::TurnEnded { stop_reason } => {
                session.status = Status::AwaitingInput;
                if stop_reason != "end_turn" {
                    session.entries.push(Entry::Notice(format!("Turn ended: {stop_reason}")));
                }
            }
            SessionEvent::Error(e) => {
                session.status = Status::Failed;
                session.entries.push(Entry::Notice(format!("Error: {e}")));
            }
            SessionEvent::Closed => {
                if session.status != Status::Failed {
                    session.status = Status::Closed;
                }
            }
        }
        if is_active {
            self.transcript_scroll.scroll_to_bottom();
        }
    }

    fn answer_permission(&mut self, session: usize, entry: usize, option: Option<(String, String)>, cx: &mut Context<Self>) {
        let s = &mut self.sessions[session];
        if let Some(Entry::Permission { request, answer }) = s.entries.get_mut(entry) {
            request.answer(option.as_ref().map(|(id, _)| id.clone()));
            *answer = Some(option.map_or("cancelled".into(), |(_, name)| name));
            s.status = Status::Working;
        }
        cx.notify();
    }

    fn send_reply(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(i) = self.active_session else { return };
        let text = self.reply.read(cx).value().trim().to_string();
        let session = &mut self.sessions[i];
        if text.is_empty() || session.status != Status::AwaitingInput {
            return;
        }
        session.handle.prompt(text.clone());
        session.entries.push(Entry::User(text));
        session.status = Status::Working;
        self.reply.update(cx, |r, cx| r.set_value("", window, cx));
        self.transcript_scroll.scroll_to_bottom();
        cx.notify();
    }

    // ---- read-only accessors (used by tests) ----

    pub fn selected_file(&self) -> Option<&Path> {
        self.selected_file.as_deref()
    }

    pub fn file_text(&self) -> &str {
        &self.file_text
    }

    pub fn session_count(&self) -> usize {
        self.sessions.len()
    }

    pub fn session_status(&self, index: usize) -> Status {
        self.sessions[index].status
    }

    /// A plain-text dump of a session's transcript.
    pub fn transcript(&self, index: usize) -> String {
        self.sessions[index]
            .entries
            .iter()
            .map(|e| match e {
                Entry::User(t) => format!("user: {t}"),
                Entry::Agent(t) => format!("agent: {t}"),
                Entry::Thought(t) => format!("thought: {t}"),
                Entry::Notice(t) => format!("notice: {t}"),
                Entry::Tool { title, status, .. } => format!("tool: {title} [{status}]"),
                Entry::Permission { request, answer } => format!(
                    "permission: {} -> {}",
                    request.title,
                    answer.as_deref().unwrap_or("pending")
                ),
            })
            .collect::<Vec<_>>()
            .join("\n")
    }

    // ---- rendering ----

    fn render_sidebar(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = cx.theme();
        let mut plans_list = v_flex().gap_1();
        let mut last_repo = String::new();
        for (fi, folder) in self.folders.iter().enumerate() {
            if folder.repo != last_repo {
                last_repo = folder.repo.clone();
                plans_list = plans_list.child(
                    div().pt_2().text_xs().text_color(theme.muted_foreground).child(folder.repo.clone()),
                );
            }
            let live = self
                .sessions
                .iter()
                .filter(|s| s.plan_path == folder.path && s.status.is_live())
                .count();
            let mut header = h_flex()
                .gap_1()
                .text_sm()
                .font_weight(FontWeight::SEMIBOLD)
                .child(folder.name.clone());
            if live > 0 {
                header = header.child(Tag::info().xsmall().child(format!("{live} live")));
            }
            plans_list = plans_list.child(header);
            for file in &folder.files {
                let selected = self.selected_file.as_ref() == Some(file);
                let path = file.clone();
                plans_list = plans_list.child(
                    div()
                        .id(SharedString::from(file.display().to_string()))
                        .test_support()
                        .pl_3()
                        .py_0p5()
                        .rounded_sm()
                        .text_sm()
                        .cursor_pointer()
                        .when(selected, |d| d.bg(theme.list_active))
                        .hover(|d| d.bg(theme.list_hover))
                        .child(file_name(file))
                        .on_click(cx.listener(move |this, _: &ClickEvent, _, cx| {
                            this.select_file(fi, path.clone(), cx)
                        })),
                );
            }
        }

        let mut sessions_list = v_flex().gap_1();
        for (si, session) in self.sessions.iter().enumerate() {
            let active = self.active_session == Some(si);
            sessions_list = sessions_list.child(
                v_flex()
                    .id(("session", si))
                    .test_support()
                    .p_1()
                    .rounded_sm()
                    .cursor_pointer()
                    .when(active, |d| d.bg(theme.list_active))
                    .hover(|d| d.bg(theme.list_hover))
                    .child(div().text_sm().child(session.label.clone()))
                    .child(session.status.tag())
                    .on_click(cx.listener(move |this, _: &ClickEvent, _, cx| {
                        this.active_session = Some(si);
                        this.transcript_scroll.scroll_to_bottom();
                        cx.notify();
                    })),
            );
        }

        v_flex()
            .w(px(280.))
            .h_full()
            .border_r_1()
            .border_color(theme.border)
            .bg(theme.sidebar)
            .child(
                h_flex()
                    .p_2()
                    .justify_between()
                    .child(div().font_weight(FontWeight::BOLD).child("Plans"))
                    .child(
                        Button::new("refresh")
                            .label("Refresh")
                            .xsmall()
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.refresh_keep_selection();
                                cx.notify();
                            })),
                    ),
            )
            .child(
                div()
                    .id("plans-scroll")
                    .flex_1()
                    .overflow_y_scroll()
                    .px_2()
                    .child(plans_list),
            )
            .child(
                v_flex()
                    .p_2()
                    .gap_1()
                    .border_t_1()
                    .border_color(theme.border)
                    .max_h(px(320.))
                    .child(div().font_weight(FontWeight::BOLD).child("Sessions"))
                    .child(div().id("sessions-scroll").overflow_y_scroll().child(sessions_list)),
            )
    }

    fn render_file(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = cx.theme();
        let title = self
            .selected_file
            .as_ref()
            .map(|p| p.strip_prefix(&self.parent).unwrap_or(p).display().to_string())
            .unwrap_or_else(|| "No file selected".into());
        let can_edit = self.selected_file.is_some();

        let mut toolbar = h_flex().gap_2().child(div().flex_1().text_sm().child(title));
        if self.editing {
            toolbar = toolbar
                .child(Button::new("save").label("Save").primary().small().on_click(
                    cx.listener(|this, _, _, cx| this.save(cx)),
                ))
                .child(Button::new("discard").label("Discard").small().on_click(cx.listener(
                    |this, _, _, cx| {
                        this.editing = false;
                        cx.notify();
                    },
                )));
        } else {
            toolbar = toolbar
                .child(
                    Button::new("new-iteration")
                        .label("New iteration")
                        .small()
                        .on_click(cx.listener(|this, _, window, cx| this.new_iteration(window, cx))),
                )
                .when(can_edit, |t| {
                    t.child(Button::new("edit").label("Edit").small().on_click(
                        cx.listener(|this, _, window, cx| this.start_editing(window, cx)),
                    ))
                });
        }

        let body: AnyElement = if self.editing {
            div()
                .flex_1()
                .p_2()
                .child(Textarea::new(&self.editor).h(relative(1.)))
                .into_any_element()
        } else {
            div()
                .id("file-scroll")
                .flex_1()
                .overflow_y_scroll()
                .p_4()
                .child(TextView::markdown("file-view", self.file_text.clone()))
                .into_any_element()
        };

        v_flex()
            .flex_1()
            .h_full()
            .min_w(px(320.))
            .child(
                div()
                    .p_2()
                    .border_b_1()
                    .border_color(theme.border)
                    .child(toolbar),
            )
            .child(body)
            .child(
                div()
                    .px_2()
                    .py_1()
                    .border_t_1()
                    .border_color(theme.border)
                    .text_xs()
                    .text_color(theme.muted_foreground)
                    .child(self.status_line.clone()),
            )
    }

    fn render_entry(&self, si: usize, ei: usize, entry: &Entry, awaiting: bool, cx: &mut Context<Self>) -> AnyElement {
        let theme = cx.theme();
        match entry {
            Entry::User(text) => div()
                .p_2()
                .rounded_md()
                .bg(theme.secondary)
                .text_sm()
                .child(text.clone())
                .into_any_element(),
            Entry::Agent(text) => div()
                .p_2()
                .rounded_md()
                .when(awaiting, |d| d.border_2().border_color(theme.success))
                .child(TextView::markdown(
                    SharedString::from(format!("agent-{si}-{ei}")),
                    SharedString::from(text.clone()),
                ))
                .when(awaiting, |d| {
                    d.child(
                        div()
                            .pt_1()
                            .text_xs()
                            .text_color(theme.success)
                            .child("The agent is waiting for your reply"),
                    )
                })
                .into_any_element(),
            Entry::Thought(text) => div()
                .px_2()
                .text_xs()
                .italic()
                .text_color(theme.muted_foreground)
                .child(text.clone())
                .into_any_element(),
            Entry::Notice(text) => div()
                .px_2()
                .text_xs()
                .text_color(theme.muted_foreground)
                .child(text.clone())
                .into_any_element(),
            Entry::Tool { title, status, .. } => {
                let tag = match status.as_str() {
                    "completed" => Tag::success(),
                    "failed" => Tag::danger(),
                    "in_progress" => Tag::info(),
                    _ => Tag::secondary(),
                };
                h_flex()
                    .gap_2()
                    .px_2()
                    .text_sm()
                    .child(tag.xsmall().child(status.clone()))
                    .child(title.clone())
                    .into_any_element()
            }
            Entry::Permission { request, answer } => {
                let mut card = v_flex()
                    .gap_2()
                    .p_2()
                    .rounded_md()
                    .border_1()
                    .border_color(if answer.is_none() { theme.warning } else { theme.border })
                    .child(
                        div()
                            .text_sm()
                            .font_weight(FontWeight::SEMIBOLD)
                            .child(format!("Permission: {}", request.title)),
                    );
                match answer {
                    Some(choice) => {
                        card = card.child(
                            div().text_xs().text_color(theme.muted_foreground).child(format!("You chose: {choice}")),
                        );
                    }
                    None => {
                        let mut buttons = h_flex().gap_2().flex_wrap();
                        for option in &request.options {
                            let choice = (option.id.clone(), option.name.clone());
                            let button = Button::new(SharedString::from(format!("perm-{si}-{}", option.id)))
                                .label(option.name.clone())
                                .small();
                            let button = match option.kind.as_str() {
                                "allow_once" => button.primary(),
                                "allow_always" => button,
                                _ => button.danger(),
                            };
                            buttons = buttons.child(button.on_click(cx.listener(
                                move |this, _, _, cx| {
                                    this.answer_permission(si, ei, Some(choice.clone()), cx)
                                },
                            )));
                        }
                        buttons = buttons.child(
                            Button::new(SharedString::from(format!("perm-{si}-cancel")))
                                .label("Cancel")
                                .small()
                                .on_click(cx.listener(move |this, _, _, cx| {
                                    this.answer_permission(si, ei, None, cx)
                                })),
                        );
                        card = card.child(buttons);
                    }
                }
                card.into_any_element()
            }
        }
    }

    fn render_sessions(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = cx.theme().clone();
        let launcher = v_flex()
            .gap_2()
            .p_2()
            .border_b_1()
            .border_color(theme.border)
            .child(Input::new(&self.extra_prompt).small())
            .child(
                h_flex()
                    .gap_2()
                    .child(Button::new("explore").label("Explore").small().on_click(
                        cx.listener(|this, _, w, cx| this.start_session(Mode::Explore, w, cx)),
                    ))
                    .child(Button::new("plan").label("Plan").small().on_click(
                        cx.listener(|this, _, w, cx| this.start_session(Mode::Plan, w, cx)),
                    ))
                    .child(Button::new("run").label("Run").small().on_click(
                        cx.listener(|this, _, w, cx| this.start_session(Mode::Run, w, cx)),
                    ))
                    .child(
                        div()
                            .flex_1()
                            .text_xs()
                            .text_color(theme.muted_foreground)
                            .text_right()
                            .child(self.agent_command.clone()),
                    ),
            );

        let Some(si) = self.active_session else {
            return v_flex()
                .w(px(520.))
                .h_full()
                .border_l_1()
                .border_color(theme.border)
                .child(launcher)
                .child(
                    div()
                        .p_4()
                        .text_sm()
                        .text_color(theme.muted_foreground)
                        .child("Select a plan file, then start an Explore, Plan or Run session."),
                );
        };
        let session = &self.sessions[si];
        let awaiting = session.status == Status::AwaitingInput;
        let last_agent = session.entries.iter().rposition(|e| matches!(e, Entry::Agent(_)));
        let entries: Vec<AnyElement> = session
            .entries
            .iter()
            .enumerate()
            .map(|(ei, e)| self.render_entry(si, ei, e, awaiting && Some(ei) == last_agent, cx))
            .collect();

        let working = matches!(session.status, Status::Working | Status::NeedsPermission);
        v_flex()
            .w(px(520.))
            .h_full()
            .border_l_1()
            .border_color(theme.border)
            .child(launcher)
            .child(
                h_flex()
                    .p_2()
                    .gap_2()
                    .child(div().flex_1().font_weight(FontWeight::BOLD).child(session.label.clone()))
                    .child(session.status.tag())
                    .when(working, |d| {
                        d.child(Button::new("cancel-turn").label("Stop").xsmall().danger().on_click(
                            cx.listener(move |this, _, _, cx| {
                                this.sessions[si].handle.cancel();
                                cx.notify();
                            }),
                        ))
                    })
                    .when(session.status.is_live(), |d| {
                        d.child(Button::new("close-session").label("Close").xsmall().on_click(
                            cx.listener(move |this, _, _, cx| {
                                this.sessions[si].handle.close();
                                cx.notify();
                            }),
                        ))
                    }),
            )
            .child(
                div()
                    .id("transcript")
                    .flex_1()
                    .overflow_y_scroll()
                    .track_scroll(&self.transcript_scroll)
                    .p_2()
                    .child(v_flex().gap_2().children(entries)),
            )
            .child(
                v_flex()
                    .p_2()
                    .gap_2()
                    .border_t_1()
                    .border_color(theme.border)
                    .child(div().id("reply").test_support().child(Textarea::new(&self.reply).disabled(!awaiting)))
                    .child(
                        h_flex().justify_end().child(
                            Button::new("send")
                                .label("Send reply")
                                .primary()
                                .small()
                                .disabled(!awaiting)
                                .on_click(cx.listener(|this, _, w, cx| this.send_reply(w, cx))),
                        ),
                    ),
            )
    }
}

impl Render for PlannerApp {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        h_flex()
            .size_full()
            .bg(cx.theme().background)
            .text_color(cx.theme().foreground)
            .child(self.render_sidebar(cx))
            .child(self.render_file(cx))
            .child(self.render_sessions(cx))
    }
}

