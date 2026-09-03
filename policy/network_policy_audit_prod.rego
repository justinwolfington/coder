package kubernetes.network_audit_prod

import rego.v1

deny contains msg if {
	not data.kubernetes.network_audit.policy_exists("coder-workspace")
	msg := "production audit render is missing required NetworkPolicy \"coder-workspace\""
}
