module "cursor" {
  count    = var.start_count
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "1.4.1"
  agent_id = var.agent_id
}
