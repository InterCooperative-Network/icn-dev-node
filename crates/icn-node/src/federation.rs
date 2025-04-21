use crate::error::{NodeError, NodeResult};
use crate::state::{self, VertexEntry};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::process::Command;
use tracing::{debug, info, warn};

// Federation peer structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Peer {
    pub id: String,
    pub name: String,
    pub address: String,
    pub last_seen: Option<chrono::DateTime<chrono::Utc>>,
}

// Federation status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FederationStatus {
    pub online_peers: Vec<Peer>,
    pub offline_peers: Vec<Peer>,
    pub last_check: chrono::DateTime<chrono::Utc>,
}

// Configuration for federation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FederationConfig {
    pub federation_name: String,
    pub node_id: String,
    pub node_name: String,
    pub peers: Vec<Peer>,
    pub sync_endpoint: String,
}

// Broadcast a DAG vertex to federation peers
pub async fn broadcast_vertex(vertex: &VertexEntry) -> NodeResult<()> {
    // Get federation config
    let config = get_federation_config()?;
    
    // Loop through peers and broadcast
    for peer in &config.peers {
        let client = Client::new();
        let endpoint = format!("{}/dag/vertices", peer.address);
        
        debug!("Broadcasting vertex {} to peer: {}", vertex.id, peer.name);
        
        // Only try broadcasting if the peer is online
        if check_peer_status(&peer.address).await.is_ok() {
            match client.post(&endpoint)
                .json(vertex)
                .send()
                .await {
                    Ok(response) => {
                        if response.status().is_success() {
                            info!("Successfully broadcast vertex {} to peer: {}", vertex.id, peer.name);
                        } else {
                            warn!("Failed to broadcast vertex to peer: {}, status: {}", 
                                peer.name, response.status());
                        }
                    },
                    Err(e) => {
                        warn!("Error broadcasting vertex to peer {}: {}", peer.name, e);
                    }
                }
        } else {
            debug!("Skipping offline peer: {}", peer.name);
        }
    }
    
    // Call federation sync script if it exists
    let script_path = "../scripts/federation-check.sh";
    if Path::new(script_path).exists() {
        debug!("Executing federation sync script");
        
        match Command::new("bash")
            .arg(script_path)
            .arg("--sync")
            .output() {
                Ok(output) => {
                    if !output.status.success() {
                        let error_msg = String::from_utf8_lossy(&output.stderr);
                        warn!("Federation sync script failed: {}", error_msg);
                    }
                },
                Err(e) => {
                    warn!("Failed to execute federation sync script: {}", e);
                }
            }
    }
    
    Ok(())
}

// Check federation health
pub async fn check_federation_health() -> NodeResult<FederationStatus> {
    let config = get_federation_config()?;
    let now = chrono::Utc::now();
    
    let mut online_peers = Vec::new();
    let mut offline_peers = Vec::new();
    
    // Check each peer
    for peer in &config.peers {
        if check_peer_status(&peer.address).await.is_ok() {
            let mut online_peer = peer.clone();
            online_peer.last_seen = Some(now);
            online_peers.push(online_peer);
        } else {
            offline_peers.push(peer.clone());
        }
    }
    
    let status = FederationStatus {
        online_peers,
        offline_peers,
        last_check: now,
    };
    
    Ok(status)
}

// Check if a peer is online
async fn check_peer_status(address: &str) -> NodeResult<()> {
    let client = Client::new();
    let status_endpoint = format!("{}/status", address);
    
    match client.get(&status_endpoint)
        .timeout(std::time::Duration::from_secs(5))
        .send()
        .await {
            Ok(response) => {
                if response.status().is_success() {
                    Ok(())
                } else {
                    Err(NodeError::Federation(format!(
                        "Peer returned error status: {}", response.status()
                    )))
                }
            },
            Err(e) => {
                Err(NodeError::Federation(format!("Failed to connect to peer: {}", e)))
            }
        }
}

// Get federation configuration
fn get_federation_config() -> NodeResult<FederationConfig> {
    // First try to get from state
    if let Ok(config) = state::get::<FederationConfig>("federation_config") {
        return Ok(config);
    }
    
    // If not in state, try to load from script
    let script_path = "../scripts/mesh-status.sh";
    if Path::new(script_path).exists() {
        debug!("Getting federation config from mesh-status.sh");
        
        let output = Command::new("bash")
            .arg(script_path)
            .arg("--json")
            .output()
            .map_err(|e| NodeError::Federation(format!("Failed to execute mesh status script: {}", e)))?;
            
        if output.status.success() {
            let json = String::from_utf8_lossy(&output.stdout);
            let config: FederationConfig = serde_json::from_str(&json)
                .map_err(|e| NodeError::Federation(format!("Failed to parse federation config: {}", e)))?;
                
            // Save to state for future use
            let _ = state::set("federation_config", &config);
            
            return Ok(config);
        }
    }
    
    // Default config with localhost
    let node_id = uuid::Uuid::new_v4().to_string();
    let config = FederationConfig {
        federation_name: "dev-federation".to_string(),
        node_id: node_id.clone(),
        node_name: format!("node-{}", node_id),
        peers: vec![
            Peer {
                id: "local".to_string(),
                name: "localhost".to_string(),
                address: "http://localhost:26657".to_string(),
                last_seen: None,
            }
        ],
        sync_endpoint: "http://localhost:26657/dag/sync".to_string(),
    };
    
    // Save to state
    let _ = state::set("federation_config", &config);
    
    Ok(config)
}

// Sync with federation
pub async fn sync_with_federation() -> NodeResult<()> {
    let script_path = "../scripts/federation-check.sh";
    
    if Path::new(script_path).exists() {
        info!("Syncing with federation");
        
        let output = Command::new("bash")
            .arg(script_path)
            .arg("--sync")
            .output()
            .map_err(|e| NodeError::Federation(format!("Failed to execute federation sync script: {}", e)))?;
            
        if !output.status.success() {
            let error_msg = String::from_utf8_lossy(&output.stderr);
            return Err(NodeError::ShellCommand {
                message: format!("Federation sync failed: {}", error_msg),
                code: output.status.code().unwrap_or(-1),
            });
        }
        
        info!("Federation sync completed");
    } else {
        warn!("Federation sync script not found: {}", script_path);
    }
    
    Ok(())
} 