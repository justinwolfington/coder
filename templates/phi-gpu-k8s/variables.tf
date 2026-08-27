variable "namespace" {
  type        = string
  description = "Target Kubernetes namespace for PHI workspace deployments."
  default     = "coder"
}

variable "coder_url" {
  type        = string
  description = "Coder access URL for the provider."
  default     = ""
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
variable "langsmith_endpoint" {
  type        = string
  description = "LangSmith API endpoint for workspace SDKs. Points at the in-cluster broker access proxy (PRODSEC-580); empty omits the env var."
  default     = ""
}

variable "langsmith_annotation_endpoint" {
  type        = string
  description = "LangSmith API endpoint for the PHI annotation workspace, via the annotation access proxy (SECPRIV-14015); empty omits the env var."
  default     = ""
}

variable "phi_workspace_utd_service_account" {
  type        = string
  description = "No-RBAC Kubernetes service account mapped to the bucket-only UTD GCP identity. Empty preserves the legacy Coder KSA fallback."
  default     = ""
}
