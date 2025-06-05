variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
  default     = "client-dev-e301d"
}

variable "zone" {
  description = "Google Cloud zone for the compute instance"
  type        = string
  default     = "us-central1-a"
  validation {
    condition = contains([
      "us-central1-a", "us-central1-b", "us-central1-c", "us-central1-f"
    ], var.zone)
    error_message = "Zone must be in us-central1 region."
  }
}

variable "disk_size" {
  description = "Boot disk size in GB"
  type        = number
  default     = 100
  validation {
    condition     = var.disk_size >= 50 && var.disk_size <= 2000
    error_message = "Disk size must be between 50-2000 GB."
  }
}

variable "service_account_email" {
  description = "Service account email with least permissions required"
  type        = string
  default     = "467615904598-compute@developer.gserviceaccount.com"
}

variable "network" {
  description = "VPC network name"
  type        = string
  default     = "development-vpc"
}

variable "subnetwork" {
  description = "VPC subnetwork name"
  type        = string
  default     = "development-ml"
}
