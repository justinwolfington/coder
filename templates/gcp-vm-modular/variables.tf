variable "coder_url" {
  type        = string
  description = "Coder access URL for the provider."
  default     = ""
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
