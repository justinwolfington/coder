terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "2.18.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "7.42.0"
    }
  }
}

############################
# PROVIDERS
############################
provider "coder" {
  url = var.coder_url
}
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
# SHARED MODULES
############################
module "gpu_resources" {
  source = "git::https://github.com/abridgeai/coder.git//modules/resources/gpu?ref=v1.15.0"
}

module "git_utilities" {
  source              = "git::https://github.com/abridgeai/coder.git//modules/utilities/git?ref=v1.15.0"
  start_count         = data.coder_workspace.me.start_count
  agent_id            = coder_agent.main.id
  repo_url            = ""
  should_clone        = false
  require_github_auth = false
}

module "ide_modules" {
  source      = "git::https://github.com/abridgeai/coder.git//modules/utilities/ide?ref=v1.15.0"
  start_count = data.coder_workspace.me.start_count
  agent_id    = coder_agent.main.id
}

module "dotfiles" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dotfiles/coder"
  version  = "1.4.2"
  agent_id = coder_agent.main.id
}

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

data "coder_parameter" "cpu_machine_type" {
  name         = "cpu_machine_type"
  display_name = "Workspace Size"
  description  = "vCPU and RAM for the workspace (applies only when GPU Configuration is No GPU)"
  type         = "string"
  default      = "e2-standard-4"
  mutable      = true

  option {
    name  = "2 vCPU / 8 GB RAM"
    value = "e2-standard-2"
  }
  option {
    name  = "4 vCPU / 16 GB RAM"
    value = "e2-standard-4"
  }
  option {
    name  = "8 vCPU / 32 GB RAM"
    value = "e2-standard-8"
  }
  option {
    name  = "16 vCPU / 64 GB RAM"
    value = "e2-standard-16"
  }
  option {
    name  = "32 vCPU / 128 GB RAM"
    value = "e2-standard-32"
  }
}

data "coder_parameter" "dl_image" {
  name         = "dl_image"
  display_name = "Deep Learning Image"
  description  = "Select deep learning platform image"
  type         = "string"
  default      = "pytorch-2-9-cu129-ubuntu-2204-nvidia-580-v20260730"
  mutable      = true

  # CUDA 12.9 / driver 580. The active line; CUDA 13 is still unpublished by GCP.
  option {
    name  = "PyTorch 2.9 + CUDA 12.9 (Ubuntu 22.04)"
    value = "pytorch-2-9-cu129-ubuntu-2204-nvidia-580-v20260730"
  }
  option {
    name  = "Multi-Framework + CUDA 12.9 (Ubuntu 22.04)"
    value = "common-cu129-ubuntu-2204-nvidia-580-v20260804"
  }
  option {
    name  = "Ubuntu 24.04 Noble (Clean Base)"
    value = "ubuntu-2404-noble-amd64-v20260723"
  }
  # Superseded snapshots. Retained as options because dl_images is an exact-match
  # lookup with no fallback and coder validates a stored value against this list,
  # so removing one breaks the next build of any workspace still holding it.
  # Prune once usage is confirmed zero.
  option {
    name  = "PyTorch 2.9 + CUDA 12.9 (superseded, Jun snapshot)"
    value = "pytorch-2-9-cu129-ubuntu-2204-nvidia-580-v20260611"
  }
  option {
    name  = "Multi-Framework + CUDA 12.9 (superseded, Jun snapshot)"
    value = "common-cu129-ubuntu-2204-nvidia-580-v20260611"
  }
  option {
    name  = "Ubuntu 24.04 Noble (superseded, May snapshot)"
    value = "ubuntu-2404-noble-amd64-v20260517"
  }
  # CUDA 12.8 / driver 570. GCP stopped publishing this family after v20260320,
  # so these cannot be refreshed. Kept only so existing workspaces still resolve
  # their stored parameter; they boot today but will fail once GCP moves the
  # snapshots from DEPRECATED to OBSOLETE. Migrate to a CUDA 12.9 option.
  option {
    name  = "PyTorch 2.7 + CUDA 12.8 (discontinued, migrate off)"
    value = "pytorch-2-7-cu128-ubuntu-2204-nvidia-570-v20260320"
  }
  option {
    name  = "Multi-Framework + CUDA 12.8 (discontinued, migrate off)"
    value = "common-cu128-ubuntu-2204-nvidia-570-v20260320"
  }
}

