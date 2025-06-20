output "workspace_name" {
  description = "Name of the created workspace"
  value       = data.coder_workspace.me.name
}

output "workspace_owner" {
  description = "Owner of the workspace"
  value       = data.coder_workspace_owner.me.name
}

output "cpu_cores" {
  description = "Number of CPU cores allocated"
  value       = module.cpu_resources.cpu.value
}

output "memory_gb" {
  description = "Amount of memory allocated in GB"
  value       = module.cpu_resources.memory.value
}

output "home_disk_size" {
  description = "Size of home disk in GB"
  value       = module.cpu_resources.home_disk_size.value
}

output "repository_url" {
  description = "Repository URL being used"
  value       = data.coder_parameter.repository_url.value
}

output "gpu_accelerator" {
  description = "GPU accelerator type selected"
  value       = data.coder_parameter.gpu_accelerator.value
}

output "gpu_count" {
  description = "Number of GPUs allocated"
  value       = data.coder_parameter.gpu_count.value
}

output "namespace" {
  description = "Kubernetes namespace where workspace is deployed"
  value       = var.namespace
}
