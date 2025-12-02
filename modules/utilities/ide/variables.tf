variable "start_count" {
  type        = number
  description = "Number of instances to start"
}

variable "agent_id" {
  type        = string
  description = "Coder agent ID"
}

variable "user_name" {
  type        = string
  description = "User name"
}

variable "workdir" {
  type        = string
  description = "Working directory for Claude Code"
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

variable "enable_codex_tasks" {
  type        = bool
  description = "Enable task reporting in Codex"
  default     = false
}