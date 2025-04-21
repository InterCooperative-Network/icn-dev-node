use crate::error::{NodeError, NodeResult};
use chrono::{DateTime, Utc};
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use std::fs::{self, File};
use std::io::{BufReader, BufWriter, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

// Global state instance
static STATE: Lazy<Arc<Mutex<NodeState>>> = Lazy::new(|| {
    Arc::new(Mutex::new(NodeState::default()))
});

// Node state structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeState {
    pub node_id: String,
    pub initialized: DateTime<Utc>,
    pub last_updated: DateTime<Utc>,
    pub last_executed_block: u64,
    pub last_proposal_id: u64,
    pub executed_proposals: Vec<String>,
    pub active_connection: String,
    pub peers: Vec<String>,
    pub system_version: String,
    pub dag_vertices: Vec<VertexEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VertexEntry {
    pub id: String,
    pub proposal_id: String,
    pub timestamp: DateTime<Utc>,
    pub hash: String,
}

impl Default for NodeState {
    fn default() -> Self {
        Self {
            node_id: Uuid::new_v4().to_string(),
            initialized: Utc::now(),
            last_updated: Utc::now(),
            last_executed_block: 0,
            last_proposal_id: 0,
            executed_proposals: Vec::new(),
            active_connection: String::new(),
            peers: Vec::new(),
            system_version: env!("CARGO_PKG_VERSION").to_string(),
            dag_vertices: Vec::new(),
        }
    }
}

// State file paths
pub fn get_state_dir() -> NodeResult<PathBuf> {
    let home_dir = dirs::home_dir()
        .ok_or_else(|| NodeError::State("Could not determine home directory".to_string()))?;
    
    let state_dir = home_dir.join(".icn");
    Ok(state_dir)
}

pub fn get_state_file() -> NodeResult<PathBuf> {
    let state_dir = get_state_dir()?;
    Ok(state_dir.join("state.json"))
}

pub fn get_backup_dir() -> NodeResult<PathBuf> {
    let state_dir = get_state_dir()?;
    Ok(state_dir.join("state").join("backups"))
}

// Initialize state
pub fn init() -> NodeResult<()> {
    let state_dir = get_state_dir()?;
    let state_file = get_state_file()?;
    let backup_dir = get_backup_dir()?;

    // Create directories if they don't exist
    fs::create_dir_all(&state_dir)?;
    fs::create_dir_all(&backup_dir)?;

    // Load or create state
    if state_file.exists() {
        load_state()?;
    } else {
        save_state()?;
    }

    Ok(())
}

// Load state from file
pub fn load_state() -> NodeResult<()> {
    let state_file = get_state_file()?;
    
    let file = File::open(&state_file)
        .map_err(|e| NodeError::State(format!("Failed to open state file: {}", e)))?;
    
    let reader = BufReader::new(file);
    let state: NodeState = serde_json::from_reader(reader)
        .map_err(|e| NodeError::State(format!("Failed to parse state file: {}", e)))?;
    
    // Update global state
    let mut global_state = STATE.lock()
        .map_err(|e| NodeError::State(format!("Failed to lock state: {}", e)))?;
    
    *global_state = state;
    
    Ok(())
}

// Save state to file
pub fn save_state() -> NodeResult<()> {
    let state_file = get_state_file()?;
    
    // Get current state
    let mut state = STATE.lock()
        .map_err(|e| NodeError::State(format!("Failed to lock state: {}", e)))?;
    
    // Update timestamp
    state.last_updated = Utc::now();
    
    // Create backup first if the file exists
    if state_file.exists() {
        backup_state()?;
    }
    
    // Write to file
    let file = File::create(&state_file)
        .map_err(|e| NodeError::State(format!("Failed to create state file: {}", e)))?;
    
    let writer = BufWriter::new(file);
    serde_json::to_writer_pretty(writer, &*state)
        .map_err(|e| NodeError::State(format!("Failed to write state file: {}", e)))?;
    
    Ok(())
}

// Backup state
pub fn backup_state() -> NodeResult<PathBuf> {
    let state_file = get_state_file()?;
    let backup_dir = get_backup_dir()?;
    
    // Create backup filename with timestamp
    let timestamp = Utc::now().format("%Y%m%d_%H%M%S");
    let backup_file = backup_dir.join(format!("state_{}.json", timestamp));
    
    // Copy the current state file to backup
    fs::copy(&state_file, &backup_file)
        .map_err(|e| NodeError::State(format!("Failed to create backup: {}", e)))?;
    
    Ok(backup_file)
}

// Get a value from state
pub fn get<T: for<'de> Deserialize<'de>>( key: &str) -> NodeResult<T> {
    let state = STATE.lock()
        .map_err(|e| NodeError::State(format!("Failed to lock state: {}", e)))?;
    
    let value = serde_json::to_value(&*state)
        .map_err(|e| NodeError::State(format!("Failed to serialize state: {}", e)))?;
    
    let result = value.get(key)
        .ok_or_else(|| NodeError::State(format!("Key not found in state: {}", key)))?
        .clone();
    
    serde_json::from_value(result)
        .map_err(|e| NodeError::State(format!("Failed to deserialize state value: {}", e)))
}

// Set a value in state
pub fn set<T: Serialize>(key: &str, value: T) -> NodeResult<()> {
    let mut state = STATE.lock()
        .map_err(|e| NodeError::State(format!("Failed to lock state: {}", e)))?;
    
    let mut state_value = serde_json::to_value(&*state)
        .map_err(|e| NodeError::State(format!("Failed to serialize state: {}", e)))?;
    
    let value = serde_json::to_value(value)
        .map_err(|e| NodeError::State(format!("Failed to serialize value: {}", e)))?;
    
    if let serde_json::Value::Object(ref mut map) = state_value {
        map.insert(key.to_string(), value);
    } else {
        return Err(NodeError::State("State is not an object".to_string()));
    }
    
    *state = serde_json::from_value(state_value)
        .map_err(|e| NodeError::State(format!("Failed to update state: {}", e)))?;
    
    save_state()?;
    
    Ok(())
}

// Add a DAG vertex
pub fn add_vertex(vertex: VertexEntry) -> NodeResult<()> {
    let mut state = STATE.lock()
        .map_err(|e| NodeError::State(format!("Failed to lock state: {}", e)))?;
    
    state.dag_vertices.push(vertex.clone());
    
    // Log the vertex
    log_vertex(&vertex)?;
    
    save_state()?;
    
    Ok(())
}

// Log vertex to dag.log
fn log_vertex(vertex: &VertexEntry) -> NodeResult<()> {
    let state_dir = get_state_dir()?;
    let logs_dir = state_dir.join("logs");
    let log_file = logs_dir.join("dag.log");
    
    // Create logs directory if it doesn't exist
    fs::create_dir_all(&logs_dir)?;
    
    // Append to log file
    let log_entry = format!(
        "{} - Vertex ID: {}, Proposal: {}, Hash: {}\n",
        vertex.timestamp, vertex.id, vertex.proposal_id, vertex.hash
    );
    
    fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_file)?
        .write_all(log_entry.as_bytes())?;
    
    Ok(())
}

// Get executed proposals
pub fn get_executed_proposals() -> NodeResult<Vec<String>> {
    let state = STATE.lock()
        .map_err(|e| NodeError::State(format!("Failed to lock state: {}", e)))?;
    
    Ok(state.executed_proposals.clone())
}

// Add executed proposal
pub fn add_executed_proposal(proposal_id: &str) -> NodeResult<()> {
    let mut state = STATE.lock()
        .map_err(|e| NodeError::State(format!("Failed to lock state: {}", e)))?;
    
    if !state.executed_proposals.contains(&proposal_id.to_string()) {
        state.executed_proposals.push(proposal_id.to_string());
    }
    
    save_state()?;
    
    Ok(())
} 