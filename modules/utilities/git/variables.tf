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