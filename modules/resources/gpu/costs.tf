variable "gpu_cost_per_unit" {
  description = "Daily cost per one GPU unit for different GPU types"
  type        = map(number)
  default = {
    ""                   = 0
    "nvidia-l4"          = 2
    "nvidia-h100-80gb"   = 5
  }
}