use clap::{App, Arg, SubCommand};
use reqwest;
use serde_json::{json, Value};
use std::error::Error;
use std::io::{self, Write};
use std::process;

const VERSION: &str = "0.1.0";

/// Main entry point for the ICN CLI application
fn main() {
    let app = App::new("icn-cli")
        .version(VERSION)
        .about("Command-line interface for ICN node management")
        .subcommand(
            SubCommand::with_name("dag")
                .about("DAG inspection and replay operations")
                .subcommand(
                    SubCommand::with_name("info")
                        .about("Show general DAG information")
                        .arg(
                            Arg::with_name("json")
                                .long("json")
                                .help("Output in JSON format"),
                        )
                        .arg(
                            Arg::with_name("node-url")
                                .long("node-url")
                                .takes_value(true)
                                .help("Node RPC URL (default: http://localhost:26657)"),
                        ),
                )
                .subcommand(
                    SubCommand::with_name("proposals")
                        .about("List all proposals in the DAG")
                        .arg(
                            Arg::with_name("json")
                                .long("json")
                                .help("Output in JSON format"),
                        )
                        .arg(
                            Arg::with_name("node-url")
                                .long("node-url")
                                .takes_value(true)
                                .help("Node RPC URL (default: http://localhost:26657)"),
                        ),
                )
                .subcommand(
                    SubCommand::with_name("proposal")
                        .about("Show details for a specific proposal")
                        .arg(
                            Arg::with_name("id")
                                .required(true)
                                .help("Proposal ID to show"),
                        )
                        .arg(
                            Arg::with_name("json")
                                .long("json")
                                .help("Output in JSON format"),
                        )
                        .arg(
                            Arg::with_name("node-url")
                                .long("node-url")
                                .takes_value(true)
                                .help("Node RPC URL (default: http://localhost:26657)"),
                        ),
                )
                .subcommand(
                    SubCommand::with_name("vertex")
                        .about("Show details for a specific DAG vertex")
                        .arg(
                            Arg::with_name("id")
                                .required(true)
                                .help("Vertex ID to show"),
                        )
                        .arg(
                            Arg::with_name("json")
                                .long("json")
                                .help("Output in JSON format"),
                        )
                        .arg(
                            Arg::with_name("node-url")
                                .long("node-url")
                                .takes_value(true)
                                .help("Node RPC URL (default: http://localhost:26657)"),
                        ),
                ),
        );

    let matches = app.get_matches();

    if let Some(matches) = matches.subcommand_matches("dag") {
        if let Some(matches) = matches.subcommand_matches("info") {
            let node_url = matches
                .value_of("node-url")
                .unwrap_or("http://localhost:26657");
            let use_json = matches.is_present("json");

            if let Err(e) = get_dag_info(node_url, use_json) {
                eprintln!("Error: {}", e);
                process::exit(1);
            }
        } else if let Some(matches) = matches.subcommand_matches("proposals") {
            let node_url = matches
                .value_of("node-url")
                .unwrap_or("http://localhost:26657");
            let use_json = matches.is_present("json");

            if let Err(e) = list_proposals(node_url, use_json) {
                eprintln!("Error: {}", e);
                process::exit(1);
            }
        } else if let Some(matches) = matches.subcommand_matches("proposal") {
            let node_url = matches
                .value_of("node-url")
                .unwrap_or("http://localhost:26657");
            let use_json = matches.is_present("json");
            let proposal_id = matches.value_of("id").unwrap();

            if let Err(e) = show_proposal(node_url, proposal_id, use_json) {
                eprintln!("Error: {}", e);
                process::exit(1);
            }
        } else if let Some(matches) = matches.subcommand_matches("vertex") {
            let node_url = matches
                .value_of("node-url")
                .unwrap_or("http://localhost:26657");
            let use_json = matches.is_present("json");
            let vertex_id = matches.value_of("id").unwrap();

            if let Err(e) = show_vertex(node_url, vertex_id, use_json) {
                eprintln!("Error: {}", e);
                process::exit(1);
            }
        } else {
            eprintln!("No valid subcommand provided for 'dag'");
            process::exit(1);
        }
    } else {
        eprintln!("No valid command provided. Use --help for usage information.");
        process::exit(1);
    }
}

/// Get general DAG information
fn get_dag_info(node_url: &str, use_json: bool) -> Result<(), Box<dyn Error>> {
    let dag_info_url = format!("{}/dag_info", node_url);
    let response = reqwest::blocking::get(&dag_info_url)?.json::<Value>()?;

    if use_json {
        println!("{}", serde_json::to_string_pretty(&response)?);
    } else {
        let dag_info = &response["result"]["dag_info"];
        
        println!("DAG Summary:");
        println!("Vertex Count: {}", dag_info["vertex_count"]);
        println!("Root Count: {}", dag_info["root_count"]);
        println!("Tip Count: {}", dag_info["tip_count"]);
        println!("Genesis Time: {}", dag_info["genesis_time"]);
        println!("Latest Update: {}", dag_info["latest_update"]);
        
        println!("\nLatest Tips:");
        if let Some(tips) = dag_info["tips"].as_array() {
            for tip in tips {
                let summary = tip["summary"].as_str().unwrap_or("No summary");
                println!("- {}: {}", tip["id"], summary);
            }
        } else {
            println!("No tips found");
        }
    }

    Ok(())
}

