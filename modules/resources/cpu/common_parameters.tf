############################
# COMMON CODER PARAMETERS
############################
# This module contains coder_parameter definitions that are commonly used
# across multiple templates in the coder workspace setup.
# The resource with the lower order is presented before the one with greater value.
# The order of parameters in the UI : cpu -> memory -> home_disk_size

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU Cores"
  description  = "The number of CPU cores (between 8-16)"
  default      = "8"
  icon         = "/icon/memory.svg"
  mutable      = true
  order        = 2
  type         = "number"
  validation {
    min = 8
    max = 16
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (GB)"
  description  = "The amount of memory in GB (between 16-48)"
  default      = "16"
  icon         = "/icon/memory.svg"
  mutable      = true
  order        = 3
  type         = "number"
  validation {
    min = 16
    max = 48
  }
}

data "coder_parameter" "home_disk_size" {
  name         = "home_disk_size"
  display_name = "Home disk size (GB)"
  description  = "The size of the home disk in GB (between 64-1024)"
  default      = "64"
  type         = "number"
  icon         = "/icon/folder.svg"
  mutable      = true
  order        = 4
  validation {
    min = 64
    max = 1024
  }
}
