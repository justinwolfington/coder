############################
# SHARED CODER PARAMETERS MODULE
############################
# This is the main entry point for the shared coder parameters module.
# It aggregates all parameter definitions from the individual parameter files.

terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

# The actual parameter definitions are split across multiple files:
# - common_parameters.tf: Parameters used across all k8s templates
# - memory_parameters.tf: Memory parameter variants with different ranges
# - gpu_parameters.tf: GPU-specific parameters for GPU-enabled templates

# All parameters are exposed through outputs defined in outputs.tf 