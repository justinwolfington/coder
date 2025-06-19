# Coder Resources Module

This module contains shared coder_parameter definitions that are commonly used across multiple Coder workspace templates.

## Purpose

Instead of duplicating the same parameter definitions in each template, this module centralizes common parameters to ensure consistency and ease of maintenance.

## Available Modules

### CPU Module (`cpu/`)
Contains CPU-specific resource parameters:
- `memory` - RAM
- `cpu` - CPU cores
- `home_disk_size` - Home disk size

Cost definitions are in `cpu/costs.tf`

### GPU Module (`gpu/`)
Contains GPU-specific resource parameters and cost definitions in `gpu/costs.tf`

## Usage Example

To use these shared parameters in your template, you would need to:

1. Import the specific module in your template's main.tf:

```hcl
# For CPU resources
module "cpu_resources" {
  source = "git::ref//modules/resources/cpu"
}

# For GPU resources
module "gpu_resources" {
  source = "git::ref//modules/resources/gpu"
}
```

2. Reference the parameters through the module outputs:

```hcl
# Example: Using CPU parameter in resource allocation
resources {
  requests = {
    cpu = module.cpu_resources.cpu.value
  }
}
```

## Note
The coder_parameter are automatically available in all the templates that import the module. While this has no effect on the correctness of workspace creation, the Workspace Builder UI will have redundant parameters. Coder does not support hiding specific parameters within templates as of now hence, exercise caution while adding parameters to the module.