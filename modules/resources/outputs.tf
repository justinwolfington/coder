############################
# OUTPUTS FOR CODER PARAMETERS
############################

# Common parameters outputs
output "repository_url" {
  description = "Repository URL parameter"
  value       = data.coder_parameter.repository_url
}

output "cpu" {
  description = "CPU cores parameter"
  value       = data.coder_parameter.cpu
}

output "home_disk_size" {
  description = "Home disk size parameter"
  value       = data.coder_parameter.home_disk_size
}

# Memory parameters outputs
output "memory_standard" {
  description = "Standard memory parameter (8-32 GB)"
  value       = data.coder_parameter.memory_standard
}

output "memory_high" {
  description = "High memory parameter (16-1024 GB)"
  value       = data.coder_parameter.memory_high
}

# GPU parameters outputs
output "gpu_accelerator" {
  description = "GPU accelerator type parameter"
  value       = data.coder_parameter.gpu_accelerator
}

output "gpu_count" {
  description = "GPU count parameter"
  value       = data.coder_parameter.gpu_count
} 