# New asset registration template
# Format: CoVM DSL v1.0

asset.register {
  id: "{{ASSET_ID}}",
  name: "{{ASSET_NAME}}",
  type: "{{ASSET_TYPE}}",
  owner: "{{OWNER_ID}}",
  metadata: {
    description: "{{DESCRIPTION}}",
    creation_date: "{{CREATION_DATE}}",
    tags: [{{TAGS}}]
  },
  permissions: {
    transfer: [{{TRANSFER_PERMISSIONS}}],
    view: [{{VIEW_PERMISSIONS}}],
    update: [{{UPDATE_PERMISSIONS}}]
  }
} 