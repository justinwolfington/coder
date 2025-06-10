terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    google = {
      source = "hashicorp/google"
    }
  }
}

############################
# PROVIDERS
############################
provider "coder" {}
provider "google" {
  project = local.env_config.project_id
  zone    = var.zone
}

############################
# DATA SOURCES
############################
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

############################
# PARAMETERS
############################
data "coder_parameter" "gpu_type" {
  name         = "gpu_type"
  display_name = "GPU Configuration"
  description  = "Select GPU setup"
  type         = "string"
  default      = "none"
  mutable      = true

  option {
    name  = "No GPU"
    value = "none"
  }
  option {
    name  = "NVIDIA L4 (2x)"
    value = "nvidia-l4-2x"
  }
  option {
    name  = "NVIDIA H100 80GB (8x)"
    value = "nvidia-h100-80gb"
  }
}

data "coder_parameter" "dl_image" {
  name         = "dl_image"
  display_name = "Deep Learning Image"
  description  = "Select deep learning platform image"
  type         = "string"
  default      = "pytorch-latest-gpu"
  mutable      = true

  option {
    name  = "PyTorch Latest GPU"
    value = "pytorch-latest-gpu"
  }
  option {
    name  = "PyTorch Latest CPU"
    value = "pytorch-latest-cpu"
  }
  option {
    name  = "TensorFlow Latest GPU"
    value = "tf-latest-gpu"
  }
  option {
    name  = "TensorFlow Latest CPU"
    value = "tf-latest-cpu"
  }
  option {
    name  = "Common Framework GPU"
    value = "common-gpu"
  }
  option {
    name  = "Common Framework CPU"
    value = "common-cpu"
  }
  option {
    name  = "Ubuntu 22.04 LTS"
    value = "ubuntu-2204"
  }
}

data "coder_parameter" "disk_size" {
  name         = "disk_size"
  display_name = "Boot Disk Size (GB)"
  description  = "Size of the boot disk in GB"
  type         = "number"
  default      = 256
  mutable      = true

  validation {
    min = 50
    max = 2000
  }
}

data "coder_parameter" "environment" {
  name         = "environment"
  display_name = "Environment"
  description  = "Select deployment environment"
  type         = "string"
  default      = "development"
  mutable      = false

  option {
    name  = "Development"
    value = "development"
  }
  option {
    name  = "Staging"
    value = "staging"
  }
  option {
    name  = "Production"
    value = "production"
  }
}

