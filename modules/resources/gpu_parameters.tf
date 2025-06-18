############################
# GPU-SPECIFIC CODER PARAMETERS
############################
# This module contains GPU-related coder_parameter definitions that are
# shared between GPU-enabled templates (gpu-k8s and phi-gpu-k8s).

# GPU accelerator type parameter
data "coder_parameter" "gpu_accelerator" {
  name         = "gpu_accelerator"
  display_name = "GPU Accelerator Type"
  description  = "Choose GPU type. Must match 'cloud.google.com/gke-accelerator' label values on GKE nodes. Leave empty for CPU-only."
  default      = ""
  mutable      = true
  order        = 5
  icon         = "/icon/container.svg"
  type         = "string"
  option {
    name  = "No GPU"
    value = ""
  }
  option {
    name  = "NVIDIA L4"
    value = "nvidia-l4"
  }
  option {
    name  = "NVIDIA H100 (80GB)"
    value = "nvidia-h100-80gb"
  }
}

# GPU count parameter
data "coder_parameter" "gpu_count" {
  name         = "gpu_count"
  display_name = "Number of GPUs"
  description  = "Number of GPUs to allocate to the workspace. Only applicable if a GPU Accelerator Type is selected."
  default      = "1"
  mutable      = true
  order        = 6
  type         = "number"
  icon         = "/icon/container.svg"
  validation {
    min = 1
    max = 8 # Adjust max as per typical node limits / user needs
  }
} 