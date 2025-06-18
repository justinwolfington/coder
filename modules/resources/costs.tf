# zero cost for ram
variable "ram_cost_per_gb" {
  type = number
  default = 0
}

variable "cpu_cost_per_core" {
    type = number
    default = 1
}

variable "gpu_cost_per_unit" {
  description = "Daily cost per one GPU unit for different GPU types"
  type        = map(number)
  default = {
    ""                   = 0
    "nvidia-l4"          = 4
    "nvidia-h100-80gb"   = 10
  }
}