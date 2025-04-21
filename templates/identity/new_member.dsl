# New member registration template
# Format: CoVM DSL v1.0

identity.register {
  name: "{{NAME}}",
  pubkey: "{{PUBKEY}}",
  metadata: {
    email: "{{EMAIL}}",
    org: "{{ORGANIZATION}}",
    role: "{{ROLE}}"
  },
  permissions: [
    {{PERMISSIONS}}
  ]
} 