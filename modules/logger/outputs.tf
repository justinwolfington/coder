locals {
  exectrace_image_repo = "us-central1-docker.pkg.dev/abridge-artifact-registry/coder/exectrace"

  # exectrace runs privileged, so a mutable tag here is a direct path from a
  # registry write to arbitrary code in a privileged container on every node.
  exectrace_image_digest = "sha256:09b7d204385f92c756d4b8849e413533c424610b7bb1d616a2a29dec3a85d03d" # f594ffb
}

output "logger_script" {
  value = file("${path.module}/logger.tftpl")
}

output "exectrace_image_repo" {
  value = local.exectrace_image_repo
}

output "exectrace_image_digest" {
  value = local.exectrace_image_digest
}

output "exectrace_image" {
  value = "${local.exectrace_image_repo}@${local.exectrace_image_digest}"
}