############################
# LOCALS
############################
locals {
  # Environment-specific configurations
  environment_configs = {
    "development" = {
      project_id            = "client-dev-e301d"
      service_account_email = "467615904598-compute@developer.gserviceaccount.com"
      network               = "development-vpc"
      subnetwork            = "development-ml"
    }
    "staging" = {
      project_id            = "abridge-client-staging"
      service_account_email = "146004356782-compute@abridge-client-staging.iam.gserviceaccount.com"
      network               = "staging-vpc"
      subnetwork            = "staging-ml"
    }
    "production" = {
      project_id            = "abridge-client-prod"
      service_account_email = "146004356782-compute@abridge-client-prod.iam.gserviceaccount.com"
      network               = "production-vpc"
      subnetwork            = "production-ml"
    }
  }

  # Selected environment configuration
  env_config = local.environment_configs[data.coder_parameter.environment.value]

  gpu_configs = {
    "none" = {
      machine_type = "e2-standard-4"
      gpu_type     = ""
      gpu_count    = 0
    }
    "nvidia-l4-2x" = {
      machine_type = "g2-standard-24"
      gpu_type     = "nvidia-l4"
      gpu_count    = 2
    }
    "nvidia-h100-80gb" = {
      machine_type = "a3-highgpu-8g"
      gpu_type     = "nvidia-h100-80gb"
      gpu_count    = 8
    }
  }

  gpu_config = local.gpu_configs[data.coder_parameter.gpu_type.value]

  # Reservation mapping based on GPU selection
  reservation_mappings = {
    "none"             = ""
    "nvidia-l4-2x"     = "projects/abridge-client-prod/reservations/shared-g2-standard-24-usc1-a-l4-4"
    "nvidia-h100-80gb" = "projects/abridge-client-prod/reservations/shared-a3-highgpu-8g-usc1-a-h100"
  }

  selected_reservation = lookup(local.reservation_mappings, data.coder_parameter.gpu_type.value, null)

  gpu_accelerators = local.gpu_config.gpu_count > 0 ? [{
    type  = "projects/${local.env_config.project_id}/zones/${var.zone}/acceleratorTypes/${local.gpu_config.gpu_type}"
    count = local.gpu_config.gpu_count
  }] : []

  dl_images = {
    "pytorch-latest-gpu" = "projects/deeplearning-platform-release/global/images/family/pytorch-latest-gpu"
    "pytorch-latest-cpu" = "projects/deeplearning-platform-release/global/images/family/pytorch-latest-cpu"
    "tf-latest-gpu"      = "projects/deeplearning-platform-release/global/images/family/tf-latest-gpu"
    "tf-latest-cpu"      = "projects/deeplearning-platform-release/global/images/family/tf-latest-cpu"
    "common-gpu"         = "projects/deeplearning-platform-release/global/images/family/common-gpu"
    "common-cpu"         = "projects/deeplearning-platform-release/global/images/family/common-cpu"
    "ubuntu-2204"        = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
  }
  image = local.dl_images[data.coder_parameter.dl_image.value]

  local_ssds = data.coder_parameter.gpu_type.value == "nvidia-h100-80gb" ? [
    for i in range(16) : {
      device_name = "local-ssd-${i}"
      interface   = "NVME"
    }
  ] : []

  startup_script = templatefile("${path.module}/startup.tftpl", {
    username  = lower(data.coder_workspace_owner.me.name)
    useremail = data.coder_workspace_owner.me.email
    gpu_type  = data.coder_parameter.gpu_type.value
    dl_image  = data.coder_parameter.dl_image.value
  })
}

############################
# CODER AGENT
############################
resource "coder_agent" "main" {
  auth           = "google-instance-identity"
  arch           = "amd64"
  os             = "linux"
  startup_script = local.startup_script

  # Environment variables for the agent
  env = {
    HOME = "/home/${lower(data.coder_workspace_owner.me.name)}"
    USER = lower(data.coder_workspace_owner.me.name)
  }

  # System monitoring
  metadata {
    display_name = "CPU Usage"
    key          = "cpu_usage"
    script       = "coder stat cpu"
    interval     = 15
    timeout      = 10
  }

  metadata {
    display_name = "Memory Usage"
    key          = "memory_usage"
    script       = "coder stat mem"
    interval     = 15
    timeout      = 10
  }

  # GPU monitoring when applicable
  dynamic "metadata" {
    for_each = local.gpu_config.gpu_count > 0 ? [1] : []
    content {
      display_name = "GPU Usage"
      key          = "gpu_usage"
      script       = "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits || echo 'N/A'"
      interval     = 15
      timeout      = 10
    }
  }

  dynamic "metadata" {
    for_each = local.gpu_config.gpu_count > 0 ? [1] : []
    content {
      display_name = "GPU Memory"
      key          = "gpu_memory"
      script       = "nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits || echo 'N/A'"
      interval     = 15
      timeout      = 10
    }
  }
}

############################
# IDE MODULES
############################
module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  folder   = "/home/${lower(data.coder_workspace_owner.me.name)}"
}

module "git-config" {
  count                 = data.coder_workspace.me.start_count
  source                = "registry.coder.com/coder/git-config/coder"
  version               = "1.0.15"
  agent_id              = coder_agent.main.id
  allow_username_change = false
  allow_email_change    = false
}

module "cursor" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "1.1.0"
  agent_id = coder_agent.main.id
}

