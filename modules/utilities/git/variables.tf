variable "start_count" {
  type        = number
  description = "Number of instances to start"
}

variable "agent_id" {
  type        = string
  description = "Coder agent ID"
}

variable "repo_url" {
  type        = string
  description = "Repository URL"
}

variable "should_clone" {
  type        = bool
  description = "Whether to clone the repository"
}

# External GitHub auth integration
variable "github_auth_id" {
  type        = string
  description = "Coder external auth provider ID for GitHub"
  default     = "primary-github"
}

variable "require_github_auth" {
  type        = bool
  description = "If true, require GitHub authentication and expose token as outputs"
  default     = true
}