# Shared Coder Parameters Module

This module contains shared coder_parameter definitions that are commonly used across multiple Coder workspace templates.

## Purpose

Instead of duplicating the same parameter definitions in each template, this module centralizes common parameters to ensure consistency and ease of maintenance.

## Available Parameters

### Common Parameters (common_parameters.tf)
- `memory` - RAM
- `cpu` - CPU cores
- `home_disk_size` - Home disk size

## Usage Example

To use these shared parameters in your template, you would need to:

1. Import the module in your template's main.tf:

```hcl
module "resources" {
  source = "git::ref"
}
```

2. Reference the parameters through the module outputs:

```hcl
# Example: Using CPU parameter in resource allocation
resources {
  requests = {
    cpu = module.shared_params.cpu.value
  }
}
```

## Note
The coder_parameter are automatically available in all the templates that import the module. While this has no effect on the correctness of workspace creation, the Workspace Builder UI will have redundant parameters. Coder does not support hiding specific parameters within templates as of now hence, exercise caution while adding parameters to the module.