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
            let command = std::env::current_exe()
                .map(|path| format!("{} --toggle-search", path.display()))
                .unwrap_or_else(|_| "deck --toggle-search".into());
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
                 [--install-shortcut [--key KEY]] [--daemon [--once]]"
            );
            Ok(())
        }
        Some(other) => {
            eprintln!("deck: unknown argument: {other}");
            eprintln!(
                "deck [--version] [--settings] [--toggle-search] \
                 [--install-shortcut [--key KEY]] [--daemon [--once]]"
            );
            exit(2);
        }
    }
}
