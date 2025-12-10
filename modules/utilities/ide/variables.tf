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

variable "enable_jetbrains" {
  type        = bool
  description = "Enable JetBrains Gateway"
  default     = false
}