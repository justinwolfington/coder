locals {
  # Template timing parameters (all in milliseconds):
  # - activity_bump_ms: How much to extend workspace deadline when activity detected
  # - failure_ttl_ms: How long to keep failed workspaces before cleanup
  # - default_ttl_ms: Default time-to-live for workspaces

  # GPU-specific timing configuration to prevent abuse while allowing productive work
  gpu_timings = {
    activity_bump_ms = 86400000  # 1 day (extend workspace when active)
    default_ttl_ms   = 172800000 # 2 days (auto-stop)
    failure_ttl_ms   = 7200000   # 2 hours (cleanup failed workspaces)
  }

  # Standard timing configuration for non-GPU templates (disabled)
  standard_timings = {}

  templates = {
    "k8s-completion-service" = merge({
      display_name = "Kubernetes Completion Service with Phoenix"
      description  = "Kubernetes workspace with Arize Phoenix. Includes completion service, uv package manager, and gcloud CLI."
      icon         = "/emojis/1f33c.png"
      directory    = "./clinician-k8s"
      environments = ["development", "staging", "production"]
    }, local.standard_timings)

    "cpu-k8s" = merge({
      display_name = "Kubernetes CPU Workspace"
      description  = "Lightweight Kubernetes workspace for CPU-intensive tasks with development tools."
      icon         = "/emojis/1f4bb.png"
      directory    = "./cpu-k8s"
      environments = ["development", "staging", "production"]
    }, local.standard_timings)

    "gpu-k8s" = merge({
      display_name = "Kubernetes GPU Workspace"
      description  = "Kubernetes workspace with GPU support for ML Scientists (no docker container support)."
      icon         = "/emojis/1f35f.png"
      directory    = "./gpu-k8s"
      environments = ["development", "staging", "production"]
    }, local.gpu_timings)

    "gcp-vm-modular" = merge({
      display_name = "GCP VM Workspace with Docker"
      description  = "GCP VM workspace with GPU support and Docker. Features ML development tools for ML Ops and Scientists."
      icon         = "/icon/gcp.png"
      directory    = "./gcp-vm-modular"
      environments = ["development", "staging"]
    }, local.gpu_timings)

    "phi-gpu-k8s" = merge({
      display_name = "Kubernetes PHI Workspace"
      description  = "Secure Kubernetes workspace with GPU support and enhanced security for PHI compliance."
      icon         = "/emojis/1f510.png"
      directory    = "./phi-gpu-k8s"
      environments = ["development", "production"]
    }, local.gpu_timings)

    "skypilot-k8s" = merge({
      display_name = "SkyPilot K8s"
      description  = "Kubernetes development workspace with SkyPilot integration."
      icon         = "/icon/pytorch.svg"
      directory    = "./skypilot-k8s"
      environments = ["development", "staging", "production"]
    }, local.standard_timings)
  }

  # Filter templates based on target environment
  active_templates = {
    for name, config in local.templates :
    name => config
    if contains(config.environments, var.environment)
  }

  # Support filtering by specific template name
  filtered_templates = {
    for name, config in local.active_templates :
    name => config
    if var.template_name == "" || name == var.template_name
  }
}

# Variables for runtime configuration
variable "environment" {
  description = "Target environment (development, staging, production)"
  type        = string

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production"
  }
}

variable "template_name" {
  description = "Specific template name to deploy (optional, deploys all if empty)"
  type        = string
  default     = ""
}

variable "commit_sha" {
  description = "Git commit SHA for version naming"
  type        = string
}

variable "coder_url" {
  description = "Coder access URL"
  type        = string
}

variable "coder_token" {
  description = "Coder session token"
  type        = string
  sensitive   = true
}

variable "anthropic_api_key" {
  description = "Anthropic API key for Claude Code (uses API billing mode, optional)"
  type        = string
  sensitive   = true
  default     = ""
}
