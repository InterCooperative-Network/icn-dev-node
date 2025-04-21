// Example Parameter Change Proposal for eco-coop
proposal {
  title: "Adjust Voting Parameters for Increased Participation"
  description: "This proposal modifies governance parameters to increase participation and enhance decision-making."
}

change_parameters {
  // Parameter path and new value
  params: [
    {
      key: "governance/voting_period",
      value: "1209600s",  // 14 days in seconds (extended from 7 days)
      rationale: "Extended voting period to allow more time for deliberation and increased participation"
    },
    {
      key: "governance/quorum",
      value: "0.25",    // 25% quorum requirement (reduced from 33.4%)
      rationale: "Slightly reduced quorum to make governance more agile while maintaining sufficient participation"
    },
    {
      key: "governance/threshold",
      value: "0.55",    // 55% approval threshold
      rationale: "Increased threshold to ensure stronger consensus on successful proposals"
    },
    {
      key: "governance/min_deposit",
      value: "50token", // Reduced deposit requirement
      rationale: "Lower barrier to entry for proposal creation while maintaining spam protection"
    }
  ],
  
  // Optional: Implementation timeframe
  implementation: {
    // When these changes take effect
    effective_date: "immediate",
    
    // Whether to apply to ongoing proposals
    apply_to_pending: false
  },
  
  // Optional: Review period
  review: {
    // Whether to automatically review the effectiveness
    scheduled: true,
    
    // When to review these changes
    review_date: "2023-12-31",
    
    // Auto-revert if specified metrics aren't met
    auto_revert: false
  }
} 