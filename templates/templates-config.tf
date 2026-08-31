locals {
  # Dormancy runs off last_used_at, not compute, so an unattended job still goes
  # dormant. Autodelete is a no-op unless time_til_dormant_ms is set too.
  retention = {
    time_til_dormant_ms            = 1814400000 # 21d idle -> dormant
    time_til_dormant_autodelete_ms = 604800000  # 7d dormant -> deleted
  }

  # PHI holds patient data: 11 days from last connection instead of 28.
  # allow_user_auto_stop=false pins default_ttl_ms on; without it a user can
  # null their ttl and run forever, which is how one PHI workspace reached 318d.
  phi_retention = {
    time_til_dormant_ms            = 604800000 # 7d idle -> dormant
    time_til_dormant_autodelete_ms = 345600000 # 4d dormant -> deleted
    default_ttl_ms                 = 259200000 # 72h, overrides the 48h GPU default
    allow_user_auto_stop           = false
  }

  # Stops workspaces stuck in the failed state. Does not retry a failed delete
  # transition, so leaked VMs still need the orphan sweep.
  failure_cleanup = {
    failure_ttl_ms = 7200000 # 2h
  }

  gpu_timings = merge({
    activity_bump_ms = 86400000  # 1d
    default_ttl_ms   = 172800000 # 2d auto-stop
  }, local.retention, local.failure_cleanup)

  phi_timings      = merge(local.gpu_timings, local.phi_retention)
  cpu_timings      = merge(local.retention, local.failure_cleanup)
  standard_timings = merge(local.retention, local.failure_cleanup)

  templates = {
    # Named for abridgeai/completion-service, archived 2026-05-15; work moved to bilrost.
    "k8s-completion-service" = merge({
      display_name        = "Kubernetes Completion Service with Phoenix"
      description         = "Kubernetes workspace with Arize Phoenix. Includes completion service, uv package manager, and gcloud CLI."
      icon                = "/emojis/1f33c.png"
      directory           = "./clinician-k8s"
      environments        = ["development", "staging", "production"]
      deprecation_message = "This template is deprecated and will be removed. Use cpu-k8s for CPU work or phi-gpu-k8s for GPU work. Existing workspaces keep running, but new ones cannot be created from this template."
    }, local.standard_timings)

    "cpu-k8s" = merge({
      display_name = "Kubernetes CPU Workspace"
      description  = "Lightweight Kubernetes workspace for CPU-intensive tasks with development tools."
      icon         = "/emojis/1f4bb.png"
      directory    = "./cpu-k8s"
      environments = ["development", "staging", "production"]
    }, local.cpu_timings)

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
    }, local.phi_timings)
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
