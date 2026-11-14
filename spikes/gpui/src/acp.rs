//! A UI-agnostic ACP client session.
//!
//! Each session runs its own agent process on its own thread. The UI talks to
//! it through two channels: it sends [`Command`]s through a [`SessionHandle`]
//! and receives [`SessionEvent`]s.

use std::path::PathBuf;
use std::str::FromStr;
use std::thread;

use agent_client_protocol::schema::ProtocolVersion;
use agent_client_protocol::v1::ConnectionTo;
use agent_client_protocol::v1::schema::{
    CancelNotification, ContentBlock, InitializeRequest, NewSessionRequest, PermissionOptionKind,
    PromptRequest, RequestPermissionOutcome, RequestPermissionRequest, RequestPermissionResponse,
    SelectedPermissionOutcome, SessionNotification, SessionUpdate, StopReason, TextContent,
    ToolCallStatus,
};
use agent_client_protocol::{AcpAgent, Agent};
use smol::channel::{Receiver, Sender, unbounded};

/// Default agent: the Claude Code ACP adapter (formerly
/// `@zed-industries/claude-code-acp`, renamed in 2026).
pub const DEFAULT_AGENT_COMMAND: &str = "npx -y @agentclientprotocol/claude-agent-acp";

#[derive(Debug, Clone)]
pub struct PermissionChoice {
    pub id: String,
    pub name: String,
    /// `allow_once`, `allow_always`, `reject_once`, `reject_always`.
    pub kind: String,
}

/// A permission request waiting for the user. Call [`PermissionRequest::answer`] once.
#[derive(Debug, Clone)]
pub struct PermissionRequest {
    pub tool_call_id: String,
    pub title: String,
    pub options: Vec<PermissionChoice>,
    reply: Sender<Option<String>>,
}

impl PermissionRequest {
    /// Pick an option by id, or `None` to cancel the request.
    pub fn answer(&self, option_id: Option<String>) {
        let _ = self.reply.try_send(option_id);
    }
}

#[derive(Debug, Clone)]
pub enum SessionEvent {
    /// Connected and a session was created.
    Ready { agent_name: Option<String>, session_id: String },
    AgentText(String),
    Thought(String),
    ToolCall { id: String, title: String, status: String },
    ToolCallUpdate { id: String, title: Option<String>, status: Option<String> },
    Plan(Vec<String>),
    Permission(PermissionRequest),
    /// The prompt turn finished: the agent is waiting for the user.
    TurnEnded { stop_reason: String },
    Error(String),
    /// The connection closed; no more events follow.
    Closed,
}

enum Command {
    Prompt(String),
    Cancel,
}

/// The UI's handle on a running session. Dropping it shuts the agent down.
#[derive(Clone)]
pub struct SessionHandle {
    commands: Sender<Command>,
}

impl SessionHandle {
    pub fn prompt(&self, text: impl Into<String>) {
        let _ = self.commands.try_send(Command::Prompt(text.into()));
    }

    pub fn cancel(&self) {
        let _ = self.commands.try_send(Command::Cancel);
    }

    /// Close the command channel, which ends the session and kills the agent.
    pub fn close(&self) {
        self.commands.close();
    }
}

/// Start an agent process speaking ACP over stdio, open a session in `cwd`
/// and send `first_prompt`.
pub fn start_session(
    agent_command: &str,
    cwd: PathBuf,
    first_prompt: String,
) -> anyhow::Result<(SessionHandle, Receiver<SessionEvent>)> {
    let agent = AcpAgent::from_str(agent_command)
        .map_err(|e| anyhow::anyhow!("bad agent command {agent_command:?}: {e:?}"))?;
    let (cmd_tx, cmd_rx) = unbounded::<Command>();
    let (ev_tx, ev_rx) = unbounded::<SessionEvent>();
    cmd_tx.try_send(Command::Prompt(first_prompt)).ok();

    thread::Builder::new()
        .name("acp-session".into())
        .spawn(move || {
            let result = smol::block_on(run(agent, cwd, cmd_rx, ev_tx.clone()));
            if let Err(e) = result {
                let _ = ev_tx.try_send(SessionEvent::Error(format!("{e:?}")));
            }
            let _ = ev_tx.try_send(SessionEvent::Closed);
        })?;

    Ok((SessionHandle { commands: cmd_tx }, ev_rx))
}

fn status_name(status: ToolCallStatus) -> String {
    serde_json::to_value(status)
        .ok()
        .and_then(|v| v.as_str().map(str::to_owned))
        .unwrap_or_else(|| format!("{status:?}"))
}

fn kind_name(kind: PermissionOptionKind) -> String {
    serde_json::to_value(kind)
        .ok()
        .and_then(|v| v.as_str().map(str::to_owned))
        .unwrap_or_else(|| format!("{kind:?}"))
}

