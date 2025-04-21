use crate::error::{NodeError, NodeResult};
use crate::executor;
use crate::state;
use async_trait::async_trait;
use notify::{Event, EventKind, RecursiveMode, Watcher};
use serde::{Deserialize, Serialize};
use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;
use tokio::sync::mpsc;
use tracing::{debug, error, info, warn};

// Proposal structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Proposal {
    pub id: String,
    pub title: String,
    pub content: String,
    pub status: ProposalStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum ProposalStatus {
    Pending,
    Executing,
    Completed,
    Failed,
    Rejected,
}

// Process all pending proposals in the queue
pub async fn process_queue() -> NodeResult<u32> {
    let queue_dir = get_queue_dir()?;
    let mut processed_count = 0;

    // Create queue directory if it doesn't exist
    fs::create_dir_all(&queue_dir)?;

    // Find all pending proposal files
    let entries = fs::read_dir(&queue_dir)?;
    let mut proposal_files = Vec::new();

    for entry in entries {
        let entry = entry?;
        let path = entry.path();

        if let Some(filename) = path.file_name().and_then(|f| f.to_str()) {
            if filename.ends_with("_pending.dsl") || filename.ends_with(".dsl") {
                proposal_files.push(path);
            }
        }
    }

    // Sort by proposal ID
    proposal_files.sort();

    // Process each proposal file
    for file in proposal_files {
        debug!("Processing proposal file: {:?}", file);

        // Extract proposal ID from filename
        let filename = file.file_name().unwrap().to_string_lossy();
        let proposal_id = extract_proposal_id(&filename)?;

        // Check if proposal has already been executed
        let executed_proposals = state::get_executed_proposals()?;
        if executed_proposals.contains(&proposal_id) {
            debug!("Proposal already executed, skipping: {}", proposal_id);
            continue;
        }

        // Execute the proposal
        match executor::execute_proposal_file(&file.to_string_lossy(), false).await {
            Ok(_) => {
                info!("Successfully executed proposal: {}", proposal_id);
                processed_count += 1;
            }
            Err(e) => {
                error!("Failed to execute proposal {}: {}", proposal_id, e);
                // Mark as failed in the filesystem
                update_proposal_status(&file, ProposalStatus::Failed)?;
            }
        }
    }

    Ok(processed_count)
}

// Sync proposals from AgoraNet
pub async fn sync_agoranet() -> NodeResult<u32> {
    let script_path = "../scripts/agoranet-proposal-sync.sh";
    
    // Check if the script exists
    if !Path::new(script_path).exists() {
        warn!("AgoraNet sync script not found: {}", script_path);
        return Ok(0);
    }
    
    // Execute the script to sync proposals
    info!("Syncing proposals from AgoraNet");
    
    let output = Command::new("bash")
        .arg(script_path)
        .output()
        .map_err(|e| NodeError::Execution(format!("Failed to execute AgoraNet sync script: {}", e)))?;
    
    if !output.status.success() {
        let error_msg = String::from_utf8_lossy(&output.stderr);
        return Err(NodeError::ShellCommand {
            message: format!("AgoraNet sync failed: {}", error_msg),
            code: output.status.code().unwrap_or(-1),
        });
    }
    
    // Parse output to determine number of synced proposals
    let output_str = String::from_utf8_lossy(&output.stdout);
    let synced_count = output_str
        .lines()
        .filter(|line| line.contains("Proposal validated and added to queue"))
        .count() as u32;
    
    Ok(synced_count)
}

