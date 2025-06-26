# Coder Modules

This directory contains reusable Terraform modules for the Coder platform.

## Using Modules from This Repository

When referencing modules from this repository in your Terraform configurations, use the following format:

```hcl
module "module_name" {
  source = "git::https://github.com/abridgeai/coder.git//modules/module_path?ref=COMMIT_HASH"

  # Module variables
  variable1 = "value1"
  variable2 = "value2"
}
```

### Example

```hcl
module "logger" {
  source = "git::https://github.com/abridgeai/coder.git//modules/logger?ref=be83dd2"
}
```

## Why Exact Commit Hashes Are Required

### 1. Branch References Are Unreliable
- **Branches are deleted by default after merge**: In most Git workflows, feature branches are automatically deleted after being merged into the main branch. Using a branch reference would cause your module source to break once the branch is deleted.
- **Branch content changes**: Even if a branch persists, its content can change over time, making your infrastructure configuration unpredictable and potentially breaking existing deployments.

### 2. Terraform Module Source Limitations
- **No variable interpolation**: Terraform does not allow variables in module source arguments. You cannot use `${var.commit_hash}` or any other variable interpolation in the `source` parameter.

## Module Directory Structure

- `logger/` - Logging configuration module
- `resources/` - Resource allocation modules
  - `cpu/` - CPU resource configurations
  - `gpu/` - GPU resource configurations
- `utilities/` - Utility modules
  - `git/` - Git-related utilities
  - `ide/` - IDE configuration utilities

## Updating Module References

When you need to update to a newer version of a module:

1. Identify the new commit hash containing your desired changes
2. Update the `ref=` parameter in your module source
3. Run `terraform init -upgrade` to fetch the new module version