data "coder_parameter" "disk_size" {
  name         = "disk_size"
  display_name = "Home Disk Size (GB)"
  description  = "Size of your persistent /home data disk in GB. This disk survives workspace stop/start, rebuilds, and image upgrades - keep your code, datasets, and caches here. Recommended: 500GB+ for L4, 1TB+ for H100. (Lowering this replaces the disk and wipes /home.)"
  type         = "number"
  default      = 500
  mutable      = true

  validation {
    min = 100
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
      service_account_email = "959950361719-compute@developer.gserviceaccount.com"
      network               = "staging-vpc"
      subnetwork            = "staging-ml"
    }
    "production" = {
      project_id            = "abridge-client-prod"
      service_account_email = "146004356782-compute@developer.gserviceaccount.com"
      network               = "production-vpc"
      subnetwork            = "production-ml"
    }
  }

  # Selected environment configuration
  env_config = local.environment_configs[data.coder_parameter.environment.value]

  gpu_configs = {
    "none" = {
      machine_type          = "e2-standard-4"
      gpu_type              = ""
      gpu_count             = 0
      disk_type             = "pd-standard"
      recommended_disk_size = 256
      local_ssd_description = "None"
    }
    "nvidia-l4-2x" = {
      machine_type          = "g2-standard-24"
      gpu_type              = "nvidia-l4"
      gpu_count             = 2
      disk_type             = "pd-ssd"
      recommended_disk_size = 500
      local_ssd_description = "None (L4 instances use persistent disks)"
    }
    "nvidia-h100-80gb" = {
      machine_type          = "a3-highgpu-8g"
      gpu_type              = "nvidia-h100-80gb"
      gpu_count             = 8
      disk_type             = "pd-ssd"
      recommended_disk_size = 1000
      local_ssd_description = "16x 375GB NVMe (Total: 6000 GB)"
    }
  }

  gpu_config = local.gpu_configs[data.coder_parameter.gpu_type.value]

  # No-GPU workspaces pick their own CPU size; GPU tiers are fixed by the accelerator.
  machine_type = data.coder_parameter.gpu_type.value == "none" ? data.coder_parameter.cpu_machine_type.value : local.gpu_config.machine_type

  # ponytail: GCP e2 us-central1 on-demand list price, rounded to nearest whole $/day (24h).
  # Surfaced to nudge against oversized picks; refresh from GCP pricing if rates move.
  cpu_cost_per_day = {
    "e2-standard-2"  = 2
    "e2-standard-4"  = 3
    "e2-standard-8"  = 6
    "e2-standard-16" = 13
    "e2-standard-32" = 26
  }

  # Reservation mapping based on GPU selection

  reservation_mappings = {
    "none"             = ""
    "nvidia-l4-2x"     = ""
    "nvidia-h100-80gb" = "projects/abridge-client-prod/reservations/shared-a3-highgpu-8g-usc1-a-h100"
  }

  selected_reservation = lookup(local.reservation_mappings, data.coder_parameter.gpu_type.value, null)

  gpu_accelerators = local.gpu_config.gpu_count > 0 ? [{
    type  = "projects/${local.env_config.project_id}/zones/${var.zone}/acceleratorTypes/${local.gpu_config.gpu_type}"
    count = local.gpu_config.gpu_count
  }] : []

  # Run the following commands to get a list of supported images:
  # Deep Learning images:
  # gcloud compute images list --project deeplearning-platform-release --format="value(NAME)" --no-standard-images
  # Ubuntu images:
  # gcloud compute images list --project ubuntu-os-cloud --format="value(NAME)" --filter="name~ubuntu-2404"

  dl_images = {
    "pytorch-2-7-cu128-ubuntu-2204-nvidia-570-v20260320" = "projects/deeplearning-platform-release/global/images/pytorch-2-7-cu128-ubuntu-2204-nvidia-570-v20260320"
    "common-cu128-ubuntu-2204-nvidia-570-v20260320"      = "projects/deeplearning-platform-release/global/images/common-cu128-ubuntu-2204-nvidia-570-v20260320"
    "pytorch-2-9-cu129-ubuntu-2204-nvidia-580-v20260611" = "projects/deeplearning-platform-release/global/images/pytorch-2-9-cu129-ubuntu-2204-nvidia-580-v20260611"
    "common-cu129-ubuntu-2204-nvidia-580-v20260611"      = "projects/deeplearning-platform-release/global/images/common-cu129-ubuntu-2204-nvidia-580-v20260611"
    "ubuntu-2404-noble-amd64-v20260517"                  = "projects/ubuntu-os-cloud/global/images/ubuntu-2404-noble-amd64-v20260517"

    # Current snapshots. Old keys above are kept because this is an exact-match
    # lookup with no fallback, so a workspace holding a superseded value would
    # fail at plan time if its key disappeared.
    "pytorch-2-9-cu129-ubuntu-2204-nvidia-580-v20260730" = "projects/deeplearning-platform-release/global/images/pytorch-2-9-cu129-ubuntu-2204-nvidia-580-v20260730"
    "common-cu129-ubuntu-2204-nvidia-580-v20260804"      = "projects/deeplearning-platform-release/global/images/common-cu129-ubuntu-2204-nvidia-580-v20260804"
    "ubuntu-2404-noble-amd64-v20260723"                  = "projects/ubuntu-os-cloud/global/images/ubuntu-2404-noble-amd64-v20260723"
  }
  image = local.dl_images[data.coder_parameter.dl_image.value]

  # Local SSDs only for H100 instances, L4 instances use persistent disks
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

  # Recommended disk size based on GPU configuration
  recommended_disk_size = local.gpu_config.recommended_disk_size

  # Working directory for IDEs and Claude Code
  repo_dir = "/home/${lower(data.coder_workspace_owner.me.name)}"

  # Boot disk holds only the OS + tooling (conda, docker layers). It is
  # image-derived and therefore REPLACED on image bumps / rebuilds, so nothing
  # durable may live here - user data lives on google_compute_disk.home_disk.
  # ponytail: fixed 200GB; promote to a coder_parameter if OS/docker outgrows it.
  boot_disk_size = 200
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
# CODER APPLICATIONS
############################
module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "1.5.2"
  agent_id = coder_agent.main.id
  folder   = "/home/${lower(data.coder_workspace_owner.me.name)}"
}

