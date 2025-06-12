variable "namespace" {
  type        = string
  description = "Target Kubernetes namespace for PHI workspace deployments."
  default     = "coder"
}
