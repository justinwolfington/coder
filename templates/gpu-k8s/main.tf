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
# DATA SOURCES
############################
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

############################
# SHARED MODULES
############################
module "cpu_resources" {
  source = "git::https://github.com/abridgeai/coder.git//modules/resources/cpu?ref=v1.9.0"
}

module "gpu_resources" {
  source = "git::https://github.com/abridgeai/coder.git//modules/resources/gpu?ref=v1.9.0"
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

module "utd_bucket" {
  source                 = "git::https://github.com/abridgeai/coder.git//modules/utilities/gcs-bucket?ref=v1.9.0"
  environment            = var.environment
  supported_environments = ["production", "staging", "development"]
  workspace_owner_groups = data.coder_workspace_owner.me.groups
  required_group         = "UTDACCESS"
  bucket_name            = lookup({ production = "abridge-client-prod-wk-secure-bucket", staging = "abridge-client-staging-wk-secure-bucket", development = "client-dev-e301d-wk-secure-bucket" }, var.environment, "")
  mount_path             = "/utddata"
  mount_options          = "implicit-dirs,only-dir=decrypt"
  parameter_name         = "utd_bucket_access"
  display_name           = "UTD Bucket Mount"
  description            = "Enable to mount the UTD secure bucket at /utddata"
  parameter_order        = 10
}

############################
# PARAMETERS
############################
data "coder_parameter" "repository_url" {
  name         = "repository_url"
  display_name = "Repository URL"
  description  = "GitHub repository URL (leave empty for no repository)"
  default      = "https://github.com/abridgeai/bilrost"
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

data "coder_parameter" "gpu_accelerator" {
  name         = "gpu_accelerator"
  display_name = "GPU Accelerator Type"
  description  = "Choose GPU type. Leave empty for CPU-only."
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
  option {
    name  = "NVIDIA RTX PRO 6000"
    value = "nvidia-rtx-pro-6000"
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

  # UTD bucket access configuration
  utd_bucket_enabled = module.utd_bucket.bucket_enabled

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
  init_script = templatefile("${path.module}/startup.tftpl", {
    should_clone = local.should_clone
    repo_url     = local.repo_url
  })
  logger_script = module.logger.logger_script

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

  compute_class_map = {
    ""                    = "cpu-coder-class"
    "nvidia-l4"           = "l4-class"
    "nvidia-h100-80gb"    = "h100-coder-class"
    "nvidia-rtx-pro-6000" = "rtx6000-class"
  }

  node_selector = {
    "cloud.google.com/compute-class" = local.compute_class_map[data.coder_parameter.gpu_accelerator.value]
  }

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
# INFRASTRUCTURE RESOURCES
############################
# # --- Coder Application: code-server ---
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
        storage = "${module.cpu_resources.home_disk_size.value}Gi"
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
        labels = local.labels
        annotations = merge(local.annotations, {
          "sidecar.istio.io/inject"                          = "true"
          "gke-gcsfuse/volumes"                              = module.utd_bucket.gcsfuse_annotation
          "traffic.sidecar.istio.io/excludeOutboundIPRanges" = module.utd_bucket.istio_ip_exclusion
          "proxy.istio.io/config" = jsonencode({
            holdApplicationUntilProxyStarts = true
          })
        })
      }
      spec {
        service_account_name = local.utd_bucket_enabled ? "coder" : null
        node_selector        = local.node_selector

        security_context {
          # Run as root for unrestricted access
          run_as_user     = 0
          fs_group        = 0
          run_as_non_root = false
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
            # Run as root
            run_as_user                = 0
            allow_privilege_escalation = true
            read_only_root_filesystem  = false
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
            requests = merge(
              {
                cpu    = module.cpu_resources.cpu.value
                memory = "${module.cpu_resources.memory.value}Gi"
              },
              local.gpu_requests
            )
            limits = merge(
              {
                cpu    = module.cpu_resources.cpu.value
                memory = "${module.cpu_resources.memory.value}Gi"
              },
              local.gpu_limits
            )
          }

          volume_mount {
            mount_path = local.home_dir
            name       = "home"
            read_only  = false
          }

          # Conditionally mount UTD bucket for authorized users
          dynamic "volume_mount" {
            for_each = module.utd_bucket.volume_mount != null ? [module.utd_bucket.volume_mount] : []
            content {
              mount_path = volume_mount.value.mount_path
              name       = volume_mount.value.name
              read_only  = volume_mount.value.read_only
            }
          }
        }

        volume {
          name = "home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.home.metadata[0].name
          }
        }

        # Conditionally add UTD bucket volume for authorized users
        dynamic "volume" {
          for_each = module.utd_bucket.volume != null ? [module.utd_bucket.volume] : []
          content {
            name = volume.value.name
            csi {
              driver            = volume.value.csi.driver
              volume_attributes = volume.value.csi.volume_attributes
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
  module.cpu_resources.ram_cost_per_gb * module.cpu_resources.memory.value) + lookup(module.gpu_resources.gpu_cost_per_unit, data.coder_parameter.gpu_accelerator.value, 0) * data.coder_parameter.gpu_count.value

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
  item {
    key   = "GPU Type"
    value = data.coder_parameter.gpu_accelerator.value != "" ? data.coder_parameter.gpu_accelerator.value : "None"
  }
  item {
    key   = "GPU Count"
    value = data.coder_parameter.gpu_accelerator.value != "" ? data.coder_parameter.gpu_count.value : "N/A"
  }
  item {
    key   = "UTD Bucket Access"
    value = local.utd_bucket_enabled ? "Enabled (/utddata)" : "Disabled"
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
}