// Watch the proposal queue for changes
pub async fn watch_queue(tx: mpsc::Sender<String>) -> NodeResult<()> {
    let queue_dir = get_queue_dir()?;
    
    // Create queue directory if it doesn't exist
    fs::create_dir_all(&queue_dir)?;
    
    info!("Starting proposal queue watcher on {:?}", queue_dir);
    
    // Set up file watcher
    let (watcher_tx, mut watcher_rx) = std::sync::mpsc::channel();
    
    let mut watcher = notify::recommended_watcher(watcher_tx)
        .map_err(|e| NodeError::Queue(format!("Failed to create queue watcher: {}", e)))?;
    
    watcher.watch(&queue_dir, RecursiveMode::NonRecursive)
        .map_err(|e| NodeError::Queue(format!("Failed to watch queue directory: {}", e)))?;
    
    // Process file events
    loop {
        match watcher_rx.recv() {
            Ok(Ok(event)) => {
                if let EventKind::Create(_) | EventKind::Modify(_) = event.kind {
                    for path in event.paths {
                        if path.extension().map_or(false, |ext| ext == "dsl") {
                            let filename = path.file_name().unwrap().to_string_lossy().to_string();
                            tx.send(format!("New proposal file: {}", filename)).await
                                .map_err(|e| NodeError::Queue(format!("Failed to send event: {}", e)))?;
                            
                            // Automatically process the new proposal
                            tokio::spawn(async move {
                                match executor::execute_proposal_file(&path.to_string_lossy(), false).await {
                                    Ok(_) => info!("Automatically executed new proposal: {:?}", path),
                                    Err(e) => error!("Failed to execute new proposal: {}", e),
                                }
                            });
                        }
                    }
                }
            },
            Ok(Err(e)) => error!("Queue watcher error: {}", e),
            Err(e) => error!("Queue watcher channel error: {}", e),
        }
    }
}

// Extract proposal ID from filename
pub fn extract_proposal_id(filename: &str) -> NodeResult<String> {
    let parts: Vec<&str> = filename.split('_').collect();
    
    if parts.len() >= 2 && parts[0] == "proposal" {
        Ok(parts[1].to_string())
    } else {
        Err(NodeError::Queue(format!("Invalid proposal filename format: {}", filename)))
    }
}

// Update proposal status in the filesystem
pub fn update_proposal_status(file_path: &Path, status: ProposalStatus) -> NodeResult<()> {
    let filename = file_path.file_name()
        .ok_or_else(|| NodeError::Queue("Invalid proposal file path".to_string()))?
        .to_string_lossy();
    
    let proposal_id = extract_proposal_id(&filename)?;
    let dir = file_path.parent().unwrap();
    
    let status_str = match status {
        ProposalStatus::Pending => "pending",
        ProposalStatus::Executing => "executing",
        ProposalStatus::Completed => "completed",
        ProposalStatus::Failed => "failed", 
        ProposalStatus::Rejected => "rejected",
    };
    
    let new_filename = format!("proposal_{}_{}.dsl", proposal_id, status_str);
    let new_path = dir.join(new_filename);
    
    // Rename the file to reflect the new status
    fs::rename(file_path, &new_path)
        .map_err(|e| NodeError::Queue(format!("Failed to update proposal status: {}", e)))?;
    
    Ok(())
}

// Get the queue directory
pub fn get_queue_dir() -> NodeResult<PathBuf> {
    let state_dir = state::get_state_dir()?;
    let queue_dir = state_dir.join("queue");
    
    // Ensure the directory exists
    fs::create_dir_all(&queue_dir)?;
    
    Ok(queue_dir)
}

// Get the executed directory
pub fn get_executed_dir() -> NodeResult<PathBuf> {
    let state_dir = state::get_state_dir()?;
    let executed_dir = state_dir.join("executed");
    
    // Ensure the directory exists
    fs::create_dir_all(&executed_dir)?;
    
    Ok(executed_dir)
}

// Get the rejected log file
pub fn get_rejected_log() -> NodeResult<PathBuf> {
    let state_dir = state::get_state_dir()?;
    let logs_dir = state_dir.join("logs");
    
    // Ensure the directory exists
    fs::create_dir_all(&logs_dir)?;
    
    Ok(logs_dir.join("rejected.log"))
}

// Log rejected proposal
pub fn log_rejected_proposal(proposal_id: &str, reason: &str) -> NodeResult<()> {
    let log_file = get_rejected_log()?;
    
    let log_entry = format!(
        "{} - Rejected proposal: {}, Reason: {}\n",
        chrono::Utc::now(),
        proposal_id,
        reason
    );
    
    fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_file)?
        .write_all(log_entry.as_bytes())?;
    
    Ok(())
} 