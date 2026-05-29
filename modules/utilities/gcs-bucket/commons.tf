terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13.1"
    }
  }
}

# Dynamic parameter for GCS bucket access - only visible to authorized groups in supported environments
data "coder_parameter" "gcs_bucket_access" {
  count = (
    contains(var.supported_environments, var.environment) &&
    contains(var.workspace_owner_groups, var.required_group)
  ) ? 1 : 0

  name         = var.parameter_name
  display_name = var.display_name
  description  = "${var.description} Mounts at ${var.mount_path}."
  type         = "string"
  default      = "disabled"
  mutable      = true
  order        = var.parameter_order
  icon         = "/icon/folder.svg"

  option {
    name  = "Disabled"
    value = "disabled"
    icon  = "/emojis/274c.png"
  }

  option {
    name  = "Mount ${var.bucket_name} (${var.mount_path})"
    value = "enabled"
    icon  = "/emojis/1f4c2.png"
  }
}

locals {
  # GCS bucket access configuration
  bucket_enabled = (
    length(data.coder_parameter.gcs_bucket_access) > 0 &&
    data.coder_parameter.gcs_bucket_access[0].value == "enabled"
  )
}
