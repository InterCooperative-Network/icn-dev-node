use crate::error::{NodeError, NodeResult};
use crate::queue::{self, ProposalStatus};
use crate::state::{self, VertexEntry};
use chrono::Utc;
use icn_covm::{execute_program_from_path, ExecutionResult as CoVMExecutionResult, VMOptions};
use serde::{Deserialize, Serialize};
use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

// Execution result structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionResult {
    pub proposal_id: String,
    pub timestamp: chrono::DateTime<Utc>,
    pub status_code: i32,
    pub vertex_id: Option<String>,
    pub output: String,
}

// Execute a proposal from a file
pub async fn execute_proposal_file(file_path: &str, force: bool) -> NodeResult<ExecutionResult> {
    let path = Path::new(file_path);
    
    if !path.exists() {
        return Err(NodeError::Execution(format!("Proposal file not found: {}", file_path)));
    }

    // Extract proposal ID from filename
    let filename = path.file_name()
        .ok_or_else(|| NodeError::Execution("Invalid proposal file path".to_string()))?
        .to_string_lossy();
    
    let proposal_id = if let Ok(id) = queue::extract_proposal_id(&filename) {
        id
    } else {
        // If not in standard format, use the filename as ID
        filename.to_string()
    };
    
    info!("Executing proposal: {}", proposal_id);
    
    // Validate proposal if not forcing execution
    if !force && !validate_proposal(path)? {
        let reason = "Proposal validation failed";
        queue::log_rejected_proposal(&proposal_id, reason)?;
        return Err(NodeError::Validation(reason.to_string()));
    }
    
    // Update status to executing
    if path.starts_with(queue::get_queue_dir()?) {
        queue::update_proposal_status(path, ProposalStatus::Executing)?;
    }
    
    // Execute proposal with CoVM
    let result = run_covm(path)?;
    
    // Process execution result
    if result.status_code == 0 {
        info!("Proposal executed successfully: {}", proposal_id);
        
        // Move to executed directory if it was in the queue
        if path.starts_with(queue::get_queue_dir()?) {
            let executed_dir = queue::get_executed_dir()?;
            let dest_path = executed_dir.join(format!("proposal_{}_completed.dsl", proposal_id));
            
            fs::copy(path, &dest_path)?;
            
            // Update status to completed
            queue::update_proposal_status(path, ProposalStatus::Completed)?;
        }
        
        // Record execution in state
        state::add_executed_proposal(&proposal_id)?;
        
        // Generate and record DAG vertex
        let vertex_id = result.vertex_id.clone().unwrap_or_else(|| Uuid::new_v4().to_string());
        
        let vertex = VertexEntry {
            id: vertex_id.clone(),
            proposal_id: proposal_id.clone(),
            timestamp: Utc::now(),
            hash: generate_content_hash(path)?,
        };
        
        state::add_vertex(vertex)?;
        
        // Store execution output
        store_execution_output(&proposal_id, &result)?;
    } else {
        // Update status to failed if it was in the queue
        if path.starts_with(queue::get_queue_dir()?) {
            queue::update_proposal_status(path, ProposalStatus::Failed)?;
        }
        
        error!("Proposal execution failed: {}, status: {}", proposal_id, result.status_code);
    }
    
    Ok(result)
}

// Trace a proposal execution by ID
pub async fn trace_proposal(proposal_id: &str) -> NodeResult<()> {
    // Try to find the proposal in executed directory
    let executed_dir = queue::get_executed_dir()?;
    let mut proposal_path = None;
    
    if executed_dir.exists() {
        for entry in fs::read_dir(executed_dir)? {
            let entry = entry?;
            let path = entry.path();
            
            if let Some(filename) = path.file_name().and_then(|f| f.to_str()) {
                if filename.contains(&format!("proposal_{}_", proposal_id)) {
                    proposal_path = Some(path);
                    break;
                }
            }
        }
    }
    
    if proposal_path.is_none() {
        // Try to find the proposal in the queue directory
        let queue_dir = queue::get_queue_dir()?;
        
        if queue_dir.exists() {
            for entry in fs::read_dir(queue_dir)? {
                let entry = entry?;
                let path = entry.path();
                
                if let Some(filename) = path.file_name().and_then(|f| f.to_str()) {
                    if filename.contains(&format!("proposal_{}_", proposal_id)) {
                        proposal_path = Some(path);
                        break;
                    }
                }
            }
        }
    }
    
    if let Some(path) = proposal_path {
        info!("Found proposal file: {:?}", path);
        
        // Get execution output if available
        let state_dir = state::get_state_dir()?;
        let output_dir = state_dir.join("output");
        let output_files: Vec<PathBuf> = fs::read_dir(output_dir)
            .map(|entries| {
                entries
                    .filter_map(Result::ok)
                    .map(|e| e.path())
                    .filter(|p| {
                        p.file_name()
                            .and_then(|f| f.to_str())
                            .map_or(false, |name| name.contains(&format!("execution_{}_", proposal_id)))
                    })
                    .collect()
            })
            .unwrap_or_default();
            
        if !output_files.is_empty() {
            // Sort by timestamp (newest first)
            let mut output_files = output_files;
            output_files.sort_by(|a, b| b.file_name().cmp(&a.file_name()));
            
            let latest_output = &output_files[0];
            info!("Latest execution output: {:?}", latest_output);
            
            let output_content = fs::read_to_string(latest_output)
                .map_err(|e| NodeError::Execution(format!("Failed to read output file: {}", e)))?;
                
            println!("Execution Output for Proposal {}:", proposal_id);
            println!("----------------------------------------");
            println!("{}", output_content);
            println!("----------------------------------------");
        } else {
            info!("No execution output found for proposal: {}", proposal_id);
            println!("No execution output found for proposal: {}", proposal_id);
        }
        
        // Execute proposal with trace mode
        let mut options = VMOptions::default();
        options.trace = true;
        options.explain = true;
        options.verbose = true;
        
        let result = execute_program_from_path(&path, options)
            .map_err(|e| NodeError::Execution(format!("Failed to trace execution: {}", e)))?;
        
        println!("Trace Output:");
        println!("----------------------------------------");
        println!("{}", result.output);
        println!("----------------------------------------");
    } else {
        return Err(NodeError::Execution(format!("Proposal not found: {}", proposal_id)));
    }
    
    Ok(())
}

