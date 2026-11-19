mod tray;
mod ui;
mod widgets;

use std::cell::RefCell;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::mpsc::{self, Sender};
use std::time::Duration;

use deck_core::paths::Paths;
use deck_core::settings::Settings;
use gtk4 as gtk;
use gtk4::prelude::*;

#[derive(Clone, Copy, Debug)]
pub enum Command {
    ToggleSearch,
    ShowSettings,
    Quit,
}

fn main() -> gtk::glib::ExitCode {
    let paths = Paths::from_env();
    if let Err(error) = paths.ensure_dirs() {
        eprintln!("deck-gui: {error}");
        return gtk::glib::ExitCode::FAILURE;
    }

    let settings = Rc::new(RefCell::new(Settings::load(&paths)));
    let socket = paths.socket_file();

    // A second launch asks the running GUI to open Search instead of creating
    // a duplicate set of widget windows.
    if let Ok(mut stream) = UnixStream::connect(&socket) {
        let _ = writeln!(stream, "toggle-search");
        return gtk::glib::ExitCode::SUCCESS;
    }
    let _ = std::fs::remove_file(&socket);

    let (tx, rx) = mpsc::channel();
    start_socket(socket, tx.clone());

    let app = gtk::Application::builder()
        .application_id("io.github.haqaliz.deck")
        .build();

    let settings_for_activate = settings.clone();
    let paths_for_activate = paths.clone();
    let tx_for_activate = tx.clone();
    let rx_slot = Rc::new(RefCell::new(Some(rx)));

    app.connect_activate(move |app| {
        ui::apply_css();

        if settings_for_activate.borrow().autostart {
            let exec = std::env::current_exe().unwrap_or_else(|_| PathBuf::from("deck-gui"));
            let _ = deck_core::autostart::install(&exec, &paths_for_activate);
        }

        let mut keep_alive = ui::widget_windows(
            app,
            settings_for_activate.clone(),
            paths_for_activate.clone(),
        );

        let (search, entry) = ui::search_window(
            app,
            paths_for_activate.clone(),
            settings_for_activate.clone(),
        );
        let settings_window = ui::settings_window(
            app,
            paths_for_activate.clone(),
            settings_for_activate.clone(),
        );
        tray::spawn(tx_for_activate.clone());

        let Some(rx) = rx_slot.borrow_mut().take() else {
            return;
        };
        let app_for_poll = app.clone();
        let search_for_poll = search.clone();
        let entry_for_poll = entry.clone();
        let settings_for_poll = settings_window.clone();
        // Keep the visible windows alive for the process lifetime.
        keep_alive.push(search);
        keep_alive.push(settings_window);

        gtk::glib::timeout_add_local(Duration::from_millis(100), move || {
            let _ = &keep_alive;
            while let Ok(command) = rx.try_recv() {
                match command {
                    Command::ToggleSearch => ui::toggle_search(&search_for_poll, &entry_for_poll),
                    Command::ShowSettings => {
                        search_for_poll.hide();
                        settings_for_poll.present();
                    }
                    Command::Quit => app_for_poll.quit(),
                }
            }
            gtk::glib::ControlFlow::Continue
        });
    });

    app.run()
}

fn start_socket(path: PathBuf, tx: Sender<Command>) {
    if let Some(parent) = path.parent() {
        if let Err(error) = std::fs::create_dir_all(parent) {
            eprintln!("deck-gui: socket dir: {error}");
            return;
        }
    }
    let listener = match UnixListener::bind(&path) {
        Ok(listener) => listener,
        Err(error) => {
            eprintln!("deck-gui: cannot bind {}: {error}", path.display());
            return;
        }
    };

    std::thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            let mut line = String::new();
            if BufReader::new(stream).read_line(&mut line).is_err() {
                continue;
            }
            let command = match line.trim() {
                "toggle-search" => Some(Command::ToggleSearch),
                "settings" => Some(Command::ShowSettings),
                "quit" => Some(Command::Quit),
                _ => None,
            };
            if let Some(command) = command {
                let _ = tx.send(command);
            }
        }
    });
}
