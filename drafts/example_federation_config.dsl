// Example Federation Configuration Proposal
// Title: Update Federation Network Parameters

configure_federation {
  // Federation identification
  federation: {
    name: "icn-testnet",
    description: "ICN Development Testnet Federation",
    version: "0.2.0"
  },
  
  // Network parameters
  network: {
    // Minimum number of peers required for a healthy federation
    min_peers: 3,
    
    // Maximum number of peers to connect to
    max_peers: 50,
    
    // Peer discovery interval in seconds
    discovery_interval: 300,
    
    // Connection retry settings
    connection: {
      max_retries: 5,
      retry_delay: 30,
      timeout: 10
    }
  },
  
  // Consensus-related federation parameters
  consensus: {
    // Block propagation parameters
    block_propagation: {
      max_block_size: 1048576,  // 1MB
      target_block_time: 5000,  // 5 seconds
      max_block_propagation_time: 3000  // 3 seconds
    },
    
    // Federation-wide validation rules
    validation: {
      // Require signature verification from at least this many members
      min_signature_count: 2,
      // Percentage of federation members required to validate a block
      quorum_percentage: 67
    }
  },
  
  // Identity management
  identity: {
    // Allow automatic identity discovery
    auto_discovery: true,
    
    // Federation-wide identity validation rules
    validation: {
      // Minimum identity lifetime (in days) to participate in federation
      min_age_days: 1,
      // Require identity to be verified by at least this many existing members
      min_verification_count: 2
    }
  },
  
  // Resource sharing configuration
  resources: {
    // Enable federation-wide data replication
    data_replication: true,
    
    // Maximum storage allocation per node (in MB)
    max_storage_mb: 5120,
    
    // Federation-wide API rate limits (requests per minute)
    rate_limits: {
      query: 1000,
      transaction: 100
    }
  }
} 