/// List all proposals in the DAG
fn list_proposals(node_url: &str, use_json: bool) -> Result<(), Box<dyn Error>> {
    let proposals_url = format!("{}/abci_query?path=\"/proposals/list\"", node_url);
    let response = reqwest::blocking::get(&proposals_url)?.json::<Value>()?;
    
    // Extract proposals from response
    let proposals = if let Some(value) = response["result"]["response"]["value"].as_str() {
        let decoded = base64::decode(value)?;
        let decoded_str = String::from_utf8(decoded)?;
        serde_json::from_str::<Value>(&decoded_str)?
    } else {
        json!([])
    };

    if use_json {
        println!("{}", serde_json::to_string_pretty(&proposals)?);
    } else {
        println!("Proposals:");
        if let Some(proposals_array) = proposals.as_array() {
            if proposals_array.is_empty() {
                println!("No proposals found");
            } else {
                for proposal in proposals_array {
                    println!("----------------------------------------");
                    println!("ID: {}", proposal["id"]);
                    println!("Title: {}", proposal["title"]);
                    println!("Status: {}", proposal["status"]);
                    println!("Proposer: {}", proposal["proposer"]);
                }
                println!("----------------------------------------");
                println!("Total proposals: {}", proposals_array.len());
            }
        } else {
            println!("No proposals found");
        }
    }

    Ok(())
}

/// Show details for a specific proposal
fn show_proposal(node_url: &str, proposal_id: &str, use_json: bool) -> Result<(), Box<dyn Error>> {
    let proposal_url = format!("{}/abci_query?path=\"/custom/gov/proposal/{}\"", node_url, proposal_id);
    let response = reqwest::blocking::get(&proposal_url)?.json::<Value>()?;
    
    // Extract proposal data from response
    let proposal = if let Some(value) = response["result"]["response"]["value"].as_str() {
        let decoded = base64::decode(value)?;
        let decoded_str = String::from_utf8(decoded)?;
        serde_json::from_str::<Value>(&decoded_str)?
    } else {
        return Err(format!("Proposal not found: {}", proposal_id).into());
    };

    // Get votes for this proposal
    let votes_url = format!("{}/abci_query?path=\"/custom/gov/votes/{}\"", node_url, proposal_id);
    let votes_response = reqwest::blocking::get(&votes_url)?.json::<Value>()?;
    
    let votes = if let Some(value) = votes_response["result"]["response"]["value"].as_str() {
        let decoded = base64::decode(value)?;
        let decoded_str = String::from_utf8(decoded)?;
        serde_json::from_str::<Value>(&decoded_str)?
    } else {
        json!([])
    };

    if use_json {
        let combined = json!({
            "proposal": proposal,
            "votes": votes
        });
        println!("{}", serde_json::to_string_pretty(&combined)?);
    } else {
        println!("Proposal Details:");
        println!("ID: {}", proposal["id"]);
        println!("Title: {}", proposal["title"]);
        println!("Description: {}", proposal["description"]);
        println!("Status: {}", proposal["status"]);
        println!("Proposer: {}", proposal["proposer"]);
        println!("Submitted At: {}", proposal["submitted_at"]);
        println!("Voting End Time: {}", proposal["voting_end_time"]);
        
        if let Some(final_tally) = proposal["final_tally"].as_object() {
            println!("\nFinal Tally:");
            for (key, value) in final_tally {
                println!("  {}: {}", key, value);
            }
        }
        
        println!("\nVotes:");
        if let Some(votes_array) = votes.as_array() {
            if votes_array.is_empty() {
                println!("No votes found");
            } else {
                for vote in votes_array {
                    println!("- {}: {} ({})", vote["voter"], vote["option"], vote["time"]);
                }
            }
        } else {
            println!("No votes found");
        }
        
        println!("\nProposal Lifecycle:");
        println!("Submission → Discussion → Voting → Execution");
    }

    Ok(())
}

/// Show details for a specific vertex
fn show_vertex(node_url: &str, vertex_id: &str, use_json: bool) -> Result<(), Box<dyn Error>> {
    let vertex_url = format!("{}/dag_vertex?id={}", node_url, vertex_id);
    let response = reqwest::blocking::get(&vertex_url)?.json::<Value>()?;
    
    if response["error"].is_object() {
        return Err(format!("Vertex not found: {}", vertex_id).into());
    }
    
    let vertex = &response["result"]["vertex"];

    if use_json {
        println!("{}", serde_json::to_string_pretty(&vertex)?);
    } else {
        println!("Vertex Details:");
        println!("ID: {}", vertex["id"]);
        println!("Timestamp: {}", vertex["timestamp"]);
        println!("Height: {}", vertex["height"]);
        println!("Proposer: {}", vertex["proposer"]);
        println!("Data Type: {}", vertex["data_type"]);
        println!("Scope: {}", vertex["scope"]);
        
        println!("\nParents:");
        if let Some(parents) = vertex["parents"].as_array() {
            if parents.is_empty() {
                println!("No parents (root vertex)");
            } else {
                for parent in parents {
                    println!("- {}", parent);
                }
            }
        }
        
        println!("\nChildren:");
        if let Some(children) = vertex["children"].as_array() {
            if children.is_empty() {
                println!("No children (tip vertex)");
            } else {
                for child in children {
                    println!("- {}", child);
                }
            }
        }
    }

    Ok(())
} 