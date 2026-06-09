terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "2.18.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
  }
}

############################
# PROVIDERS
############################
provider "coder" {
  url = var.coder_url
}

provider "kubernetes" {
  config_path = null
}

############################
# SHARED MODULES
############################
module "cpu_resources" {
  source = "git::https://github.com/abridgeai/coder.git//modules/resources/cpu?ref=v1.9.0"
}

module "git_utilities" {
  source       = "git::https://github.com/abridgeai/coder.git//modules/utilities/git?ref=v1.9.0"
  start_count  = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  repo_url     = data.coder_parameter.repository_url.value
  should_clone = data.coder_parameter.repository_url.value != ""
}

module "ide_utilities" {
  source           = "git::https://github.com/abridgeai/coder.git//modules/utilities/ide?ref=v1.9.0"
  start_count      = data.coder_workspace.me.start_count
  agent_id         = coder_agent.main.id
  user_name        = data.coder_workspace_owner.me.name
  enable_jetbrains = data.coder_parameter.enable_jetbrains.value
}

module "logger" {
  source = "git::https://github.com/abridgeai/coder.git//modules/logger?ref=v1.9.0"
}

module "dotfiles" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dotfiles/coder"
  version  = "1.4.2"
  agent_id = coder_agent.main.id
}

############################
# DATA SOURCES
############################
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}


############################
# PARAMETERS
############################
data "coder_parameter" "repository_url" {
  name         = "repository_url"
  display_name = "Repository URL"
  description  = "GitHub repository URL (leave empty for no repository)"
  default      = "https://github.com/abridgeai/ml-training-utils"
  mutable      = true
  order        = 1
  type         = "string"
}

data "coder_parameter" "enable_jetbrains" {
  name         = "enable_jetbrains"
  display_name = "Enable JetBrains Gateway"
  description  = "Enable JetBrains Gateway IDE access"
  type         = "bool"
  default      = false
  mutable      = true
}

############################
# LOCALS
############################
locals {
  # Directory configuration
  home_dir = "/home/vscode"

  # Image and environment configuration
  base_image_repo = "us-central1-docker.pkg.dev/abridge-artifact-registry/coder/base"
  base_image_tag  = "latest"
  base_image      = "${local.base_image_repo}:${local.base_image_tag}"


  # Repository configuration - simplified
  repo_url     = data.coder_parameter.repository_url.value
  should_clone = local.repo_url != ""

  # Extract repo name from URL for directory naming
  repo_name = local.should_clone ? regex("([^/]+?)(\\.git)?$", local.repo_url)[0] : ""
  repo_dir  = local.should_clone ? "${local.home_dir}/${local.repo_name}" : local.home_dir

  # Kubernetes metadata
  labels = {
    "app.kubernetes.io/name"     = "coder-workspace"
    "app.kubernetes.io/instance" = "coder-workspace-${data.coder_workspace.me.id}"
    "app.kubernetes.io/part-of"  = "coder"
    "com.coder.resource"         = "true"
    "com.coder.workspace.id"     = data.coder_workspace.me.id
    "com.coder.workspace.name"   = data.coder_workspace.me.name
    "com.coder.user.id"          = data.coder_workspace_owner.me.id
    "com.coder.user.username"    = data.coder_workspace_owner.me.name
  }

  annotations = {
    "com.coder.user.email" = data.coder_workspace_owner.me.email
  }

  # Startup script for the workspace
  init_script = templatefile("${path.module}/startup.tftpl", {
    should_clone = local.should_clone
    repo_url     = local.repo_url
  })
  logger_script = module.logger.logger_script

  # Metrics for workspace monitoring
  metrics = {
    "0_cpu_usage"      = { name = "CPU Usage", script = "coder stat cpu" }
    "1_ram_usage"      = { name = "RAM Usage", script = "coder stat mem" }
    "3_home_disk"      = { name = "Home Disk", script = "coder stat disk --path $HOME" }
    "4_cpu_usage_host" = { name = "CPU Usage (Host)", script = "coder stat cpu --host" }
    "5_mem_usage_host" = { name = "Memory Usage (Host)", script = "coder stat mem --host" }
    "6_load_host"      = { name = "Load Average (Host)", script = "echo \"`cat /proc/loadavg | awk '{ print $1 }'` `nproc`\" | awk '{ printf \"%0.2f\", $1/$2 }'" }
  }
}

############################
# CODER AGENT
############################
resource "coder_agent" "main" {
  os             = "linux"
  arch           = "amd64"
  startup_script = local.init_script

  dynamic "metadata" {
    for_each = local.metrics
    content {
      display_name = metadata.value.name
      key          = metadata.key
      script       = metadata.value.script
      interval     = 15
      timeout      = 5
    }
  }
}
############################
# INFRASTRUCTURE RESOURCES
############################

# --- Coder Application: code-server ---
resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "code-server"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13337?folder=${local.repo_dir}"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 3
    threshold = 10
  }
}


# --- Kubernetes Resources ---

