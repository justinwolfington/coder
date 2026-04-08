variable "namespace" {
  type        = string
  description = "Target Kubernetes namespace for workspace deployments."
  default     = "skypilot-api-server"
}

variable "coder_url" {
  type        = string
  description = "Coder access URL for the provider."
  default     = ""
}
