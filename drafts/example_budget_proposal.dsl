// Example Budget Allocation Proposal for community-fund
// Title: Fund Community Garden Project

allocate_budget {
  // Recipient identity or project name
  recipient: "community-garden-working-group",
  
  // Amount of tokens to allocate
  amount: 5000,
  
  // Purpose of allocation
  purpose: "Initial funding for the community garden project including materials, seeds, and tools",
  
  // Optional: Time constraints
  timeframe: {
    start_date: "2023-06-01",
    end_date: "2023-12-31"
  },
  
  // Optional: Milestones for phased release
  milestones: [
    {
      description: "Site preparation and initial planning",
      amount: 1500,
      deadline: "2023-06-15"
    },
    {
      description: "Purchase of materials and tools",
      amount: 2000,
      deadline: "2023-07-15"
    },
    {
      description: "Planting and implementation",
      amount: 1000,
      deadline: "2023-08-15"
    },
    {
      description: "Final report and documentation",
      amount: 500,
      deadline: "2023-12-15"
    }
  ],
  
  // Optional: Reporting requirements
  reporting: {
    frequency: "monthly",
    format: "digital-report",
    required_metrics: [
      "budget_utilization",
      "project_milestones",
      "community_participation"
    ]
  }
} 