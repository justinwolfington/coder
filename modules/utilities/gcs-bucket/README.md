# GCS Bucket Mount Module

This module provides a reusable configuration for mounting Google Cloud Storage (GCS) buckets in Coder workspaces using GCSFuse CSI driver.

## Purpose

Centralizes GCS bucket mounting logic to:
- Enable conditional bucket access based on environment and user group membership
- Provide consistent mounting configuration across templates
- Support multiple buckets with different configurations
- Simplify PHI and secure data access patterns

## Features

- **Conditional Access Control**: Only shows mount option to users in specific groups and environments
- **Configurable Mount Options**: Support for various GCSFuse mount options
- **Kubernetes Integration**: Provides volume and volume_mount configurations
- **Istio Compatibility**: Includes IP exclusions for GCS metadata server
- **Flexible Configuration**: Customizable bucket name, mount path, and display options

## Usage Example

### Basic Usage (UTD Bucket)

```hcl
module "utd_bucket" {
  source                  = "git::https://github.com/abridgeai/coder.git//modules/utilities/gcs-bucket?ref=COMMIT_HASH"
  environment             = var.environment
  workspace_owner_groups  = data.coder_workspace_owner.me.groups
  required_group          = "UTDACCESS"
  bucket_name             = "abridge-client-prod-wk-secure-bucket"
  mount_path              = "/utddata"
  mount_options           = "implicit-dirs,only-dir=decrypt"
  parameter_name          = "utd_bucket_access"
  display_name            = "UTD Bucket Mount"
  description             = "Enable to mount the UTD secure bucket at /utddata"
  parameter_order         = 10
}

locals {
  utd_bucket_enabled = module.utd_bucket.bucket_enabled
}

# In your Kubernetes deployment:
resource "kubernetes_deployment" "main" {
  # ... other configuration ...

  spec {
    template {
      metadata {
        annotations = merge(local.annotations, {
          "gke-gcsfuse/volumes"                              = module.utd_bucket.gcsfuse_annotation
          "traffic.sidecar.istio.io/excludeOutboundIPRanges" = module.utd_bucket.istio_ip_exclusion
        })
      }
      spec {
        service_account_name = local.utd_bucket_enabled ? "coder" : null

        container {
          # ... other configuration ...

          # Conditionally mount bucket
          dynamic "volume_mount" {
            for_each = module.utd_bucket.volume_mount != null ? [module.utd_bucket.volume_mount] : []
            content {
              mount_path = volume_mount.value.mount_path
              name       = volume_mount.value.name
              read_only  = volume_mount.value.read_only
            }
          }
        }

        # Conditionally add volume
        dynamic "volume" {
          for_each = module.utd_bucket.volume != null ? [module.utd_bucket.volume] : []
          content {
            name = volume.value.name
            csi {
              driver            = volume.value.csi.driver
              volume_attributes = volume.value.csi.volume_attributes
            }
          }
        }
      }
    }
  }
}
```

### Multiple Buckets

```hcl
module "phi_bucket" {
  source                  = "git::https://github.com/abridgeai/coder.git//modules/utilities/gcs-bucket?ref=COMMIT_HASH"
  environment             = var.environment
  workspace_owner_groups  = data.coder_workspace_owner.me.groups
  required_group          = "PHI_ACCESS"
  bucket_name             = "phi-secure-bucket"
  mount_path              = "/phidata"
  mount_options           = "implicit-dirs"
  parameter_name          = "phi_bucket_access"
  display_name            = "PHI Data Bucket"
  description             = "Enable to mount PHI data bucket"
  parameter_order         = 10
}

module "research_bucket" {
  source                  = "git::https://github.com/abridgeai/coder.git//modules/utilities/gcs-bucket?ref=COMMIT_HASH"
  environment             = var.environment
  workspace_owner_groups  = data.coder_workspace_owner.me.groups
  required_group          = "RESEARCH_TEAM"
  bucket_name             = "research-data-bucket"
  mount_path              = "/research"
  mount_options           = "implicit-dirs,file-mode=644,dir-mode=755"
  parameter_name          = "research_bucket_access"
  display_name            = "Research Data Bucket"
  description             = "Enable to mount research data bucket"
  parameter_order         = 11
}
```

## Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `environment` | string | Environment (e.g., production, staging) | Required |
| `workspace_owner_groups` | list(string) | List of groups the workspace owner belongs to | Required |
| `required_group` | string | Group name required for bucket access | Required |
| `bucket_name` | string | GCS bucket name to mount | Required |
| `mount_path` | string | Path where the bucket should be mounted | `/data` |
| `mount_options` | string | GCSFuse mount options | `implicit-dirs` |
| `parameter_name` | string | Name of the Coder parameter | `gcs_bucket_access` |
| `display_name` | string | Display name for the parameter | `GCS Bucket Mount` |
| `description` | string | Description for the parameter | `Enable to mount the GCS bucket.` |
| `parameter_order` | number | Order of the parameter in the UI | `10` |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| `bucket_enabled` | bool | Whether the GCS bucket mount is enabled |
| `bucket_name` | string | Name of the GCS bucket |
| `mount_path` | string | Path where the bucket is mounted |
| `mount_options` | string | GCSFuse mount options |
| `gcsfuse_annotation` | string | Annotation to enable GCSFuse sidecar injection |
| `istio_ip_exclusion` | string | IP ranges to exclude from Istio traffic interception |
| `volume_mount` | object | Kubernetes volume mount configuration |
| `volume` | object | Kubernetes volume configuration |

## Requirements

### Kubernetes Cluster Requirements
- GKE cluster with GCSFuse CSI driver enabled
- Workload Identity configured
- Service account with GCS bucket access permissions

### Terraform Provider Requirements
- `coder` provider version 2.7.0 or higher

## GCSFuse Mount Options

Common mount options include:
- `implicit-dirs` - Create implicit directories for path components
- `only-dir=<path>` - Only mount a specific subdirectory
- `file-mode=<mode>` - Set file permissions (e.g., 644)
- `dir-mode=<mode>` - Set directory permissions (e.g., 755)
- `uid=<uid>` - Set owner UID
- `gid=<gid>` - Set owner GID

For more options, see [GCSFuse documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/cloud-storage-fuse-csi-driver).

## Security Considerations

- **Access Control**: The module only displays the mount option to users in the specified group
- **Environment Restriction**: Can be restricted to specific environments (e.g., production only)
- **IAM Permissions**: Ensure the Kubernetes service account has minimal required permissions
- **Audit Logging**: Enable GCS audit logging for compliance requirements
- **Istio Integration**: Properly excludes GCS metadata server IPs from service mesh

## Example: phi-gpu-k8s Template

See the [phi-gpu-k8s template](../../../templates/phi-gpu-k8s/main.tf) for a complete implementation example.
