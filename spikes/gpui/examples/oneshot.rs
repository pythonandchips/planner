//! Headless check of the ACP client against any agent command.
//!
//! cargo run --example oneshot -- "<agent command>" "<prompt>"
//! Permission requests are cancelled. Prints every event, exits when the turn ends.

use planner_gpui::acp::{DEFAULT_AGENT_COMMAND, SessionEvent, start_session};

fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let command = args.next().unwrap_or_else(|| DEFAULT_AGENT_COMMAND.into());
    let prompt = args.next().unwrap_or_else(|| "Reply with the single word: pong".into());
    let (handle, events) = start_session(&command, std::env::current_dir()?, prompt)?;
    smol::block_on(async {
        while let Ok(event) = events.recv().await {
            println!("{event:?}");
            match event {
                SessionEvent::Permission(p) => p.answer(None),
                SessionEvent::TurnEnded { .. } => {
                    handle.close();
                }
                SessionEvent::Closed => break,
                _ => {}
            }
        }
    });
    Ok(())
}
