output "bucket_enabled" {
  description = "Whether the GCS bucket mount is enabled"
  value       = local.bucket_enabled
}

output "bucket_name" {
  description = "Name of the GCS bucket"
  value       = var.bucket_name
}

output "mount_path" {
  description = "Path where the bucket is mounted"
  value       = var.mount_path
}

output "mount_options" {
  description = "GCSFuse mount options"
  value       = var.mount_options
}

output "gcsfuse_annotation" {
  description = "Annotation to enable GCSFuse sidecar injection"
  value       = local.bucket_enabled ? "true" : null
}

output "istio_ip_exclusion" {
  description = "IP ranges to exclude from Istio traffic interception for GCS metadata server"
  value       = local.bucket_enabled ? "169.254.169.254/32,100.100.100.100/32" : null
}

output "volume_mount" {
  description = "Kubernetes volume mount configuration for the bucket"
  value = local.bucket_enabled ? {
    mount_path = var.mount_path
    name       = "gcs-bucket"
    read_only  = false
  } : null
}

output "volume" {
  description = "Kubernetes volume configuration for the GCS bucket"
  value = local.bucket_enabled ? {
    name = "gcs-bucket"
    csi = {
      driver = "gcsfuse.csi.storage.gke.io"
      volume_attributes = {
        bucketName   = var.bucket_name
        mountOptions = var.mount_options
      }
    }
  } : null
}
