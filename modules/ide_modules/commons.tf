module "code-server" {
  count    = var.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = var.agent_id
  folder   = "/home/${lower(var.user_name)}"
}

module "git-config" {
  count                 = var.start_count
  source                = "registry.coder.com/coder/git-config/coder"
  version               = "1.0.15"
  agent_id              = var.agent_id
  allow_username_change = false
  allow_email_change    = false
}

module "cursor" {
  count    = var.start_count
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "1.1.0"
  agent_id = var.agent_id
}

module "jetbrains_gateway" {
  count          = var.start_count
  source         = "registry.coder.com/coder/jetbrains-gateway/coder"
  version        = "1.2.0"
  agent_id       = var.agent_id
  folder         = "/home/${lower(var.user_name)}"
  jetbrains_ides = ["PY"]
  default        = "PY"
}