# Reference to existing shared PVCs created by skypilot-api-server
data "kubernetes_persistent_volume_claim" "data_pvc" {
  metadata {
    name      = "data-pvc"
    namespace = var.namespace
  }
}

data "kubernetes_persistent_volume_claim" "shared_home_pvc" {
  metadata {
    name      = "home-pvc"
    namespace = var.namespace
  }
}

# Workspace-specific home PVC (keep existing behavior)
resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name        = "coder-${data.coder_workspace.me.id}-home"
    namespace   = var.namespace
    labels      = local.labels
    annotations = local.annotations
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${module.cpu_resources.home_disk_size.value}Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "main" {
  count            = data.coder_workspace.me.start_count
  depends_on       = [kubernetes_persistent_volume_claim.home, data.kubernetes_persistent_volume_claim.data_pvc, data.kubernetes_persistent_volume_claim.shared_home_pvc]
  wait_for_rollout = false

  metadata {
    name        = "coder-${data.coder_workspace.me.id}"
    namespace   = var.namespace
    labels      = local.labels
    annotations = local.annotations
  }

  spec {
    replicas = 1
    selector {
      match_labels = local.labels
    }
    strategy { type = "Recreate" }

    template {
      metadata {
        labels = local.labels
        annotations = merge(local.annotations, {
          "sidecar.istio.io/inject" = "false"
        })
      }
      spec {
        security_context {
          run_as_user     = "1000"
          fs_group        = "1000"
          run_as_non_root = true
        }

        container {
          name              = "exectrace"
          image             = module.logger.exectrace_image
          image_pull_policy = "Always"
          command = [
            "/opt/exectrace",
            "--init-address", "127.0.0.1:56123",
            "--label", "workspace_id=${data.coder_workspace.me.id}",
            "--label", "workspace_name=${data.coder_workspace.me.name}",
            "--label", "user_id=${data.coder_workspace_owner.me.id}",
            "--label", "username=${data.coder_workspace_owner.me.name}",
            "--label", "user_email=${data.coder_workspace_owner.me.email}",
          ]
          security_context {
            // exectrace must be started as root so it can attach probes into the
            // kernel to record process events with high throughput.
            run_as_user  = "0"
            run_as_group = "0"
            // exectrace requires a privileged container so it can control mounts
            // and perform privileged syscalls against the host kernel to attach
            // probes.
            privileged = true
          }
        }

        container {
          name              = "dev"
          image             = local.base_image
          image_pull_policy = "Always"
          command           = ["sh", "-c", "${local.logger_script}\n\n${coder_agent.main.init_script}"]

          security_context {
            run_as_user = "1000"
          }

          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }

          env {
            name  = "CODER_AGENT_SUBSYSTEM"
            value = "exectrace"
          }

          # Pass GitHub token to container so startup checks and git operations can use it
          env {
            name  = "GITHUB_TOKEN"
            value = module.git_utilities.github_token
          }

          resources {
            requests = {
              cpu    = "${module.cpu_resources.cpu.value}"
              memory = "${module.cpu_resources.memory.value}Gi"
            }
            limits = {
              cpu    = "${module.cpu_resources.cpu.value}"
              memory = "${module.cpu_resources.memory.value}Gi"
            }
          }

          volume_mount {
            mount_path = local.home_dir
            name       = "home"
            read_only  = false
          }

          volume_mount {
            mount_path = "/mnt/data"
            name       = "data"
            read_only  = false
          }

          volume_mount {
            mount_path = "/mnt/home"
            name       = "shared-home"
            read_only  = false
          }
        }

        volume {
          name = "home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.home.metadata[0].name
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = "data-pvc"
          }
        }

        volume {
          name = "shared-home"
          persistent_volume_claim {
            claim_name = "home-pvc"
          }
        }

        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 1
              pod_affinity_term {
                topology_key = "kubernetes.io/hostname"
                label_selector {
                  match_expressions {
                    key      = "app.kubernetes.io/name"
                    operator = "In"
                    values   = ["coder-workspace"]
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

############################
# METADATA
############################
# --- Coder Metadata (for UI display) ---
resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = kubernetes_deployment.main[0].id
  daily_cost = (module.cpu_resources.cpu_cost_per_core * module.cpu_resources.cpu.value +
  module.cpu_resources.ram_cost_per_gb * module.cpu_resources.memory.value)

  item {
    key   = "Image Used"
    value = local.base_image
  }
  item {
    key   = "CPU Cores"
    value = "${module.cpu_resources.cpu.value} vCPU"
  }
  item {
    key   = "Memory"
    value = "${module.cpu_resources.memory.value} GB RAM"
  }
}

resource "coder_metadata" "home_pvc_info" {
  resource_id = kubernetes_persistent_volume_claim.home.id

  item {
    key   = "Home Volume Size"
    value = "${module.cpu_resources.home_disk_size.value} GB"
  }
  item {
    key   = "Namespace"
    value = var.namespace
  }
  item {
    key   = "Shared Home PVC"
    value = "home-pvc (mounted at /mnt/home)"
  }
  item {
    key   = "Shared Data PVC"
    value = "data-pvc (mounted at /mnt/data)"
  }
}