fn stop_name(reason: StopReason) -> String {
    serde_json::to_value(reason)
        .ok()
        .and_then(|v| v.as_str().map(str::to_owned))
        .unwrap_or_else(|| format!("{reason:?}"))
}

fn text_of(block: &ContentBlock) -> Option<String> {
    match block {
        ContentBlock::Text(t) => Some(t.text.clone()),
        _ => None,
    }
}

fn to_event(update: SessionUpdate) -> Option<SessionEvent> {
    match update {
        SessionUpdate::AgentMessageChunk(c) => text_of(&c.content).map(SessionEvent::AgentText),
        SessionUpdate::AgentThoughtChunk(c) => text_of(&c.content).map(SessionEvent::Thought),
        SessionUpdate::ToolCall(t) => Some(SessionEvent::ToolCall {
            id: t.tool_call_id.0.to_string(),
            title: t.title,
            status: status_name(t.status),
        }),
        SessionUpdate::ToolCallUpdate(u) => Some(SessionEvent::ToolCallUpdate {
            id: u.tool_call_id.0.to_string(),
            title: u.fields.title,
            status: u.fields.status.map(status_name),
        }),
        SessionUpdate::Plan(p) => Some(SessionEvent::Plan(
            p.entries.into_iter().map(|e| e.content).collect(),
        )),
        _ => None,
    }
}

async fn run(
    agent: AcpAgent,
    cwd: PathBuf,
    commands: Receiver<Command>,
    events: Sender<SessionEvent>,
) -> Result<(), agent_client_protocol::Error> {
    let notif_events = events.clone();
    let perm_events = events.clone();

    agent_client_protocol::Client
        .v1()
        .name("planner-gpui")
        .on_receive_notification(
            async move |n: SessionNotification, _cx| {
                if let Some(ev) = to_event(n.update) {
                    let _ = notif_events.send(ev).await;
                }
                Ok(())
            },
            agent_client_protocol::on_receive_notification!(),
        )
        .on_receive_request(
            async move |req: RequestPermissionRequest, responder, cx| {
                let (reply_tx, reply_rx) = smol::channel::bounded::<Option<String>>(1);
                let title = req
                    .tool_call
                    .fields
                    .title
                    .clone()
                    .unwrap_or_else(|| req.tool_call.tool_call_id.0.to_string());
                let request = PermissionRequest {
                    tool_call_id: req.tool_call.tool_call_id.0.to_string(),
                    title,
                    options: req
                        .options
                        .iter()
                        .map(|o| PermissionChoice {
                            id: o.option_id.0.to_string(),
                            name: o.name.clone(),
                            kind: kind_name(o.kind),
                        })
                        .collect(),
                    reply: reply_tx,
                };
                let _ = perm_events.send(SessionEvent::Permission(request)).await;
                // Wait for the user off the dispatch loop so other updates keep flowing.
                cx.spawn(async move {
                    let outcome = match reply_rx.recv().await.ok().flatten() {
                        Some(id) => RequestPermissionOutcome::Selected(
                            SelectedPermissionOutcome::new(id),
                        ),
                        None => RequestPermissionOutcome::Cancelled,
                    };
                    responder.respond(RequestPermissionResponse::new(outcome))
                })?;
                Ok(())
            },
            agent_client_protocol::on_receive_request!(),
        )
        .connect_with(agent, async move |connection: ConnectionTo<Agent>| {
            let init = connection
                .send_request(InitializeRequest::new(ProtocolVersion::V1))
                .block_task()
                .await?;
            let session = connection
                .send_request(NewSessionRequest::new(cwd))
                .block_task()
                .await?;
            let session_id = session.session_id;
            let _ = events
                .send(SessionEvent::Ready {
                    agent_name: init.agent_info.map(|i| i.name),
                    session_id: session_id.0.to_string(),
                })
                .await;

            while let Ok(command) = commands.recv().await {
                match command {
                    Command::Prompt(text) => {
                        let request = PromptRequest::new(
                            session_id.clone(),
                            vec![ContentBlock::Text(TextContent::new(text))],
                        );
                        let conn = connection.clone();
                        let events = events.clone();
                        // Spawned so Cancel can still be sent while the turn runs.
                        connection.spawn(async move {
                            let event = match conn.send_request(request).block_task().await {
                                Ok(r) => SessionEvent::TurnEnded {
                                    stop_reason: stop_name(r.stop_reason),
                                },
                                Err(e) => SessionEvent::Error(format!("prompt failed: {e:?}")),
                            };
                            let _ = events.send(event).await;
                            Ok(())
                        })?;
                    }
                    Command::Cancel => {
                        connection.send_notification(CancelNotification::new(session_id.clone()))?;
                    }
                }
            }
            Ok(())
        })
        .await
}
