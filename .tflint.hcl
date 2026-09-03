plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Pre-existing across templates/ and modules/. Re-enable each once cleared,
# rather than holding the rest of the ruleset back.
rule "terraform_required_version" {
  enabled = false
}

rule "terraform_unused_declarations" {
  enabled = false
}