// Validate a proposal
fn validate_proposal(path: &Path) -> NodeResult<bool> {
    info!("Validating proposal: {:?}", path);
    
    // First check basic structure
    let content = fs::read_to_string(path)
        .map_err(|e| NodeError::Validation(format!("Failed to read proposal file: {}", e)))?;
    
    // Basic checks (these could be improved with actual parsing)
    if !content.contains('{') || !content.contains('}') {
        let reason = "Proposal missing valid JSON structure";
        warn!("{}: {:?}", reason, path);
        return Ok(false);
    }
    
    // If the proposal is a governance proposal, check for required fields
    if content.contains("proposal") {
        if !content.contains("title:") {
            let reason = "Governance proposal missing required 'title' field";
            warn!("{}: {:?}", reason, path);
            return Ok(false);
        }
        
        if !content.contains("description:") {
            let reason = "Governance proposal missing required 'description' field";
            warn!("{}: {:?}", reason, path);
            return Ok(false);
        }
    }
    
    // Use CoVM directly to validate
    let mut options = VMOptions::default();
    options.simulate = true; // Don't make changes during validation
    
    match execute_program_from_path(path, options) {
        Ok(_) => {
            debug!("CoVM validation successful");
            Ok(true)
        }
        Err(e) => {
            warn!("CoVM validation failed: {}", e);
            Ok(false)
        }
    }
}

// Execute proposal with CoVM
fn run_covm(path: &Path) -> NodeResult<ExecutionResult> {
    info!("Running CoVM execution for: {:?}", path);
    
    // Create VM options
    let mut options = VMOptions::default();
    options.use_stdlib = true;
    options.storage_backend = "file".to_string();
    
    // Get data directory for storage path
    let data_dir = dirs::home_dir()
        .ok_or_else(|| NodeError::Execution("Could not determine home directory".to_string()))?
        .join(".icn");
    
    options.storage_path = data_dir.join("storage").to_string_lossy().to_string();
    
    // Set the identity if it exists
    let identity_file = data_dir.join("identity.json");
    if identity_file.exists() {
        options.identity_path = Some(identity_file.to_string_lossy().to_string());
    }
    
    // Execute the program
    let covm_result = execute_program_from_path(path, options)
        .map_err(|e| NodeError::Execution(format!("CoVM execution failed: {}", e)))?;
    
    let filename = path.file_name()
        .ok_or_else(|| NodeError::Execution("Invalid proposal file path".to_string()))?
        .to_string_lossy();
    
    let proposal_id = if let Ok(id) = queue::extract_proposal_id(&filename) {
        id
    } else {
        filename.to_string()
    };
    
    let result = ExecutionResult {
        proposal_id,
        timestamp: Utc::now(),
        status_code: covm_result.status_code,
        vertex_id: covm_result.vertex_id,
        output: covm_result.output,
    };
    
    Ok(result)
}

// Store execution output to file
fn store_execution_output(proposal_id: &str, result: &ExecutionResult) -> NodeResult<PathBuf> {
    let state_dir = state::get_state_dir()?;
    let output_dir = state_dir.join("output");
    
    // Create output directory if it doesn't exist
    fs::create_dir_all(&output_dir)?;
    
    let timestamp = result.timestamp.format("%Y%m%d_%H%M%S");
    let output_file = output_dir.join(format!("execution_{}_{}.json", proposal_id, timestamp));
    
    // Write output to file
    let mut file = File::create(&output_file)?;
    let serialized = serde_json::to_string_pretty(result)?;
    file.write_all(serialized.as_bytes())?;
    
    Ok(output_file)
}

// Generate a content hash for a proposal file
fn generate_content_hash(path: &Path) -> NodeResult<String> {
    let content = fs::read_to_string(path)
        .map_err(|e| NodeError::Execution(format!("Failed to read proposal file: {}", e)))?;
    
    // Use a simple hash for now
    let hash = format!("{:x}", md5::compute(content));
    
    Ok(hash)
} 