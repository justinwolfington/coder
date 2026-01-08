variable "environment" {
  type        = string
  description = "Current environment (e.g., production, staging)"
}

variable "supported_environments" {
  type        = list(string)
  description = "List of environments where this bucket can be mounted"
  default     = ["production"]
}

variable "workspace_owner_groups" {
  type        = list(string)
  description = "List of groups the workspace owner belongs to"
}

variable "required_group" {
  type        = string
  description = "Group name required for bucket access"
}

variable "bucket_name" {
  type        = string
  description = "GCS bucket name to mount"
}

variable "mount_path" {
  type        = string
  description = "Path where the bucket should be mounted"
  default     = "/data"
}

variable "mount_options" {
  type        = string
  description = "GCSFuse mount options"
  default     = "implicit-dirs"
}

variable "parameter_name" {
  type        = string
  description = "Name of the Coder parameter for this bucket"
  default     = "gcs_bucket_access"
}

variable "display_name" {
  type        = string
  description = "Display name for the bucket mount parameter"
  default     = "GCS Bucket Mount"
}

variable "description" {
  type        = string
  description = "Description for the bucket mount parameter"
  default     = "Enable to mount the GCS bucket."
}

variable "parameter_order" {
  type        = number
  description = "Order of the parameter in the UI"
  default     = 10
}
