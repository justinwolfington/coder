############################
# COMMON CODER PARAMETERS
############################
# This module contains coder_parameter definitions that are commonly used
# across multiple templates in the coder workspace setup.

# Repository URL parameter - used in all k8s templates
data "coder_parameter" "repository_url" {
  name         = "repository_url"
  display_name = "Repository URL"
  description  = "GitHub repository URL (leave empty for no repository)"
  default      = "https://github.com/abridgeai/completion-service"
  mutable      = true
  order        = 1
  type         = "string"
}

# CPU cores parameter - used in all k8s templates
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

# Home disk size parameter - used in all k8s templates
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