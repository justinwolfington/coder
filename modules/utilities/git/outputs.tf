output "github_token" {
  description = "GitHub access token from Coder external auth (null if not required)"
  value       = length(data.coder_external_auth.github) > 0 ? data.coder_external_auth.github[0].access_token : null
  sensitive   = true
}