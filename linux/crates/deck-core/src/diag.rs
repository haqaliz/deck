use std::fs;
use std::path::Path;

/// Writes a crash/summary file without ever blocking the caller's exit path.
pub fn record(cache_dir: &Path, name: &str, message: &str) {
    let _ = fs::create_dir_all(cache_dir);
    let _ = fs::write(cache_dir.join(name), message);
}

pub fn read(cache_dir: &Path, name: &str) -> Option<String> {
    fs::read_to_string(cache_dir.join(name)).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn records_and_reads_a_last_error() {
        let tmp = tempfile::tempdir().expect("temp");
        assert!(read(tmp.path(), "last-error.log").is_none());
        record(tmp.path(), "last-error.log", "panicked at test.rs:1\n");
        assert_eq!(
            read(tmp.path(), "last-error.log").as_deref(),
            Some("panicked at test.rs:1\n")
        );
        record(tmp.path(), "last-error.log", "second");
        assert_eq!(
            read(tmp.path(), "last-error.log").as_deref(),
            Some("second")
        );
    }
}
