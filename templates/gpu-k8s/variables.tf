variable "namespace" {
  type        = string
  description = "Target Kubernetes namespace for workspace deployments."
  default     = "coder"
}

variable "environment" {
  type        = string
  description = "Environment (e.g., production, staging, development)"
  default     = "production"
}

variable "anthropic_api_key" {
  type        = string
  description = "Anthropic API key for Claude Code (uses API billing mode, optional)"
  sensitive   = true
  default     = ""
}
