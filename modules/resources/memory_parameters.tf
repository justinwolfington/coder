############################
# MEMORY CODER PARAMETERS
############################
# This module contains different variants of memory parameters with different
# validation ranges, used across different templates.

# Standard memory parameter (8-32 GB) - used in cpu-k8s and clinician-k8s
data "coder_parameter" "memory_standard" {
  name         = "memory"
  display_name = "Memory (GB)"
  description  = "The amount of memory in GB (between 8-32)"
  default      = "8"
  icon         = "/icon/memory.svg"
  mutable      = true
  order        = 3
  type         = "number"
  validation {
    min = 8
    max = 32
  }
}

# High memory parameter (16-1024 GB) - used in gpu-k8s and phi-gpu-k8s
data "coder_parameter" "memory_high" {
  name         = "memory"
  display_name = "Memory (GB)"
  description  = "The amount of memory in GB (between 16-1024)"
  default      = "16"
  icon         = "/icon/memory.svg"
  mutable      = true
  order        = 3
  type         = "number"
  validation {
    min = 16
    max = 1024
  }
} 