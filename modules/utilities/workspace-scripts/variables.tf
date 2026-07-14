variable "start_count" {
  type        = number
  description = "Number of instances to start (0 when the workspace is stopped)"
}

variable "agent_id" {
  type        = string
  description = "Coder agent ID"
}

variable "should_clone" {
  type        = bool
  description = "Whether a repository will be cloned; drives the GitHub auth precondition"
}

variable "repo_url" {
  type        = string
  description = "Repository URL referenced in the GitHub auth message"
  default     = ""
}

variable "install_claude_code" {
  type        = bool
  description = "Install the Claude Code CLI as a non-blocking startup step"
  default     = true
}
