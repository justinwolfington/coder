package kubernetes.network_audit_required

import rego.v1

required_policy_names := {
	"langsmith-annotation-proxy-ingress",
	"langsmith-proxy-ingress",
}

deny contains msg if {
	some name in required_policy_names
	not data.kubernetes.network_audit.policy_exists(name)
	msg := sprintf("audit render is missing required NetworkPolicy %q", [name])
}
