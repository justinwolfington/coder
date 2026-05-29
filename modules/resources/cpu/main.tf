############################
# SHARED CODER PARAMETERS MODULE
############################
# This is the main entry point for the shared coder parameters module.
# It aggregates all parameter definitions from the individual parameter files.
# NOTE: Any template that imports this module will automatically import all
# the parameters defined in common_parameters.tf, implying that the variables
# will be shown on the template UI irrespective of whether they are used or
# not. This is a limitation of the coder terraform provider.

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13.1"
    }
  }
}

# All parameters are exposed through outputs defined in outputs.tf
