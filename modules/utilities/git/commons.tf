terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "2.7.0"
    }
  }
}

module "git-clone" {
  count    = var.start_count > 0 && var.should_clone ? 1 : 0
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "1.1.0"
  agent_id = var.agent_id
  url      = var.repo_url
}

module "git-config" {
  source                = "registry.coder.com/coder/git-config/coder"
  version               = "1.0.15"
  agent_id              = var.agent_id
  allow_username_change = false
  allow_email_change    = false
}

data "coder_external_auth" "github" {
  count = var.require_github_auth && var.start_count > 0 ? 1 : 0
  id    = var.github_auth_id
}
