//! X11 desktop-window hints. GTK4 no longer exposes the XID, so the window is
//! found by title among this process's windows and marked as a desktop surface
//! with `_NET_WM_WINDOW_TYPE_DESKTOP` plus below/skip-taskbar states.
//!
//! This is best-effort: a window manager may ignore the hint, and X11
//! placement is the WM's job. It runs on its own thread after the window maps.

use std::thread;
use std::time::Duration;

use x11rb::connection::Connection;
use x11rb::protocol::xproto::{AtomEnum, ConfigureWindowAux, ConnectionExt as _, PropMode, Window};
use x11rb::rust_connection::RustConnection;
use x11rb::wrapper::ConnectionExt as _;

/// X11 has no layer shell, so centre the Spotlight panel on its monitor after
/// the window manager has mapped it.
pub fn center_overlay_window(title: String) {
    thread::spawn(move || {
        thread::sleep(Duration::from_millis(300));
        let _ = center_overlay(&title);
    });
}

fn center_overlay(title: &str) -> Result<(), Box<dyn std::error::Error>> {
    let (connection, screen) = x11rb::connect(None)?;
    let root = connection.setup().roots[screen].root;
    let geometry = connection.get_geometry(root)?.reply()?;
    let pid = std::process::id();
    let net_client_list = atom(&connection, "_NET_CLIENT_LIST")?;
    let net_wm_pid = atom(&connection, "_NET_WM_PID")?;
    let net_wm_name = atom(&connection, "_NET_WM_NAME")?;
    let utf8_string = atom(&connection, "UTF8_STRING")?;
    let windows = property_u32(&connection, root, net_client_list, AtomEnum::WINDOW.into())
        .unwrap_or_default();
    for window in windows {
        let Some(window_pid) =
            property_u32(&connection, window, net_wm_pid, AtomEnum::CARDINAL.into())
                .and_then(|values| values.first().copied())
        else {
            continue;
        };
        if window_pid != pid {
            continue;
        }
        if window_title(&connection, window, net_wm_name, utf8_string).as_deref() != Some(title) {
            continue;
        }
        let window_geometry = connection.get_geometry(window)?.reply()?;
        let x = (i32::from(geometry.width) - i32::from(window_geometry.width)).max(0) / 2;
        let y =
            ((i32::from(geometry.height) - i32::from(window_geometry.height)).max(0) / 4).max(24);
        connection.configure_window(window, &ConfigureWindowAux::new().x(x).y(y))?;
    }
    connection.flush()?;
    Ok(())
}

pub fn mark_desktop_window(title: String) {
    thread::spawn(move || {
        // The window is not in _NET_CLIENT_LIST until the WM has mapped it.
        thread::sleep(Duration::from_millis(500));
        let _ = mark(&title);
    });
}

fn mark(title: &str) -> Result<(), Box<dyn std::error::Error>> {
    let (connection, screen) = x11rb::connect(None)?;
    let root = connection.setup().roots[screen].root;
    let pid = std::process::id();

    let net_client_list = atom(&connection, "_NET_CLIENT_LIST")?;
    let net_wm_pid = atom(&connection, "_NET_WM_PID")?;
    let net_wm_name = atom(&connection, "_NET_WM_NAME")?;
    let utf8_string = atom(&connection, "UTF8_STRING")?;
    let net_wm_window_type = atom(&connection, "_NET_WM_WINDOW_TYPE")?;
    let desktop = atom(&connection, "_NET_WM_WINDOW_TYPE_DESKTOP")?;
    let net_wm_state = atom(&connection, "_NET_WM_STATE")?;
    let below = atom(&connection, "_NET_WM_STATE_BELOW")?;
    let skip_taskbar = atom(&connection, "_NET_WM_STATE_SKIP_TASKBAR")?;
    let skip_pager = atom(&connection, "_NET_WM_STATE_SKIP_PAGER")?;

    let mut windows = property_u32(&connection, root, net_client_list, AtomEnum::WINDOW.into())
        .unwrap_or_default();
    if windows.is_empty() {
        let tree = connection.query_tree(root)?.reply()?;
        windows = tree.children;
    }

    for window in windows {
        let Some(window_pid) =
            property_u32(&connection, window, net_wm_pid, AtomEnum::CARDINAL.into())
                .and_then(|values| values.first().copied())
        else {
            continue;
        };
        if window_pid != pid {
            continue;
        }
        if window_title(&connection, window, net_wm_name, utf8_string).as_deref() != Some(title) {
            continue;
        }
        connection.change_property32(
            PropMode::REPLACE,
            window,
            net_wm_window_type,
            u32::from(AtomEnum::ATOM),
            &[desktop],
        )?;
        connection.change_property32(
            PropMode::REPLACE,
            window,
            net_wm_state,
            u32::from(AtomEnum::ATOM),
            &[below, skip_taskbar, skip_pager],
        )?;
    }
    connection.flush()?;
    Ok(())
}

fn atom(connection: &RustConnection, name: &str) -> Result<u32, Box<dyn std::error::Error>> {
    Ok(connection
        .intern_atom(false, name.as_bytes())?
        .reply()?
        .atom)
}

fn property_u32(
    connection: &RustConnection,
    window: Window,
    property: u32,
    type_: u32,
) -> Option<Vec<u32>> {
    let reply = connection
        .get_property(false, window, property, type_, 0, 1024)
        .ok()?
        .reply()
        .ok()?;
    let values: Vec<u32> = reply.value32()?.collect();
    Some(values)
}

fn window_title(
    connection: &RustConnection,
    window: Window,
    net_wm_name: u32,
    utf8_string: u32,
) -> Option<String> {
    let reply = connection
        .get_property(false, window, net_wm_name, utf8_string, 0, 1024)
        .ok()?
        .reply()
        .ok()?;
    if !reply.value.is_empty() {
        return Some(String::from_utf8_lossy(&reply.value).into_owned());
    }
    let reply = connection
        .get_property(
            false,
            window,
            u32::from(AtomEnum::WM_NAME),
            u32::from(AtomEnum::STRING),
            0,
            1024,
        )
        .ok()?
        .reply()
        .ok()?;
    (!reply.value.is_empty()).then(|| String::from_utf8_lossy(&reply.value).into_owned())
}
