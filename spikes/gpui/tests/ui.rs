//! Drives the real window headlessly with gpui-kit's test support:
//! click a plan file, start a session against mock_agent.py, answer the
//! permission prompt with its button, then reply when the turn ends.

use std::fs;
use std::time::{Duration, Instant};

use gpui_kit::test::TestWindowExt;
use gpui_kit::{
    AppContext as _, Bounds, Entity, Point, SharedString, TestAppContext, WindowBounds, WindowOptions,
    px, size,
};
use planner_gpui::ui::{PlannerApp, Status};

fn mock_command() -> String {
    format!("python3 {}/mock_agent.py", env!("CARGO_MANIFEST_DIR"))
}

/// Pump the GPUI test executor in real time until `done` holds (agent runs on a real thread).
fn wait_until(
    cx: &mut TestAppContext,
    app: &Entity<PlannerApp>,
    what: &str,
    mut done: impl FnMut(&PlannerApp) -> bool,
) {
    let start = Instant::now();
    loop {
        cx.run_until_parked();
        if cx.read(|cx| done(app.read(cx))) {
            return;
        }
        if start.elapsed() > Duration::from_secs(10) {
            let dump = cx.read(|cx| {
                let a = app.read(cx);
                (0..a.session_count()).map(|i| a.transcript(i)).collect::<Vec<_>>().join("\n---\n")
            });
            panic!("timed out waiting for {what}\n{dump}");
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

#[gpui_kit::test]
fn full_session_flow_through_the_ui(cx: &mut TestAppContext) {
    // The agent runs on real threads, so let them wake the test scheduler.
    cx.executor().allow_parking();
    cx.update(gpui_kit::init);
    let tmp = tempfile::tempdir().unwrap();
    let plan = tmp.path().join("repo-a/docs/plans/20261114-desktop");
    fs::create_dir_all(&plan).unwrap();
    let iteration = plan.join("ITERATION-001.md");
    fs::write(&iteration, "# Iteration one\n\nBuild the **desktop** view.\n").unwrap();

    let parent = tmp.path().to_path_buf();
    let window = cx
        .update(|cx| {
            gpui_kit::open_window(
                WindowOptions {
                    window_bounds: Some(WindowBounds::Windowed(Bounds {
                        origin: Point::default(),
                        size: size(px(1440.), px(900.)),
                    })),
                    ..Default::default()
                },
                cx,
                |window, cx| cx.new(|cx| PlannerApp::new(parent, mock_command(), window, cx)),
            )
        })
        .unwrap();
    let (handle, app) = window;

    // Click the file in the sidebar; its id is its path.
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        window.click(SharedString::from(iteration.display().to_string()), cx);
    })
    .unwrap();
    cx.read(|cx| {
        assert_eq!(app.read(cx).selected_file(), Some(iteration.as_path()));
        assert!(app.read(cx).file_text().contains("Build the **desktop** view."));
    });

    // Start two sessions from the toolbar buttons.
    cx.update_window(handle, |_, window, cx| {
        window.click("explore", cx);
        window.click("plan", cx);
    })
    .unwrap();
    assert_eq!(cx.read(|cx| app.read(cx).session_count()), 2);

    // Session 1 (plan) is active; wait for its permission prompt.
    wait_until(cx, &app, "permission", |a| a.session_status(1) == Status::NeedsPermission);
    wait_until(cx, &app, "permission on session 0", |a| {
        a.session_status(0) == Status::NeedsPermission
    });

    // Answer through the rendered "Allow once" button.
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        window.click("perm-1-allow", cx);
    })
    .unwrap();
    wait_until(cx, &app, "turn end", |a| a.session_status(1) == Status::AwaitingInput);
    let transcript = cx.read(|cx| app.read(cx).transcript(1));
    assert!(transcript.contains("tool: Write ITERATION-002.md [completed]"), "{transcript}");
    assert!(transcript.contains("permission: Write ITERATION-002.md -> Allow once"), "{transcript}");
    assert!(transcript.contains("should the next iteration cover the reply box?"), "{transcript}");
    // Session 0 is still blocked on its own permission prompt.
    assert_eq!(cx.read(|cx| app.read(cx).session_status(0)), Status::NeedsPermission);

    // Type a reply and send it with the button.
    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        window.click("reply", cx);
        window.input("yes, cover it", cx);
        window.click("send", cx);
    })
    .unwrap();
    wait_until(cx, &app, "reply turn", |a| {
        a.session_status(1) == Status::AwaitingInput && a.transcript(1).contains("You said: yes, cover it")
    });

    // Switch to session 0 and reject.
    cx.update_window(handle, |_, window, cx| {
        window.click(("session", 0usize), cx);
        window.render_frame(cx);
        window.click("perm-0-reject", cx);
    })
    .unwrap();
    wait_until(cx, &app, "session 0 turn end", |a| a.session_status(0) == Status::AwaitingInput);
    let transcript = cx.read(|cx| app.read(cx).transcript(0));
    assert!(transcript.contains("[failed]"), "{transcript}");
}

#[gpui_kit::test]
fn edit_and_save_an_iteration(cx: &mut TestAppContext) {
    cx.update(gpui_kit::init);
    let tmp = tempfile::tempdir().unwrap();
    let plan = tmp.path().join("docs/plans/p1");
    fs::create_dir_all(&plan).unwrap();
    let iteration = plan.join("ITERATION-001.md");
    fs::write(&iteration, "old\n").unwrap();
    let parent = tmp.path().to_path_buf();
    let (handle, app) = cx
        .update(|cx| {
            gpui_kit::open_window(
                WindowOptions {
                    window_bounds: Some(WindowBounds::Windowed(Bounds {
                        origin: Point::default(),
                        size: size(px(1440.), px(900.)),
                    })),
                    ..Default::default()
                },
                cx,
                |window, cx| cx.new(|cx| PlannerApp::new(parent, mock_command(), window, cx)),
            )
        })
        .unwrap();

    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        window.click(SharedString::from(iteration.display().to_string()), cx);
        window.click("new-iteration", cx);
    })
    .unwrap();
    let new_file = plan.join("ITERATION-002.md");
    assert!(new_file.exists());
    cx.read(|cx| assert_eq!(app.read(cx).selected_file(), Some(new_file.as_path())));

    cx.update_window(handle, |_, window, cx| {
        window.render_frame(cx);
        window.input("Typed in the GUI. ", cx);
        window.click("save", cx);
    })
    .unwrap();
    let saved = fs::read_to_string(&new_file).unwrap();
    assert!(saved.contains("# Iteration"), "{saved}");
    assert!(saved.contains("Typed in the GUI."), "{saved}");
}
