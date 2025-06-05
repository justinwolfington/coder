output "instance_name" {
  description = "Name of the created GCP compute instance"
  value       = data.coder_workspace.me.start_count > 0 ? google_compute_instance.workspace[0].name : ""
}

output "internal_ip" {
  description = "Internal IP address of the compute instance"
  value       = data.coder_workspace.me.start_count > 0 ? google_compute_instance.workspace[0].network_interface[0].network_ip : ""
}

output "machine_type" {
  description = "Machine type used for the compute instance"
  value       = local.gpu_config.machine_type
}

output "gpu_config" {
  description = "GPU configuration selected for the workspace"
  value       = data.coder_parameter.gpu_type.value
}

output "dl_image" {
  description = "Deep learning image selected for the workspace"
  value       = data.coder_parameter.dl_image.value
}

output "zone" {
  description = "GCP zone where the instance is running"
  value       = var.zone
}
