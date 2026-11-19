use std::collections::BTreeMap;
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};

use crate::paths::{write_atomic, Paths};
use crate::CoreError;

const ATTRIBUTE_SERVICE: &str = "service";
const ATTRIBUTE_ACCOUNT: &str = "account";
const ATTRIBUTE_SERVICE_VALUE: &str = "deck";

/// Token storage. Secret Service (`secret-tool`) is preferred; the 0600 JSON
/// fallback exists because a minimal Pi OS install may have no keyring.
pub enum CredentialStore {
    SecretTool(SecretToolStore),
    File(FileStore),
}

impl CredentialStore {
    pub fn detect(paths: &Paths) -> Self {
        if command_exists("secret-tool") {
            Self::SecretTool(SecretToolStore)
        } else {
            Self::File(FileStore::new(paths))
        }
    }

    pub fn kind(&self) -> &'static str {
        match self {
            Self::SecretTool(_) => "secret-service",
            Self::File(_) => "file-0600",
        }
    }

    pub fn read(&self, id: &str) -> Result<Option<String>, CoreError> {
        match self {
            Self::SecretTool(store) => store.read(id),
            Self::File(store) => store.read(id),
        }
    }

    pub fn write(&self, id: &str, token: &str) -> Result<(), CoreError> {
        match self {
            Self::SecretTool(store) => store.write(id, token),
            Self::File(store) => store.write(id, token),
        }
    }

    pub fn delete(&self, id: &str) -> Result<(), CoreError> {
        match self {
            Self::SecretTool(store) => store.delete(id),
            Self::File(store) => store.delete(id),
        }
    }
}

pub struct FileStore {
    path: PathBuf,
}

impl FileStore {
    pub fn new(paths: &Paths) -> Self {
        Self {
            path: paths.credentials_file(),
        }
    }

    fn load(&self) -> Result<BTreeMap<String, String>, CoreError> {
        let bytes = match fs::read(&self.path) {
            Ok(bytes) => bytes,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Ok(BTreeMap::new())
            }
            Err(error) => return Err(error.into()),
        };
        serde_json::from_slice(&bytes).map_err(|_| {
            CoreError::Credentials(
                "credentials file is not valid JSON; refusing to drop stored tokens".into(),
            )
        })
    }

    fn save(&self, map: &BTreeMap<String, String>) -> Result<(), CoreError> {
        let bytes = serde_json::to_vec_pretty(map)?;
        write_atomic(&self.path, &bytes, 0o600)?;
        Ok(())
    }

    pub fn read(&self, id: &str) -> Result<Option<String>, CoreError> {
        Ok(self.load()?.get(id).cloned())
    }

    pub fn write(&self, id: &str, token: &str) -> Result<(), CoreError> {
        let mut map = self.load()?;
        map.insert(id.to_owned(), token.to_owned());
        self.save(&map)
    }

    pub fn delete(&self, id: &str) -> Result<(), CoreError> {
        let mut map = self.load()?;
        map.remove(id);
        self.save(&map)
    }
}

pub struct SecretToolStore;

impl SecretToolStore {
    pub fn read(&self, id: &str) -> Result<Option<String>, CoreError> {
        let output = Command::new("secret-tool")
            .args([
                "lookup",
                ATTRIBUTE_SERVICE,
                ATTRIBUTE_SERVICE_VALUE,
                ATTRIBUTE_ACCOUNT,
                id,
            ])
            .output()
            .map_err(|error| CoreError::Credentials(format!("secret-tool: {error}")))?;
        if output.status.success() {
            let token = String::from_utf8_lossy(&output.stdout).trim().to_owned();
            return Ok((!token.is_empty()).then_some(token));
        }
        if output.status.code() == Some(1) {
            return Ok(None);
        }
        Err(CoreError::Credentials(format!(
            "secret-tool lookup failed with {:?}",
            output.status.code()
        )))
    }

    pub fn write(&self, id: &str, token: &str) -> Result<(), CoreError> {
        let label = format!("Deck {id}");
        let mut child = Command::new("secret-tool")
            .args([
                "store",
                "--label",
                &label,
                ATTRIBUTE_SERVICE,
                ATTRIBUTE_SERVICE_VALUE,
                ATTRIBUTE_ACCOUNT,
                id,
            ])
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|error| CoreError::Credentials(format!("secret-tool: {error}")))?;
        if let Some(mut stdin) = child.stdin.take() {
            stdin
                .write_all(token.as_bytes())
                .map_err(|error| CoreError::Credentials(format!("secret-tool stdin: {error}")))?;
        }
        let status = child
            .wait()
            .map_err(|error| CoreError::Credentials(format!("secret-tool: {error}")))?;
        if status.success() {
            Ok(())
        } else {
            Err(CoreError::Credentials(format!(
                "secret-tool store failed with {:?}",
                status.code()
            )))
        }
    }

    pub fn delete(&self, id: &str) -> Result<(), CoreError> {
        let status = Command::new("secret-tool")
            .args([
                "clear",
                ATTRIBUTE_SERVICE,
                ATTRIBUTE_SERVICE_VALUE,
                ATTRIBUTE_ACCOUNT,
                id,
            ])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map_err(|error| CoreError::Credentials(format!("secret-tool: {error}")))?;
        if status.success() || status.code() == Some(1) {
            Ok(())
        } else {
            Err(CoreError::Credentials(format!(
                "secret-tool clear failed with {:?}",
                status.code()
            )))
        }
    }
}

fn command_exists(name: &str) -> bool {
    std::env::var_os("PATH")
        .map(|paths| {
            std::env::split_paths(&paths)
                .map(|dir| dir.join(name))
                .any(|candidate| candidate.is_file())
        })
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::paths::Paths;
    use std::os::unix::fs::PermissionsExt;

    fn temp_paths() -> (tempfile::TempDir, Paths) {
        let tmp = tempfile::tempdir().expect("temp dir");
        let root = tmp.path().to_path_buf();
        (
            tmp,
            Paths::new(root.join("config"), root.join("data"), root.join("cache")),
        )
    }

    #[test]
    fn file_store_round_trips_and_is_0600() {
        let (_tmp, paths) = temp_paths();
        let store = FileStore::new(&paths);
        assert_eq!(store.read("a").expect("read empty"), None);
        store.write("a", "secret-a").expect("write");
        assert_eq!(store.read("a").expect("read"), Some("secret-a".into()));
        let mode = fs::metadata(paths.credentials_file())
            .expect("metadata")
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(mode, 0o600);
        store.delete("a").expect("delete");
        assert_eq!(store.read("a").expect("read after delete"), None);
    }

    #[test]
    fn corrupt_file_is_an_error_not_a_silent_token_loss() {
        let (_tmp, paths) = temp_paths();
        paths.ensure_dirs().expect("dirs");
        fs::write(paths.credentials_file(), b"{not json").expect("write");
        let store = FileStore::new(&paths);
        assert!(matches!(store.read("a"), Err(CoreError::Credentials(_))));
    }

    #[test]
    fn store_kind_is_reported_without_the_token() {
        let (_tmp, paths) = temp_paths();
        let store = CredentialStore::File(FileStore::new(&paths));
        assert_eq!(store.kind(), "file-0600");
    }
}
