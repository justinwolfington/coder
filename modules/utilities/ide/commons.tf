module "cursor" {
  count    = var.start_count
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "1.3.3"
  agent_id = var.agent_id
}

module "jetbrains_gateway" {
  count          = var.start_count
  source         = "registry.coder.com/coder/jetbrains-gateway/coder"
  version        = "1.2.6"
  agent_id       = var.agent_id
  folder         = "/home/${lower(var.user_name)}"
  jetbrains_ides = ["PY"]
  default        = "PY"
}

module "claude-code" {
  count          = var.start_count > 0 && var.anthropic_api_key != "" ? 1 : 0
  source         = "registry.coder.com/coder/claude-code/coder"
  version        = "4.2.3"
  agent_id       = var.agent_id
  workdir        = var.workdir
  claude_api_key = var.anthropic_api_key
}
