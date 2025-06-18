############################
# OUTPUTS FOR CODER PARAMETERS
############################

output "cpu" {
  description = "CPU cores parameter"
  value       = data.coder_parameter.cpux.value
}