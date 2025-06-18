variable "ram_cost_per_gb" {
  type = number
  default = 1
}

variable "cpu_cost_per_core" {
    type = number
    default = 2
}

variable "gpu_cost_per_unit" {
  description = "Daily cost per one GPU unit for different GPU types"
  type        = map(number)
  default = {
    ""                   = 0
    "nvidia-l4"          = 2
    "nvidia-h100-80gb"   = 5 
  }
}