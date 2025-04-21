# Basic governance proposal template for ICN
# Format: CoVM DSL v1.0

proposal {
  title: "{{TITLE}}",
  author: "{{AUTHOR}}",
  description: """
    {{DESCRIPTION}}
  """,
  actions: [
    {{ACTIONS}}
  ],
  requires: {
    quorum: {{QUORUM}},
    acceptance: {{ACCEPTANCE}}
  }
} 