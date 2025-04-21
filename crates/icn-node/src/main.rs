use anyhow::Result;
use clap::{Parser, Subcommand};
use tracing::{debug, error, info, Level};
use tracing_subscriber::FmtSubscriber;

mod executor;
mod queue;
mod dag;
mod federation;
mod state;
mod error;

#[derive(Parser)]
#[command(author, version, about = "Cooperative Node Runner for the Intercooperative Network")]
struct Cli {
    #[command(subcommand)]
    command: Commands,

    /// Set the log level
    #[arg(short, long, global = true, default_value = "info")]
    log_level: Level,
}

#[derive(Subcommand)]
enum Commands {
    /// Run the node in daemon mode
    Run {
        /// Check interval in seconds
        #[arg(long, default_value = "30")]
        interval: u64,
    },
    
    /// Execute a specific proposal
    Execute {
        /// Path to the proposal file
        #[arg(long)]
        file: String,
        
        /// Bypass validation
        #[arg(long, default_value = "false")]
        force: bool,
    },
    
    /// Trace a proposal execution
    Trace {
        /// Proposal ID to trace
        #[arg(long)]
        proposal: String,
    },
    
    /// Watch the DAG and proposal queue
    Watch,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    
    // Initialize logging
    let subscriber = FmtSubscriber::builder()
        .with_max_level(cli.log_level)
        .finish();
    tracing::subscriber::set_global_default(subscriber)
        .expect("Failed to set tracing subscriber");
        
    // Initialize state
    state::init()?;
    
    match cli.command {
        Commands::Run { interval } => {
            info!("Starting cooperative node runner with {}s check interval", interval);
            run_daemon(interval).await
        },
        Commands::Execute { file, force } => {
            info!("Executing proposal from file: {}", file);
            match executor::execute_proposal_file(&file, force).await {
                Ok(result) => {
                    info!("Execution completed with status: {}", result.status_code);
                    Ok(())
                },
                Err(e) => Err(anyhow::anyhow!("Execution failed: {}", e))
            }
        },
        Commands::Trace { proposal } => {
            info!("Tracing proposal: {}", proposal);
            match executor::trace_proposal(&proposal).await {
                Ok(_) => Ok(()),
                Err(e) => Err(anyhow::anyhow!("Tracing failed: {}", e))
            }
        },
        Commands::Watch => {
            info!("Watching DAG and proposal queue");
            watch_dag_and_queue().await
        },
    }
}

async fn run_daemon(interval: u64) -> Result<()> {
    info!("Starting cooperative node daemon");
    
    loop {
        debug!("Checking proposal queue");
        
        // Process proposal queue
        match queue::process_queue().await {
            Ok(count) => {
                if count > 0 {
                    info!("Processed {} proposals", count);
                }
            },
            Err(e) => error!("Error processing queue: {}", e),
        }
        
        // Sync with AgoraNet
        match queue::sync_agoranet().await {
            Ok(count) => {
                if count > 0 {
                    info!("Synced {} proposals from AgoraNet", count);
                }
            },
            Err(e) => error!("Error syncing from AgoraNet: {}", e),
        }
        
        // Wait for the next interval
        tokio::time::sleep(tokio::time::Duration::from_secs(interval)).await;
    }
}

async fn watch_dag_and_queue() -> Result<()> {
    info!("Starting DAG and queue watcher");
    
    // Set up combined watcher for DAG and queue
    let (dag_tx, mut dag_rx) = tokio::sync::mpsc::channel(100);
    let (queue_tx, mut queue_rx) = tokio::sync::mpsc::channel(100);
    
    // Start DAG watcher
    tokio::spawn(async move {
        if let Err(e) = dag::watch_dag(dag_tx).await {
            error!("DAG watcher error: {}", e);
        }
    });
    
    // Start queue watcher
    tokio::spawn(async move {
        if let Err(e) = queue::watch_queue(queue_tx).await {
            error!("Queue watcher error: {}", e);
        }
    });
    
    // Process events from both watchers
    loop {
        tokio::select! {
            Some(event) = dag_rx.recv() => {
                info!("DAG event: {}", event);
            }
            Some(event) = queue_rx.recv() => {
                info!("Queue event: {}", event);
            }
            else => break,
        }
    }
    
    Ok(())
} 