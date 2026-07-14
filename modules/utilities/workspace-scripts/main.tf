# Shared workspace startup steps, split into independent named coder_script
# resources so each shows its own log/status in the Coder UI. coder_script
# resources run in parallel with no ordering, so only genuinely independent
# work lives here; template-specific setup (code-server, node, etc.) stays local.

# Blocking precondition: fail fast if a repo is requested but GitHub auth is
# missing, so the workspace reports unhealthy instead of silently skipping.
resource "coder_script" "github_auth" {
  count              = var.start_count
  agent_id           = var.agent_id
  display_name       = "GitHub authentication"
  run_on_start       = true
  start_blocks_login = true
  script             = <<-EOT
    #!/bin/bash
    set -euo pipefail
    if [ "${var.should_clone}" = "true" ] && [ -z "$${GITHUB_TOKEN:-}" ]; then
      echo "GitHub authentication required to clone ${var.repo_url}"
      echo "Please authenticate via Coder (Account -> External Authentication)"
      exit 1
    fi
    echo "GitHub authentication OK"
  EOT
}

# Best-effort, independent: install Claude Code CLI without blocking login.
resource "coder_script" "claude_code" {
  count        = var.install_claude_code ? var.start_count : 0
  agent_id     = var.agent_id
  display_name = "Install Claude Code"
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    echo "Installing Claude Code CLI..."
    curl -fsSL https://claude.ai/install.sh | bash || echo "Claude Code installation failed, continuing..."
  EOT
}