############################
# INFRASTRUCTURE RESOURCES
############################

resource "google_compute_disk" "vm_boot_disk" {
  name  = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}-boot-disk"
  type  = local.gpu_config.disk_type
  zone  = var.zone
  size  = local.boot_disk_size
  image = local.image
  labels = {
    "coder-workspace"   = data.coder_workspace.me.id
    "coder_replaceable" = "yes"
    "workspace-type"    = local.gpu_config.gpu_count > 0 ? "gpu" : "cpu"
  }
}

# Persistent /home data disk. Deliberately created WITHOUT an image, so it is a
# blank volume: changing the deep-learning image or rebuilding the workspace
# replaces the boot disk above but NEVER touches this one. No count -> survives
# stop/start. Not labeled coder_replaceable - it holds the user's data.
# Only a workspace DELETE (terraform destroy) removes it.
resource "google_compute_disk" "home_disk" {
  name = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}-home-disk"
  type = local.gpu_config.disk_type
  zone = var.zone
  size = data.coder_parameter.disk_size.value
  labels = {
    "coder-workspace" = data.coder_workspace.me.id
    "workspace-type"  = local.gpu_config.gpu_count > 0 ? "gpu" : "cpu"
  }
}

# Without this, dropping count reads as a new resource and plans destroy+create.
moved {
  from = google_compute_instance.workspace[0]
  to   = google_compute_instance.workspace
}

