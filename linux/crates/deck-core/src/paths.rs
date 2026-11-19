use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process;
use std::time::{SystemTime, UNIX_EPOCH};

/// XDG paths for the Linux app.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Paths {
    pub config_dir: PathBuf,
    pub data_dir: PathBuf,
    pub cache_dir: PathBuf,
}

impl Paths {
    pub fn from_env() -> Self {
        let home = env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/"));
        let config = env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .filter(|p| p.is_absolute())
            .unwrap_or_else(|| home.join(".config"))
            .join("deck");
        let data = env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .filter(|p| p.is_absolute())
            .unwrap_or_else(|| home.join(".local/share"))
            .join("deck");
        let cache = env::var_os("XDG_CACHE_HOME")
            .map(PathBuf::from)
            .filter(|p| p.is_absolute())
            .unwrap_or_else(|| home.join(".cache"))
            .join("deck");
        Self {
            config_dir: config,
            data_dir: data,
            cache_dir: cache,
        }
    }

    pub fn new(config_dir: PathBuf, data_dir: PathBuf, cache_dir: PathBuf) -> Self {
        Self {
            config_dir,
            data_dir,
            cache_dir,
        }
    }

    pub fn ensure_dirs(&self) -> io::Result<()> {
        fs::create_dir_all(&self.config_dir)?;
        fs::create_dir_all(&self.data_dir)?;
        fs::create_dir_all(&self.cache_dir)?;
        set_mode(&self.config_dir, 0o700)?;
        Ok(())
    }

    pub fn settings_file(&self) -> PathBuf {
        self.config_dir.join("settings.json")
    }

    pub fn credentials_file(&self) -> PathBuf {
        self.config_dir.join("credentials.json")
    }

    pub fn snapshot_file(&self, source: &str) -> PathBuf {
        self.data_dir.join(format!("{source}.json"))
    }

    pub fn fetch_status_file(&self, source: &str) -> PathBuf {
        self.data_dir.join(format!("fetch-{source}.json"))
    }
}

/// Atomic write: unique temp in the same directory, then rename. The target is
/// either the complete new bytes or the untouched old file.
pub fn write_atomic(path: &Path, bytes: &[u8], mode: u32) -> io::Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "path has no parent"))?;
    fs::create_dir_all(parent)?;
    let name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("deck.tmp");
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let temp = parent.join(format!(".{name}.tmp.{}.{nanos}", process::id()));

    let result = (|| {
        fs::write(&temp, bytes)?;
        set_mode(&temp, mode)?;
        fs::rename(&temp, path)?;
        set_mode(path, mode)?;
        Ok(())
    })();

    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result
}

#[cfg(unix)]
fn set_mode(path: &Path, mode: u32) -> io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(mode))
}

#[cfg(not(unix))]
fn set_mode(_path: &Path, _mode: u32) -> io::Result<()> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    fn temp_paths() -> (tempfile::TempDir, Paths) {
        let tmp = tempfile::tempdir().expect("temp dir");
        let root = tmp.path().to_path_buf();
        let paths = Paths::new(root.join("config"), root.join("data"), root.join("cache"));
        (tmp, paths)
    }

    #[test]
    fn ensure_dirs_creates_all_three_and_config_is_private() {
        let (_tmp, paths) = temp_paths();
        paths.ensure_dirs().expect("dirs");
        assert!(paths.config_dir.is_dir());
        assert!(paths.data_dir.is_dir());
        assert!(paths.cache_dir.is_dir());
        let mode = fs::metadata(&paths.config_dir)
            .expect("config metadata")
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(mode, 0o700);
    }

    #[test]
    fn atomic_write_sets_the_requested_mode_and_leaves_no_temp() {
        let (_tmp, paths) = temp_paths();
        let file = paths.config_dir.join("secret.json");
        write_atomic(&file, b"{\"a\":1}", 0o600).expect("write");
        let mode = fs::metadata(&file).expect("metadata").permissions().mode() & 0o777;
        assert_eq!(mode, 0o600);
        let leftovers = fs::read_dir(&paths.config_dir)
            .expect("read dir")
            .filter_map(Result::ok)
            .filter(|entry| entry.file_name().to_string_lossy().contains(".tmp."))
            .count();
        assert_eq!(leftovers, 0);
    }
}
