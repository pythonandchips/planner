//! Drives the ACP client against mock_agent.py.

use std::time::Duration;

use planner_gpui::acp::{SessionEvent, start_session};
use smol::channel::Receiver;

fn mock_command() -> String {
    format!("python3 {}/mock_agent.py", env!("CARGO_MANIFEST_DIR"))
}

fn next(rx: &Receiver<SessionEvent>) -> SessionEvent {
    smol::block_on(async {
        smol::future::or(async { rx.recv().await.expect("channel closed") }, async {
            smol::Timer::after(Duration::from_secs(10)).await;
            panic!("timed out waiting for an event")
        })
        .await
    })
}

/// Collect events until the turn ends, answering permission requests with `choice`.
fn run_turn(rx: &Receiver<SessionEvent>, choice: Option<&str>) -> (String, Vec<SessionEvent>) {
    let mut text = String::new();
    let mut seen = Vec::new();
    loop {
        let ev = next(rx);
        match &ev {
            SessionEvent::AgentText(t) => text.push_str(t),
            SessionEvent::Permission(p) => p.answer(choice.map(str::to_owned)),
            SessionEvent::TurnEnded { .. } => {
                seen.push(ev);
                return (text, seen);
            }
            SessionEvent::Error(e) => panic!("session error: {e}"),
            _ => {}
        }
        seen.push(ev);
    }
}

#[test]
fn streams_asks_permission_and_takes_a_reply() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, rx) =
        start_session(&mock_command(), dir.path().to_path_buf(), "plan it".into()).unwrap();

    match next(&rx) {
        SessionEvent::Ready { agent_name, session_id } => {
            assert_eq!(agent_name.as_deref(), Some("mock-agent"));
            assert_eq!(session_id, "mock-session");
        }
        other => panic!("expected Ready, got {other:?}"),
    }

    let (text, seen) = run_turn(&rx, Some("allow"));
    assert!(text.starts_with("Reading the plan folder."), "{text}");
    assert!(text.contains("Permission: allow."), "{text}");
    assert!(text.ends_with("should the next iteration cover the reply box?"), "{text}");

    let perm = seen
        .iter()
        .find_map(|e| match e {
            SessionEvent::Permission(p) => Some(p.clone()),
            _ => None,
        })
        .expect("permission request");
    assert_eq!(perm.title, "Write ITERATION-002.md");
    let kinds: Vec<_> = perm.options.iter().map(|o| o.kind.as_str()).collect();
    assert_eq!(kinds, ["allow_once", "allow_always", "reject_once"]);

    assert!(seen.iter().any(|e| matches!(e,
        SessionEvent::ToolCall { id, status, .. } if id == "call-1" && status == "pending")));
    assert!(seen.iter().any(|e| matches!(e,
        SessionEvent::ToolCallUpdate { status: Some(s), .. } if s == "completed")));
    assert!(matches!(seen.last(), Some(SessionEvent::TurnEnded { stop_reason }) if stop_reason == "end_turn"));

    handle.prompt("yes please");
    let (text, _) = run_turn(&rx, None);
    assert_eq!(text, "You said: yes please");

    handle.close();
    loop {
        if let SessionEvent::Closed = next(&rx) {
            break;
        }
    }
}

#[test]
fn rejected_permission_fails_the_tool_call() {
    let dir = tempfile::tempdir().unwrap();
    let (_handle, rx) =
        start_session(&mock_command(), dir.path().to_path_buf(), "go".into()).unwrap();
    let (text, seen) = run_turn(&rx, Some("reject"));
    assert!(text.contains("Permission: reject."), "{text}");
    assert!(seen.iter().any(|e| matches!(e,
        SessionEvent::ToolCallUpdate { status: Some(s), .. } if s == "failed")));
}

#[test]
fn two_sessions_run_concurrently() {
    let dir = tempfile::tempdir().unwrap();
    let (_a, rx_a) =
        start_session(&mock_command(), dir.path().to_path_buf(), "a".into()).unwrap();
    let (_b, rx_b) =
        start_session(&mock_command(), dir.path().to_path_buf(), "b".into()).unwrap();
    // Session B finishes its turn while A is still blocked on its permission prompt.
    let perm_a = loop {
        if let SessionEvent::Permission(p) = next(&rx_a) {
            break p;
        }
    };
    let (text_b, _) = run_turn(&rx_b, Some("allow"));
    assert!(text_b.contains("Permission: allow."));
    perm_a.answer(None); // cancel
    let (text_a, _) = run_turn(&rx_a, None);
    assert!(text_a.contains("Permission: cancelled."), "{text_a}");
}

#[test]
fn bad_command_reports_an_error() {
    let dir = tempfile::tempdir().unwrap();
    let (_h, rx) =
        start_session("/no/such/agent-binary", dir.path().to_path_buf(), "x".into()).unwrap();
    let mut got_error = false;
    loop {
        match next(&rx) {
            SessionEvent::Error(_) => got_error = true,
            SessionEvent::Closed => break,
            _ => {}
        }
    }
    assert!(got_error);
}
