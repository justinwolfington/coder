locals {
  # Template timing parameters (all in milliseconds):
  # - activity_bump_ms: How much to extend workspace deadline when activity detected
  # - failure_ttl_ms: How long to keep failed workspaces before cleanup
  # - default_ttl_ms: Default time-to-live for workspaces
  # - time_til_dormant_ms: Idle time before a workspace is stopped and marked dormant
  # - time_til_dormant_autodelete_ms: Dormant time before the workspace is deleted
  #
  # Dormancy is measured from last_used_at, which tracks user connections rather than
  # compute. A workspace running an unattended job nobody connects to will go dormant.
  # Setting autodelete without time_til_dormant_ms is a no-op: isEligibleForDelete
  # requires DormantAt, which only isEligibleForDormantStop sets.
  # 21 days idle -> stopped + dormant, 7 more -> deleted. 28 days from last
  # connection.
  #
  # The non-PHI idle distribution has no natural gap to cut at - it runs
  # continuously from 0d out past 250d - so the threshold is a judgement call
  # rather than something the data picks for us. 21d leaves three weeks before
  # a workspace is touched, which covers a normal holiday, then only 7 days of
  # dormancy before deletion.
  retention = {
    time_til_dormant_ms            = 1814400000 # 21 days idle -> stopped + dormant
    time_til_dormant_autodelete_ms = 604800000  # 7 days dormant -> deleted
  }

  # PHI workspaces hold real patient data, so they get a much shorter window:
  # 7 days idle -> dormant, 7 more -> deleted. 14 days from last connection
  # instead of 44.
  #
  # Deliberately aggressive. Measured against the 32 prod PHI workspaces, a 7d
  # threshold catches 21 where 14d catches 15 and 30d catches 14 - the extra 6
  # sit at 7-15 days idle, so this will reach workspaces someone used last week.
  # That is the intended trade: PHI should not sit unattended, and a stopped
  # workspace is recoverable for 7 days before anything is destroyed.
  #
  # Consequence worth knowing: two weeks away without touching the workspace
  # means deletion. Coder emails the owner at both the dormant and the pending
  # deletion step, but someone on leave may not act on either.
  phi_retention = {
    time_til_dormant_ms            = 604800000 # 7 days idle -> stopped + dormant
    time_til_dormant_autodelete_ms = 604800000 # 7 days dormant -> deleted
  }

  # GPU-specific timing configuration to prevent abuse while allowing productive work
  gpu_timings = merge({
    activity_bump_ms = 86400000  # 1 day (extend workspace when active)
    default_ttl_ms   = 172800000 # 2 days (auto-stop)
    failure_ttl_ms   = 7200000   # 2 hours (cleanup failed workspaces)
  }, local.retention)

  # Same compute guardrails as GPU workspaces, but the shorter PHI window.
  phi_timings = merge(local.gpu_timings, local.phi_retention)

  # Retention only: CPU workspaces are cheap to leave running, so no auto-stop,
  # but they should not accumulate home volumes indefinitely.
  cpu_timings = local.retention

  # Non-GPU templates: no auto-stop or failure cleanup, but the same retention
  # as everything else. These were previously exempt entirely, which left 45
  # idle workspaces (27 of them running) outside the policy - k8s-completion-
  # service alone accounts for 43 of those and is the largest single block of
  # reclaimable compute in the fleet.
  standard_timings = local.retention

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
      environments = ["development", "staging", "production"]
    }, local.gpu_timings)

    "phi-gpu-k8s" = merge({
      display_name = "Kubernetes PHI Workspace"
      description  = "Secure Kubernetes workspace with GPU support and enhanced security for PHI compliance."
      icon         = "/emojis/1f510.png"
      directory    = "./phi-gpu-k8s"
      environments = ["development", "production"]
    }, local.phi_timings)

    "soap-dashboard-k8s" = merge({
      display_name = "SOAP Dashboard"
      description  = "Development workspace for SOAP Dashboard with Claude Code. Pre-configured for PMs to vibe code."
      icon         = "/emojis/1f4cb.png"
      directory    = "./soap-dashboard-k8s"
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
