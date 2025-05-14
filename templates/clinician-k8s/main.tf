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

provider "coder" {}

provider "kubernetes" {
  config_path = null
}

variable "namespace" {
  type        = string
  description = "Target Kubernetes namespace for workspace deployments."
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  repo_map = {
    "completion-service" = "https://github.com/abridgeai/completion-service"
  }

  repo_url = (
    data.coder_parameter.repo_selection.value == "custom"
    ? data.coder_parameter.custom_repo.value
    : lookup(local.repo_map, data.coder_parameter.repo_selection.value, "")
  )

  should_clone = (
    data.coder_parameter.repo_selection.value != "custom"
    || data.coder_parameter.custom_repo.value != ""
  )

  base_image = "us-central1-docker.pkg.dev/abridge-artifact-registry/coder/base:ef839cc"

  home_dir = "/home/vscode"

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

  init_script = <<-EOT
    set -e

    # Install uv
    curl -LsSf https://astral.sh/uv/install.sh | sh
    source ~/.local/bin/env

    # Install required authentication tools for keyring and the GAR backend
    uv tool install keyring --with keyrings.google-artifactregistry-auth


    if [ ! -f ~/.env ]; then
      cat <<EOF > ~/.env
EYES_API_URL=http://eyes-v1-eyes-new.eyes-v1.svc.cluster.local/api
ELMS_API_URL=http://elms-api.elms.svc.cluster.local
ELMS_BASE_URL=http://elms-api.elms.svc.cluster.local
PF_TRACING_SKIP_EXPORTER_SETUP=false
PF_TRACING_SKIP_LOCAL_SETUP=false
PF_DISABLE_TRACING=false
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:23333/v1/traces
PATH="\$HOME/.local/bin:\$PATH"
EOF
      echo "source ~/.env" >> ~/.bashrc
      cat ~/.bashrc >> ~/.profile
      cat ~/.bashrc >> ~/.zshrc
    fi

    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server
    /tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &
  EOT

  metrics = {
    "0_cpu_usage"      = { name = "CPU Usage", script = "coder stat cpu" }
    "1_ram_usage"      = { name = "RAM Usage", script = "coder stat mem" }
    "3_home_disk"      = { name = "Home Disk", script = "coder stat disk --path $HOME" }
    "4_cpu_usage_host" = { name = "CPU Usage (Host)", script = "coder stat cpu --host" }
    "5_mem_usage_host" = { name = "Memory Usage (Host)", script = "coder stat mem --host" }
  }
}

data "coder_parameter" "repo_selection" {
  name         = "repo_selection"
  display_name = "Repository Selection"
  description  = "Choose which repository to clone"
  default      = "completion-service"
  mutable      = true
  order        = 1
  option {
    name  = "Completion Service"
    value = "completion-service"
  }
  option {
    name  = "Custom Repository"
    value = "custom"
  }
}

data "coder_parameter" "custom_repo" {
  name         = "custom_repo"
  display_name = "Custom Repository URL"
  description  = "If you selected 'Custom Repository' above, provide the full Git repository URL"
  default      = ""
  mutable      = true
  type         = "string"
  order        = 2
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "The number of CPU cores"
  default      = "4"
  icon         = "/icon/memory.svg"
  mutable      = true
  order        = 3
  option {
    name  = "4 Cores"
    value = "4"
  }
  option {
    name  = "6 Cores"
    value = "6"
  }
  option {
    name  = "8 Cores"
    value = "8"
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory"
  description  = "The amount of memory in GB"
  default      = "6"
  icon         = "/icon/memory.svg"
  mutable      = true
  order        = 4
  option {
    name  = "6 GB"
    value = "6"
  }
  option {
    name  = "8 GB"
    value = "8"
  }
}

data "coder_parameter" "home_disk_size" {
  name         = "home_disk_size"
  display_name = "Home disk size"
  description  = "The size of the home disk in GB"
  default      = "10"
  type         = "number"
  icon         = "/emojis/1f4be.png"
  mutable      = false
  order        = 5
  validation {
    min = 1
    max = 1000
  }
}

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
      interval     = metadata.key == "6_load_host" ? 60 : 10
      timeout      = 1
    }
  }
}

module "git-clone" {
  count    = data.coder_workspace.me.start_count > 0 && local.should_clone ? 1 : 0
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "1.0.18"
  agent_id = coder_agent.main.id
  url      = local.repo_url
}

resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "code-server"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13337?folder=${local.home_dir}"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 3
    threshold = 10
  }
}

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
      metadata { labels = local.labels }
      spec {
        security_context {
          run_as_user     = 1000
          fs_group        = 1000
          run_as_non_root = true
        }

        container {
          name              = "dev"
          image             = local.base_image
          image_pull_policy = "Always"
          command           = ["sh", "-c", coder_agent.main.init_script]
          security_context { run_as_user = 1000 }
          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }
          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
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

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = kubernetes_deployment.main[0].id

  item {
    key   = "image"
    value = local.base_image
  }

  item {
    key   = "type"
    value = "Kubernetes Pod"
  }
}

resource "coder_metadata" "home_info" {
  resource_id = kubernetes_persistent_volume_claim.home.id

  item {
    key   = "size"
    value = "${data.coder_parameter.home_disk_size.value} GiB"
  }
}