# Stopped, not destroyed. count = start_count dropped the instance from state on
# every stop, so a build failing mid-write orphaned a VM that still held the
# disks above, and the next destroy hit resourceInUseByAnotherResource.
resource "google_compute_instance" "workspace" {
  name           = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
  machine_type   = local.machine_type
  zone           = var.zone
  desired_status = data.coder_workspace.me.start_count > 0 ? "RUNNING" : "TERMINATED"

  network_interface {
    network    = "projects/${local.env_config.project_id}/global/networks/${local.env_config.network}"
    subnetwork = "projects/${local.env_config.project_id}/regions/us-central1/subnetworks/${local.env_config.subnetwork}"
    nic_type   = "GVNIC"
  }

  boot_disk {
    source      = google_compute_disk.vm_boot_disk.self_link
    auto_delete = false
  }

  # Persistent /home; surfaces in the guest at /dev/disk/by-id/google-home.
  attached_disk {
    source      = google_compute_disk.home_disk.self_link
    device_name = "home"
    mode        = "READ_WRITE"
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
    for_each = local.selected_reservation != null && local.selected_reservation != "" ? [1] : []
    content {
      type = "SPECIFIC_RESERVATION"
      specific_reservation {
        key    = "compute.googleapis.com/reservation-name"
        values = [local.selected_reservation]
      }
    }
  }

  # For instances without specific reservations (like L4), use ANY_RESERVATION to get cost benefits
  dynamic "reservation_affinity" {
    for_each = local.selected_reservation == null || local.selected_reservation == "" ? [1] : []
    content {
      type = "ANY_RESERVATION"
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

  # coder_scripts run concurrently with the startup script that mounts
  # /home/<user>, so the mount point must exist before the agent starts or
  # git-config fails to create .gitconfig and the workspace reports unhealthy.
  metadata_startup_script = <<-EOT
    #!/bin/bash
    mkdir -p /home/${lower(data.coder_workspace_owner.me.name)}
    ${coder_agent.main.init_script}
  EOT

  labels = {
    "coder-workspace"   = data.coder_workspace.me.id
    "coder_replaceable" = "yes"
    "workspace-type"    = local.gpu_config.gpu_count > 0 ? "gpu" : "cpu"
    "owner"             = lower(data.coder_workspace_owner.me.name)
    "workspace-name"    = lower(data.coder_workspace.me.name)
    "gpu-type"          = local.gpu_config.gpu_count > 0 ? local.gpu_config.gpu_type : "none"
    "gpu-count"         = tostring(local.gpu_config.gpu_count)
    "machine-type"      = local.machine_type
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
  instance_id = google_compute_instance.workspace.instance_id
}

############################
# METADATA
############################
resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = google_compute_instance.workspace.id
  daily_cost  = local.gpu_config.gpu_count > 0 ? lookup(module.gpu_resources.gpu_cost_per_unit, local.gpu_config.gpu_type, 0) * local.gpu_config.gpu_count : lookup(local.cpu_cost_per_day, local.machine_type, 0)

  item {
    key   = "Machine Type"
    value = local.machine_type
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
    value = "${data.coder_parameter.disk_size.value} GB (Recommended: ${local.recommended_disk_size} GB for ${local.gpu_config.gpu_count > 0 ? "GPU" : "CPU"} workloads)"
  }

  item {
    key   = "Local SSDs"
    value = local.gpu_config.local_ssd_description
  }

  item {
    key   = "Reservation"
    value = "Shared reservations used automatically when available"
  }

  item {
    key   = "Reservation Strategy"
    value = local.selected_reservation != null && local.selected_reservation != "" ? "Specific reservation: ${local.selected_reservation}" : "Any available reservation (cost-optimized)"
  }

  item {
    key   = "Internal IP"
    value = google_compute_instance.workspace.network_interface[0].network_ip
  }
}
