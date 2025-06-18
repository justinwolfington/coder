############################
# COMMON CODER PARAMETERS
############################
# This module contains coder_parameter definitions that are commonly used
# across multiple templates in the coder workspace setup.

# Repository URL parameter - used in all k8s templates
# CPU cores parameter - used in all k8s templates
data "coder_parameter" "cpux" {
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