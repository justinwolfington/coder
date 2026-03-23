variable "namespace" {
  type        = string
  description = "Target Kubernetes namespace for workspace deployments."
  default     = "coder"
}

variable "judges_openai_base_url" {
  type        = string
  description = "Base URL for the judges OpenAI-compatible API (llm-gateway)."
  default     = "https://us.api.openai.com/v1"
}
