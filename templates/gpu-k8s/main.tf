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
# DATA SOURCES
############################
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

############################
# SHARED MODULES
############################
module "resources" {
  source = "git::https://github.com/abridgeai/coder.git//modules/resources?ref=shubh/add-user-quotas"
}

module "gpu_resources" {
  source = "git::https://github.com/abridgeai/coder.git//modules/gpu_resources?ref=shubh/add-user-quotas"
}

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

data "coder_parameter" "gpu_accelerator" {
  name         = "gpu_accelerator"
  display_name = "GPU Accelerator Type"
  description  = "Choose GPU type. Must match 'cloud.google.com/gke-accelerator' label values on GKE nodes. Leave empty for CPU-only."
  default      = ""
  mutable      = true
  order        = 5
  icon         = "/icon/container.svg"
  type         = "string"
  option {
    name  = "No GPU"
    value = ""
  }
  option {
    name  = "NVIDIA L4"
    value = "nvidia-l4"
  }
  option {
    name  = "NVIDIA H100 (80GB)"
    value = "nvidia-h100-80gb"
  }
}

data "coder_parameter" "gpu_count" {
  name         = "gpu_count"
  display_name = "Number of GPUs"
  description  = "Number of GPUs to allocate to the workspace. Only applicable if a GPU Accelerator Type is selected."
  default      = "1"
  mutable      = true
  order        = 6
  type         = "number"
  icon         = "/icon/container.svg"
  validation {
    min = 1
    max = 8 # Adjust max as per typical node limits / user needs
  }
}

############################
# LOCALS
############################
locals {
  # Directory configuration
  home_dir = "/root"

  # Image and environment configuration
  base_image_repo = "us-central1-docker.pkg.dev/abridge-artifact-registry/coder/gpu"
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
    "2_gpu_usage"      = { name = "GPU Usage", script = "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits" }
    "3_home_disk"      = { name = "Home Disk", script = "coder stat disk --path $HOME" }
    "4_cpu_usage_host" = { name = "CPU Usage (Host)", script = "coder stat cpu --host" }
    "5_mem_usage_host" = { name = "Memory Usage (Host)", script = "coder stat mem --host" }
    "6_load_host"      = { name = "Load Average (Host)", script = "echo \"`cat /proc/loadavg | awk '{ print $1 }'` `nproc`\" | awk '{ printf \"%0.2f\", $1/$2 }'" }
  }

  gpu_node_selector = data.coder_parameter.gpu_accelerator.value != "" ? {
    "cloud.google.com/gke-accelerator" = data.coder_parameter.gpu_accelerator.value
  } : {}

  # Conditional GPU resource requests and limits
  gpu_requests = data.coder_parameter.gpu_accelerator.value != "" ? {
    "nvidia.com/gpu" = data.coder_parameter.gpu_count.value
  } : {}

  gpu_limits = data.coder_parameter.gpu_accelerator.value != "" ? {
    "nvidia.com/gpu" = data.coder_parameter.gpu_count.value # Assuming limits are same as requests for GPUs
  } : {}

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
# IDE MODULES
############################
# --- Git Repository Cloning ---
module "git-clone" {
  count    = data.coder_workspace.me.start_count > 0 && local.should_clone ? 1 : 0
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "1.0.18"
  agent_id = coder_agent.main.id
  url      = local.repo_url
}

# --- Cursor IDE Integration ---
module "cursor" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "1.1.0"
  agent_id = coder_agent.main.id
}

# --- Git Configuration ---
module "git-config" {
  source                = "registry.coder.com/coder/git-config/coder"
  version               = "1.0.15"
  agent_id              = coder_agent.main.id
  allow_username_change = false
  allow_email_change    = false
}

# --- JetBrains Gateway ---
module "jetbrains_gateway" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/jetbrains-gateway/coder"
  version        = "1.2.0"
  agent_id       = coder_agent.main.id
  folder         = local.home_dir
  jetbrains_ides = ["PY"]
  default        = "PY"
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
        node_selector = data.coder_parameter.gpu_accelerator.value != "" ? local.gpu_node_selector : null

        security_context {
          # Run as root for unrestricted access
          run_as_user     = 0
          fs_group        = 0
          run_as_non_root = false
        }

        container {
          name              = "dev"
          image             = local.base_image
          image_pull_policy = "Always"
          command           = ["sh", "-c", coder_agent.main.init_script]

          security_context {
            # Run as root
            run_as_user                = 0
            allow_privilege_escalation = true
            read_only_root_filesystem  = false
          }

          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }

          resources {
            requests = merge(
              {
                cpu    = module.resources.cpu.value
                memory = "${module.resources.memory.value}Gi"
              },
              local.gpu_requests
            )
            limits = merge(
              {
                cpu    = module.resources.cpu.value
                memory = "${module.resources.memory.value}Gi"
              },
              local.gpu_limits
            )
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
  module.resources.ram_cost_per_gb * module.resources.memory.value) + lookup(module.gpu_resources.gpu_cost_per_unit, data.coder_parameter.gpu_accelerator.value, 0) * data.coder_parameter.gpu_count.value

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
  item {
    key   = "GPU Type"
    value = data.coder_parameter.gpu_accelerator.value != "" ? data.coder_parameter.gpu_accelerator.value : "None"
  }
  item {
    key   = "GPU Count"
    value = data.coder_parameter.gpu_accelerator.value != "" ? data.coder_parameter.gpu_count.value : "N/A"
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
