use crate::error::{NodeError, NodeResult};
use crate::federation;
use crate::state::{self, VertexEntry};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use tokio::sync::mpsc;
use tokio::time::{self, Duration};
use tracing::{error, info};

// DAG vertex structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Vertex {
    pub id: String,
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub proposal_id: String,
    pub parents: Vec<String>,
    pub hash: String,
    pub submitter: String,
}

// DAG info structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DagInfo {
    pub vertex_count: usize,
    pub root_count: usize,
    pub tip_count: usize,
    pub genesis_time: chrono::DateTime<chrono::Utc>,
    pub latest_update: chrono::DateTime<chrono::Utc>,
    pub tips: Vec<String>,
}

// Get DAG info
pub async fn get_dag_info() -> NodeResult<DagInfo> {
    // For now, we're just using the state to get DAG info
    let vertices = get_all_vertices()?;
    
    // Very simple DAG implementation for now
    // In a real implementation, we would track the actual DAG structure with parents/children
    let vertex_count = vertices.len();
    let root_count = 1; // Simplified
    let tips = if vertex_count > 0 {
        vec![vertices.last().unwrap().id.clone()]
    } else {
        Vec::new()
    };
    
    let genesis_time = if vertices.is_empty() {
        chrono::Utc::now()
    } else {
        vertices.first().unwrap().timestamp
    };
    
    let latest_update = if vertices.is_empty() {
        chrono::Utc::now()
    } else {
        vertices.last().unwrap().timestamp
    };
    
    Ok(DagInfo {
        vertex_count,
        root_count,
        tip_count: tips.len(),
        genesis_time,
        latest_update,
        tips,
    })
}

// Record a new vertex in the DAG
pub async fn add_vertex(vertex: VertexEntry) -> NodeResult<()> {
    // Add to state
    state::add_vertex(vertex.clone())?;
    
    // Sync with federation
    federation::broadcast_vertex(&vertex).await?;
    
    Ok(())
}

// Get all vertices
pub fn get_all_vertices() -> NodeResult<Vec<VertexEntry>> {
    let state = state::get::<state::NodeState>("state")?;
    Ok(state.dag_vertices)
}

// Get specific vertex by ID
pub fn get_vertex(id: &str) -> NodeResult<VertexEntry> {
    let vertices = get_all_vertices()?;
    
    vertices.iter()
        .find(|v| v.id == id)
        .cloned()
        .ok_or_else(|| NodeError::Dag(format!("Vertex not found: {}", id)))
}

// Watch the DAG for changes
pub async fn watch_dag(tx: mpsc::Sender<String>) -> NodeResult<()> {
    let mut last_count = 0;
    
    loop {
        // Check for new vertices
        let vertices = get_all_vertices()?;
        let current_count = vertices.len();
        
        if current_count > last_count {
            let new_vertices = vertices.iter().skip(last_count).cloned().collect::<Vec<_>>();
            
            for vertex in &new_vertices {
                tx.send(format!("New DAG vertex: {}", vertex.id)).await
                    .map_err(|e| NodeError::Dag(format!("Failed to send DAG event: {}", e)))?;
            }
            
            last_count = current_count;
        }
        
        // Wait before checking again
        time::sleep(Duration::from_secs(5)).await;
    }
}

// Get DAG logs
pub fn get_dag_logs() -> NodeResult<String> {
    let log_path = get_dag_log_path()?;
    
    if !log_path.exists() {
        return Ok("No DAG logs found".to_string());
    }
    
    let content = fs::read_to_string(log_path)
        .map_err(|e| NodeError::Dag(format!("Failed to read DAG log: {}", e)))?;
    
    Ok(content)
}

// Get DAG log path
fn get_dag_log_path() -> NodeResult<PathBuf> {
    let state_dir = state::get_state_dir()?;
    let logs_dir = state_dir.join("logs");
    
    // Ensure the directory exists
    fs::create_dir_all(&logs_dir)?;
    
    Ok(logs_dir.join("dag.log"))
} 