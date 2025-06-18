terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

############################
# PROVIDERS
############################
provider "coder" {}

provider "kubernetes" {
  config_path = null
}

############################
# SHARED MODULES
############################
module "resources" {
  source = "git::https://github.com/abridgeai/coder.git//modules/resources?ref=shubh/add-user-quotas"
}

module "git_utilities" {
  source = "git::https://github.com/abridgeai/coder.git//modules/utilities/git?ref=shubh/add-user-quotas"
  start_count = data.coder_workspace.me.start_count
  agent_id = coder_agent.main.id
  repo_url = data.coder_parameter.repository_url.value
  should_clone = data.coder_parameter.repository_url.value != ""
}

module "ide_utilities" {
  source = "git::https://github.com/abridgeai/coder.git//modules/utilities/ide?ref=shubh/add-user-quotas"
  start_count = data.coder_workspace.me.start_count
  agent_id = coder_agent.main.id
  user_name = data.coder_workspace_owner.me.name
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
  default      = "https://github.com/abridgeai/completion-service"
  mutable      = true
  order        = 1
  type         = "string"
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
  init_script = templatefile("${path.module}/startup.tftpl", {})

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

# # --- Coder Application: code-server ---
# resource "coder_app" "code-server" {
#   agent_id     = coder_agent.main.id
#   slug         = "code-server"
#   display_name = "code-server"
#   icon         = "/icon/code.svg"
#   url          = "http://localhost:13337?folder=${local.repo_dir}"
#   subdomain    = false
#   share        = "owner"

#   healthcheck {
#     url       = "http://localhost:13337/healthz"
#     interval  = 3
#     threshold = 10
#   }
# }

############################
# INFRASTRUCTURE RESOURCES
############################
# --- Kubernetes Resources ---

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
        storage = "${module.resources.home_disk_size.value}Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "main" {
  count            = data.coder_workspace.me.start_count
  depends_on       = [kubernetes_persistent_volume_claim.home]
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
        labels      = local.labels
        annotations = local.annotations
      }
      spec {
        security_context {
          run_as_user     = "1000"
          fs_group        = "1000"
          run_as_non_root = true
        }

        container {
          name              = "dev"
          image             = local.base_image
          image_pull_policy = "Always"
          command           = ["sh", "-c", coder_agent.main.init_script]

          security_context {
            run_as_user = "1000"
          }

          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }

          resources {
            requests = {
              cpu    = "${module.resources.cpu.value}"
              memory = "${module.resources.memory.value}Gi"
            }
            limits = {
              cpu    = "${module.resources.cpu.value}"
              memory = "${module.resources.memory.value}Gi"
            }
          }

          volume_mount {
            mount_path = local.home_dir
            name       = "home"
            read_only  = false
          }
        }

        volume {
          name = "home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.home.metadata[0].name
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
  daily_cost = (module.resources.cpu_cost_per_core * module.resources.cpu.value +
  module.resources.ram_cost_per_gb * module.resources.memory.value)

  item {
    key   = "Image Used"
    value = local.base_image
  }
  item {
    key   = "CPU Cores"
    value = "${module.resources.cpu.value} vCPU"
  }
  item {
    key   = "Memory"
    value = "${module.resources.memory.value} GB RAM"
  }
}

resource "coder_metadata" "home_pvc_info" {
  resource_id = kubernetes_persistent_volume_claim.home.id

  item {
    key   = "Home Volume Size"
    value = "${module.resources.home_disk_size.value} GB"
  }
  item {
    key   = "Namespace"
    value = var.namespace
  }
}
