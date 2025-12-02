variable "namespace" {
  type        = string
  description = "Target Kubernetes namespace for workspace deployments."
  default     = "coder"
}

variable "anthropic_api_key" {
  type        = string
  description = "Anthropic API key for Claude Code (uses API billing mode, optional)"
  sensitive   = true
  default     = ""
}

variable "openai_api_key" {
  type        = string
  description = "OpenAI API key for Codex (optional)"
  sensitive   = true
  default     = ""
}
