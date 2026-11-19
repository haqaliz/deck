use std::io;

/// One error type for the shared core. Messages never contain a token.
#[derive(Debug, thiserror::Error)]
pub enum CoreError {
    #[error("io: {0}")]
    Io(#[from] io::Error),

    #[error("json: {0}")]
    Json(#[from] serde_json::Error),

    #[error("credentials: {0}")]
    Credentials(String),
}
