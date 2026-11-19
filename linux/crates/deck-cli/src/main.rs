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
            println!("deck: search panel arrives in L2");
            Ok(())
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
            println!("deck [--version] [--settings] [--toggle-search] [--daemon [--once]]");
            Ok(())
        }
        Some(other) => {
            eprintln!("deck: unknown argument: {other}");
            eprintln!("deck [--version] [--settings] [--toggle-search] [--daemon [--once]]");
            exit(2);
        }
    }
}
