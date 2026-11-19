use std::path::PathBuf;

use crate::paths::Paths;

impl Paths {
    /// The GUI's control socket. Prefer the session runtime dir, then the cache
    /// dir (SSH/no-session fallback).
    pub fn socket_file(&self) -> PathBuf {
        let runtime = std::env::var_os("XDG_RUNTIME_DIR")
            .map(PathBuf::from)
            .filter(|path| path.is_absolute())
            .unwrap_or_else(|| self.cache_dir.clone());
        runtime.join("deck.sock")
    }
}
