use std::io::Write;
use std::os::unix::net::UnixStream;
use std::process::exit;
use std::time::Duration;

use deck_core::paths::Paths;
use deck_core::platform::detect_session;

fn main() {
    if let Err(error) = run() {
        eprintln!("deck: {error}");
        exit(1);
    }
}

fn run() -> Result<(), deck_core::CoreError> {
    let paths = Paths::from_env();
    let args: Vec<String> = std::env::args().skip(1).collect();

    match args.first().map(String::as_str) {
        Some("--version") | Some("-V") => {
            println!("deck {}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        Some("--settings") => {
            println!("{}", paths.settings_file().display());
            println!("session: {:?}", detect_session());
            Ok(())
        }
        Some("--check-credentials") => {
            let store = deck_core::credentials::CredentialStore::detect(&paths);
            println!("store: {}", store.kind());
            let settings = deck_core::settings::Settings::load(&paths);
            let mut ids = vec![
                "github".to_string(),
                "azure".to_string(),
                "elastic".to_string(),
                "grafana".to_string(),
                "opencode".to_string(),
            ];
            ids.extend(
                settings
                    .azure_accounts
                    .into_iter()
                    .map(|account| account.id),
            );
            for id in ids {
                let present = store
                    .read(&id)
                    .map(|value| value.is_some())
                    .unwrap_or(false);
                println!("{id}: {}", if present { "stored" } else { "missing" });
            }
            Ok(())
        }
        Some("--toggle-search") => {
            match UnixStream::connect(paths.socket_file()) {
                Ok(mut stream) => {
                    let _ = writeln!(stream, "toggle-search");
                }
                Err(_) => {
                    println!("deck: is not running; start deck-gui or enable autostart");
                }
            }
            Ok(())
        }
        Some("--install-shortcut") => {
            let key = args
                .iter()
                .position(|arg| arg == "--key")
                .and_then(|index| args.get(index + 1))
                .map(String::as_str)
                .unwrap_or(deck_core::shortcut::DEFAULT_KEY);
            let command = match deck_core::platform::flatpak_id() {
                Some(id) => format!("flatpak run {id} --toggle-search"),
                None => std::env::current_exe()
                    .map(|path| format!("{} --toggle-search", path.display()))
                    .unwrap_or_else(|_| "deck --toggle-search".into()),
            };
            let _ = deck_core::shortcut::ensure_labwc_desktop_rule();
            let desktop = std::env::var("XDG_CURRENT_DESKTOP")
                .unwrap_or_default()
                .to_lowercase();
            let session = detect_session();
            if desktop.contains("gnome") {
                match deck_core::gnome::install(&command) {
                    Ok(()) => {
                        println!("deck: installed Super+Space as a GNOME custom shortcut");
                        Ok(())
                    }
                    Err(error) => {
                        eprintln!("deck: GNOME shortcut install failed: {error}");
                        exit(1);
                    }
                }
            } else if desktop.contains("kde") {
                match deck_core::shortcut::install_kde_shortcut(&command, key) {
                    Ok(path) => {
                        println!(
                            "deck: installed Deck Search in KDE ({}); log out or restart Plasma to activate it",
                            path.display()
                        );
                        Ok(())
                    }
                    Err(error) => {
                        eprintln!("deck: KDE shortcut install failed: {error}");
                        exit(1);
                    }
                }
            } else if desktop.contains("labwc")
                || std::process::Command::new("pgrep")
                    .args(["-x", "labwc"])
                    .status()
                    .map(|status| status.success())
                    .unwrap_or(false)
            {
                match deck_core::shortcut::install_labwc_shortcut(&command, key) {
                    Ok(path) => {
                        println!("deck: installed {key} in {}", path.display());
                        Ok(())
                    }
                    Err(error) => {
                        eprintln!("deck: shortcut install failed: {error}");
                        exit(1);
                    }
                }
            } else {
                println!("deck: no automatic installer for this desktop.");
                println!("Bind `{command}` to your chosen shortcut:");
                if desktop.contains("kde") {
                    println!(
                        "  KDE: System Settings → Shortcuts → Custom Shortcuts → New → Command/URL"
                    );
                } else if session == deck_core::platform::SessionKind::X11 {
                    println!("  X11: your desktop's keyboard settings, or a launcher entry");
                } else {
                    println!("  Sway: bindsym $mod+space exec {command}");
                    println!("  Hyprland: bind = SUPER, Space, exec, {command}");
                    println!("  wlroots: use your compositor's command binding");
                }
                Ok(())
            }
        }
        Some("--remove-shortcut") => {
            let desktop = std::env::var("XDG_CURRENT_DESKTOP")
                .unwrap_or_default()
                .to_lowercase();
            if desktop.contains("kde") {
                match deck_core::shortcut::remove_kde_shortcut() {
                    Ok(Some(path)) => {
                        println!("deck: removed the KDE shortcut {}", path.display());
                        return Ok(());
                    }
                    Ok(None) => {
                        println!("deck: no KDE shortcut was installed");
                        return Ok(());
                    }
                    Err(error) => {
                        eprintln!("deck: KDE shortcut removal failed: {error}");
                        exit(1);
                    }
                }
            }
            if desktop.contains("gnome") {
                match deck_core::gnome::remove() {
                    Ok(true) => println!("deck: removed the GNOME shortcut"),
                    Ok(false) => println!("deck: no GNOME shortcut was installed"),
                    Err(error) => {
                        eprintln!("deck: GNOME shortcut removal failed: {error}");
                        exit(1);
                    }
                }
                return Ok(());
            }
            match deck_core::shortcut::remove_labwc_shortcut() {
                Ok(Some(path)) => {
                    println!("deck: removed the search shortcut from {}", path.display());
                    Ok(())
                }
                Ok(None) => {
                    println!("deck: no Deck shortcut was installed");
                    Ok(())
                }
                Err(error) => {
                    eprintln!("deck: shortcut removal failed: {error}");
                    exit(1);
                }
            }
        }
        Some("--daemon") => {
            let once = args.iter().any(|arg| arg == "--once");
            if once {
                let path = deckd::run_once(&paths)?;
                println!("deck: wrote {}", path.display());
            } else {
                deckd::run_forever(&paths, Duration::from_secs(60))?;
            }
            Ok(())
        }
        Some("--help") | Some("-h") | None => {
            println!(
                "deck [--version] [--settings] [--toggle-search] \
                 [--install-shortcut [--key KEY]] [--remove-shortcut] \
                 [--check-credentials] [--daemon [--once]]"
            );
            Ok(())
        }
        Some(other) => {
            eprintln!("deck: unknown argument: {other}");
            eprintln!(
                "deck [--version] [--settings] [--toggle-search] \
                 [--install-shortcut [--key KEY]] [--remove-shortcut] \
                 [--check-credentials] [--daemon [--once]]"
            );
            exit(2);
        }
    }
}
