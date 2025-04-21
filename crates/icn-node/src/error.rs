use thiserror::Error;

#[derive(Error, Debug)]
pub enum NodeError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
    
    #[error("HTTP error: {0}")]
    Http(#[from] reqwest::Error),
    
    #[error("State error: {0}")]
    State(String),
    
    #[error("Queue error: {0}")]
    Queue(String),
    
    #[error("Execution error: {0}")]
    Execution(String),
    
    #[error("DAG error: {0}")]
    Dag(String),
    
    #[error("Federation error: {0}")]
    Federation(String),
    
    #[error("Validation error: {0}")]
    Validation(String),

    #[error("Shell command error: {message}, code: {code}")]
    ShellCommand { message: String, code: i32 },
    
    #[error("Configuration error: {0}")]
    Config(String),
}

pub type NodeResult<T> = Result<T, NodeError>; 