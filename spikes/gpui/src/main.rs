//! Planner desktop spike.
//!
//! Usage: planner-gpui [parent-folder] [--agent "<command>"]
//! The agent command can also come from PLANNER_AGENT_COMMAND.

use std::path::PathBuf;

use gpui_kit::*;
use planner_gpui::acp;
use planner_gpui::ui::PlannerApp;

fn parse_args() -> (PathBuf, String) {
    let mut args = std::env::args().skip(1);
    let mut parent = None;
    let mut agent = std::env::var("PLANNER_AGENT_COMMAND").ok();
    while let Some(arg) = args.next() {
        if arg == "--agent" {
            agent = args.next();
        } else {
            parent = Some(PathBuf::from(arg));
        }
    }
    let parent = parent
        .unwrap_or_else(|| std::env::current_dir().expect("cwd"))
        .canonicalize()
        .expect("parent folder must exist");
    (parent, agent.unwrap_or_else(|| acp::DEFAULT_AGENT_COMMAND.to_string()))
}

fn main() {
    let (parent, agent_command) = parse_args();
    gpui_kit::application()
        .with_assets(gpui_kit::assets::Assets)
        .run(move |cx| {
            gpui_kit::init(cx);
            let bounds = Bounds::centered(None, size(px(1440.), px(900.)), cx);
            let options = WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                titlebar: Some(TitlebarOptions {
                    title: Some("Planner".into()),
                    ..Default::default()
                }),
                ..Default::default()
            };
            gpui_kit::open_window(options, cx, |window, cx| {
                cx.new(|cx| PlannerApp::new(parent, agent_command, window, cx))
            })
            .expect("failed to open window");
            cx.on_window_closed(|cx, _| cx.quit()).detach();
            cx.activate(true);
        });
}
