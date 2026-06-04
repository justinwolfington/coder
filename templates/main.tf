terraform {
  required_providers {
    coderd = {
      source  = "coder/coderd"
      version = "0.0.16"
    }
  }
}

provider "coderd" {
  url   = var.coder_url
  token = var.coder_token
}

# Create Coder templates based on filtered configuration
# Assumes that the templates are already filtered in the templates-config.tf file
# (dummy change to validate PR workflow)
resource "coderd_template" "templates" {
  for_each = local.filtered_templates

  name         = each.key
  display_name = each.value.display_name
  description  = each.value.description
  icon         = each.value.icon

  # Optional timing parameters - only set if specified in config
  activity_bump_ms    = try(each.value.activity_bump_ms, null)
  failure_ttl_ms      = try(each.value.failure_ttl_ms, null)
  time_til_dormant_ms = try(each.value.time_til_dormant_ms, null)
  default_ttl_ms      = try(each.value.default_ttl_ms, null)

  # Version management through the Coder provider
  versions = [{
    name      = var.commit_sha
    message   = "Auto-deploy ${var.commit_sha} to ${var.environment}"
    directory = each.value.directory
    active    = true
  }]
}

# Note: Template versioning is handled directly by the coderd_template resource above
# The versions block in the resource automatically:
# 1. Pushes the template from the specified directory
# 2. Creates a new version with the commit SHA
# 3. Sets it as active (promotes it)

# Output deployed templates for visibility
output "deployed_templates" {
  description = "Templates deployed in this run"
  value = {
    environment = var.environment
    version     = var.commit_sha
    templates   = keys(local.filtered_templates)
  }
}
