use std::fs;
use std::path::{Path, PathBuf};

use crate::paths::{write_atomic, Paths};
use crate::CoreError;

/// Write `$XDG_CONFIG_HOME/autostart/deck.desktop`.
pub fn install(exec: &Path, paths: &Paths) -> Result<PathBuf, CoreError> {
    let autostart = autostart_dir(paths);
    fs::create_dir_all(&autostart)?;
    let desktop = autostart.join("deck.desktop");
    let content = format!(
        "[Desktop Entry]\nType=Application\nName=Deck\nComment=Desktop widgets, settings and search\nExec={}\nTerminal=false\nX-GNOME-Autostart-enabled=true\n",
        exec.display()
    );
    write_atomic(&desktop, content.as_bytes(), 0o644)?;
    Ok(desktop)
}

pub fn remove(paths: &Paths) -> Result<(), CoreError> {
    let desktop = autostart_dir(paths).join("deck.desktop");
    match fs::remove_file(desktop) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error.into()),
    }
}

fn autostart_dir(paths: &Paths) -> PathBuf {
    paths
        .config_dir
        .parent()
        .unwrap_or(&paths.config_dir)
        .join("autostart")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_paths() -> (tempfile::TempDir, Paths) {
        let tmp = tempfile::tempdir().expect("temp dir");
        let root = tmp.path().to_path_buf();
        (
            tmp,
            Paths::new(root.join("config"), root.join("data"), root.join("cache")),
        )
    }

    #[test]
    fn installs_and_removes_the_desktop_entry() {
        let (_tmp, paths) = temp_paths();
        let exec = Path::new("/usr/bin/deck-gui");
        let desktop = install(exec, &paths).expect("install");
        assert!(desktop.is_file());
        let content = fs::read_to_string(&desktop).expect("read");
        assert!(content.contains("Exec=/usr/bin/deck-gui"));
        remove(&paths).expect("remove");
        assert!(!desktop.exists());
    }

    #[test]
    fn removing_a_missing_entry_is_not_an_error() {
        let (_tmp, paths) = temp_paths();
        remove(&paths).expect("remove missing");
    }
}
