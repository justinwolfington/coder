locals {
  exectrace_image_repo = "us-central1-docker.pkg.dev/abridge-artifact-registry/coder/exectrace"
  exectrace_image_tag  = "64e8e00"
}

output "logger_script" {
  value = file("${path.module}/logger.tftpl")
}

output "exectrace_image_repo" {
  value = local.exectrace_image_repo
}

output "exectrace_image_tag" {
  value = local.exectrace_image_tag
}

output "exectrace_image" {
  value = "${local.exectrace_image_repo}:${local.exectrace_image_tag}"
}