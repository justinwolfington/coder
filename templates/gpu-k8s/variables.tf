variable "namespace" {
  type        = string
  description = "Target Kubernetes namespace for workspace deployments."
  default     = "coder"
}

variable "coder_url" {
  type        = string
  description = "Coder access URL for the provider."
  default     = ""
}

variable "environment" {
  type        = string
  description = "Environment (e.g., production, staging, development)"
  default     = "production"
}
