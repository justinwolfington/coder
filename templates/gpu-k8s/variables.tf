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