############################
# INFRASTRUCTURE RESOURCES
############################
resource "google_compute_instance" "workspace" {
  count        = data.coder_workspace.me.start_count
  name         = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
  machine_type = local.gpu_config.machine_type
  zone         = var.zone

  network_interface {
    network    = "projects/${local.env_config.project_id}/global/networks/${local.env_config.network}"
    subnetwork = "projects/${local.env_config.project_id}/regions/us-central1/subnetworks/${local.env_config.subnetwork}"
    nic_type   = "GVNIC"
  }

  boot_disk {
    initialize_params {
      image = local.image
      size  = data.coder_parameter.disk_size.value
      type  = "pd-standard"
    }
  }

  dynamic "scratch_disk" {
    for_each = local.local_ssds
    content {
      interface = scratch_disk.value.interface
      size      = 375
    }
  }

  dynamic "guest_accelerator" {
    for_each = local.gpu_accelerators
    content {
      type  = guest_accelerator.value.type
      count = guest_accelerator.value.count
    }
  }

  dynamic "reservation_affinity" {
    for_each = local.selected_reservation != null ? [1] : []
    content {
      type = "SPECIFIC_RESERVATION"
      specific_reservation {
        key    = "compute.googleapis.com/reservation-name"
        values = [local.selected_reservation]
      }
    }
  }

  scheduling {
    on_host_maintenance = local.gpu_config.gpu_count > 0 ? "TERMINATE" : "MIGRATE"
    preemptible         = false
    automatic_restart   = true
  }

  service_account {
    email = local.env_config.service_account_email
    scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/trace.append",
    ]
  }

  metadata = {
    "enable-oslogin"          = "TRUE"
    "enable-osconfig"         = "TRUE"
    "enable-guest-attributes" = "TRUE"
    "block-project-ssh-keys"  = "TRUE"
  }

  metadata_startup_script = coder_agent.main.init_script

  labels = {
    "coder-workspace"   = data.coder_workspace.me.id
    "coder_replaceable" = "yes"
    "workspace-type"    = local.gpu_config.gpu_count > 0 ? "gpu" : "cpu"
    "owner"             = lower(data.coder_workspace_owner.me.name)
    "workspace-name"    = lower(data.coder_workspace.me.name)
    "gpu-type"          = local.gpu_config.gpu_count > 0 ? local.gpu_config.gpu_type : "none"
    "gpu-count"         = tostring(local.gpu_config.gpu_count)
    "machine-type"      = local.gpu_config.machine_type
    "dl-image"          = data.coder_parameter.dl_image.value
    "environment"       = data.coder_parameter.environment.value
    "managed-by"        = "coder"
  }

  shielded_instance_config {
    enable_secure_boot          = false
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}

############################
# AGENT INSTANCE
############################
resource "coder_agent_instance" "main" {
  count       = data.coder_workspace.me.start_count
  agent_id    = coder_agent.main.id
  instance_id = google_compute_instance.workspace[0].instance_id
}

############################
# METADATA
############################
resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = google_compute_instance.workspace[0].id

  item {
    key   = "Machine Type"
    value = local.gpu_config.machine_type
  }

  item {
    key   = "GPU Configuration"
    value = local.gpu_config.gpu_count > 0 ? "${local.gpu_config.gpu_count}x ${local.gpu_config.gpu_type}" : "CPU Only"
  }

  item {
    key   = "Deep Learning Image"
    value = data.coder_parameter.dl_image.value
  }

  item {
    key   = "Zone"
    value = var.zone
  }

  item {
    key   = "Disk Size"
    value = "${data.coder_parameter.disk_size.value} GB"
  }

  item {
    key   = "Local SSDs"
    value = length(local.local_ssds) > 0 ? "${length(local.local_ssds)}x 375GB NVMe" : "None"
  }

  item {
    key   = "Reservation"
    value = "Shared reservations used automatically when available"
  }

  item {
    key   = "Internal IP"
    value = google_compute_instance.workspace[0].network_interface[0].network_ip
  }
}
