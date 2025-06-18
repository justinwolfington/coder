# Shared Coder Parameters Module

This module contains shared coder_parameter definitions that are commonly used across multiple Coder workspace templates.

## Purpose

Instead of duplicating the same parameter definitions in each template, this module centralizes common parameters to ensure consistency and ease of maintenance.

## Available Parameters

### Common Parameters (common_parameters.tf)
- `repository_url` - GitHub repository URL parameter
- `cpu` - CPU cores parameter (4-16 cores)
- `home_disk_size` - Home disk size parameter (16-1024 GB)

### Memory Parameters (memory_parameters.tf)
- `memory_standard` - Standard memory parameter (8-32 GB) for CPU workspaces
- `memory_high` - High memory parameter (16-1024 GB) for GPU workspaces

### GPU Parameters (gpu_parameters.tf)
- `gpu_accelerator` - GPU accelerator type selection
- `gpu_count` - Number of GPUs (1-8)

## Usage Example

To use these shared parameters in your template, you would need to:

1. Import the module in your template's main.tf:

```hcl
module "shared_params" {
  source = "../../modules/resources"
}
```

2. Reference the parameters through the module outputs:

```hcl
# Example: Using the repository URL parameter
locals {
  repo_url = module.shared_params.repository_url.value
}

# Example: Using CPU parameter in resource allocation
resources {
  requests = {
    cpu = module.shared_params.cpu.value
  }
}
```

## Note

The current template files still contain their own parameter definitions. To fully utilize this shared module, the templates would need to be refactored to import and use these shared parameters instead of defining their own. 