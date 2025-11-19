variable "namespace" {
  type        = string
  description = "Target Kubernetes namespace for PHI workspace deployments."
  default     = "coder"
}

variable "environment" {
  type        = string
  description = "Target environment (development, staging, production)"
  default     = "development"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "The environment must be one of: development, staging, or production."
  }
}