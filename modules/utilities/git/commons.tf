module "git-clone" {
  count    = var.start_count > 0 && var.should_clone ? 1 : 0
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "1.0.18"
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
