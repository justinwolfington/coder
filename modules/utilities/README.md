# Coder Utilities Module

This module provides common utility configurations for Coder workspaces including Git and IDE integrations.

## Purpose

Centralizes frequently used utility modules to avoid duplication across templates and ensure consistency.

## Available Utilities

### Git Utilities (git/)
- `git-clone` - Clone repositories on workspace startup
- `git-config` - Configure git user settings

### IDE Utilities (ide/)
- `cursor` - Cursor IDE
- `jetbrains_gateway` - JetBrains Gateway with PyCharm

## Usage Example

```hcl
module "git_utils" {
  source       = "../modules/utilities/git"
  start_count  = 1
  agent_id     = coder_agent.main.id
  repo_url     = data.coder_parameter.repo_url.value
  should_clone = true
}

module "ide_utils" {
  source      = "../modules/utilities/ide"
  start_count = 1
  agent_id    = coder_agent.main.id
  user_name   = data.coder_workspace.me.owner
}
```
