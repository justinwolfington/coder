############################
# OUTPUTS FOR CODER PARAMETERS AND COSTS
############################

output "cpu" {
  description = "CPU cores parameter"
  value       = data.coder_parameter.cpu
}

output "memory" {
  description = "Memory parameter"
  value       = data.coder_parameter.memory
}

output "home_disk_size" {
  description = "Home disk size parameter"
  value       = data.coder_parameter.home_disk_size
}

output "ram_cost_per_gb" {
    value = var.ram_cost_per_gb
}

output "cpu_cost_per_core" {
    value = var.cpu_cost_per_core
}