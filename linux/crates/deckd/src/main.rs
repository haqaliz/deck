use std::process::exit;
use std::time::Duration;

use deck_core::paths::Paths;

fn main() {
    if let Err(error) = run() {
        eprintln!("deckd: {error}");
        exit(1);
    }
}

fn run() -> Result<(), deck_core::CoreError> {
    let mut once = false;
    let mut interval = 60_u64;

    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--once" => once = true,
            "--interval" => {
                let value = args.next().unwrap_or_default();
                interval = value.parse().unwrap_or(60).max(1);
            }
            "--help" | "-h" => {
                println!("deckd [--once] [--interval SECONDS]");
                return Ok(());
            }
            other => {
                eprintln!("deckd: unknown argument: {other}");
                eprintln!("deckd [--once] [--interval SECONDS]");
                exit(2);
            }
        }
    }

    let paths = Paths::from_env();
    paths.ensure_dirs()?;
    let cache = paths.cache_dir.clone();
    std::panic::set_hook(Box::new(move |info| {
        deck_core::diag::record(&cache, "deckd-last-error.log", &format!("{info}\n"));
        eprintln!("deckd: {info}");
    }));
    if once {
        let path = deckd::run_once(&paths)?;
        println!("deckd: wrote {}", path.display());
        return Ok(());
    }

    deckd::run_forever(&paths, Duration::from_secs(interval))
}
