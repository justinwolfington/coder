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
# VARIABLES
############################
variable "namespace" {
  type        = string
  description = "Target Kubernetes namespace for workspace deployments."
  default     = "coder"
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

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU Cores"
  description  = "The number of CPU cores (between 4-16)"
  default      = "4"
  icon         = "/icon/memory.svg"
  mutable      = true
  order        = 2
  type         = "number"
  validation {
    min = 4
    max = 16
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (GB)"
  description  = "The amount of memory in GB (between 8-64)"
  default      = "8"
  icon         = "/icon/memory.svg"
  mutable      = true
  order        = 3
  type         = "number"
  validation {
    min = 8
    max = 64
  }
}

data "coder_parameter" "home_disk_size" {
  name         = "home_disk_size"
  display_name = "Home disk size (GB)"
  description  = "The size of the home disk in GB (between 16-1024)"
  default      = "16"
  type         = "number"
  icon         = "/icon/folder.svg"
  mutable      = true
  order        = 4
  validation {
    min = 16
    max = 1024
  }
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

  # Phoenix image configuration
  phoenix_image_repo = "us-central1-docker.pkg.dev/abridge-artifact-registry/coder/phoenix"
  phoenix_image_tag  = "latest"
  phoenix_image      = "${local.phoenix_image_repo}:${local.phoenix_image_tag}"

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
  init_script = <<-EOT
    set -e

    export USER_HOME="/home/vscode"
    export BASHRC_FILE="$USER_HOME/.bashrc"
    export ROOT_BASHRC_FILE="/root/.bashrc"

    sudo cp "$ROOT_BASHRC_FILE" "$BASHRC_FILE"
    sudo chown vscode:vscode "$BASHRC_FILE"

    # Install and start code-server
    export CODE_SERVER_DIR="/tmp/code-server"

    if [ ! -f "$CODE_SERVER_DIR/bin/code-server" ]; then
      mkdir -p "$CODE_SERVER_DIR"
      curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix="$CODE_SERVER_DIR" || exit 1
    fi

    # Install VS Code extensions
    $CODE_SERVER_DIR/bin/code-server --install-extension ms-python.python
    $CODE_SERVER_DIR/bin/code-server --install-extension ms-toolsai.jupyter

    $CODE_SERVER_DIR/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &
  EOT

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

# --- Coder Application: Arize Phoenix ---
resource "coder_app" "arize-phoenix" {
  agent_id     = coder_agent.main.id
  slug         = "arize-phoenix"
  display_name = "Arize Phoenix"
  icon         = "/icon/database.svg"
  url          = "http://localhost:6006"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:6006"
    interval  = 10
    threshold = 15
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
        storage = "${data.coder_parameter.home_disk_size.value}Gi"
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

          # Arize Phoenix tracing environment variables
          env {
            name  = "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"
            value = "http://localhost:6006/v1/traces"
          }

          env {
            name  = "PF_TRACING_SKIP_EXPORTER_SETUP"
            value = "true"
          }

          env {
            name  = "PF_TRACING_SKIP_LOCAL_SETUP"
            value = "true"
          }

          env {
            name  = "PF_DISABLE_TRACING"
            value = "false"
          }

          resources {
            requests = {
              cpu    = data.coder_parameter.cpu.value
              memory = "${data.coder_parameter.memory.value}Gi"
            }
            limits = {
              cpu    = data.coder_parameter.cpu.value
              memory = "${data.coder_parameter.memory.value}Gi"
            }
          }

          volume_mount {
            mount_path = local.home_dir
            name       = "home"
            read_only  = false
          }
        }

        # Arize Phoenix sidecar container
        container {
          name              = "arize-phoenix"
          image             = local.phoenix_image
          image_pull_policy = "Always"

          port {
            container_port = 6006
            name           = "phoenix-http"
          }

          port {
            container_port = 4317
            name           = "phoenix-grpc"
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }

          volume_mount {
            mount_path = "/tmp/phoenix"
            name       = "phoenix-data"
            read_only  = false
          }

          # Kubernetes health checks (not Docker health checks)
          liveness_probe {
            http_get {
              path = "/"
              port = 6006
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 6006
            }
            initial_delay_seconds = 10
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
          }
        }

        volume {
          name = "home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.home.metadata[0].name
          }
        }

        # Phoenix data volume
        volume {
          name = "phoenix-data"
          empty_dir {}
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

  item {
    key   = "Image Used"
    value = local.base_image
  }
  item {
    key   = "CPU Cores"
    value = "${data.coder_parameter.cpu.value} vCPU"
  }
  item {
    key   = "Memory"
    value = "${data.coder_parameter.memory.value} GB RAM"
  }
  item {
    key   = "Arize Phoenix"
    value = "Enabled - http://localhost:6006"
  }
}

resource "coder_metadata" "home_pvc_info" {
  resource_id = kubernetes_persistent_volume_claim.home.id

  item {
    key   = "Home Volume Size"
    value = "${data.coder_parameter.home_disk_size.value} GB"
  }
  item {
    key   = "Namespace"
    value = var.namespace
  }
}

############################
# OUTPUTS
############################
output "workspace_name" {
  description = "Name of the created workspace"
  value       = data.coder_workspace.me.name
}

output "workspace_owner" {
  description = "Owner of the workspace"
  value       = data.coder_workspace_owner.me.name
}

output "cpu_cores" {
  description = "Number of CPU cores allocated"
  value       = data.coder_parameter.cpu.value
}

output "memory_gb" {
  description = "Amount of memory allocated in GB"
  value       = data.coder_parameter.memory.value
}

output "home_disk_size" {
  description = "Size of home disk in GB"
  value       = data.coder_parameter.home_disk_size.value
}

output "repository_url" {
  description = "Repository URL being used"
  value       = data.coder_parameter.repository_url.value
}

output "namespace" {
  description = "Kubernetes namespace where workspace is deployed"
  value       = var.namespace
}
