package kubernetes.network_audit_prod

import rego.v1

workspace_policy := {
	"apiVersion": "networking.k8s.io/v1",
	"kind": "NetworkPolicy",
	"metadata": {"name": "coder-workspace", "namespace": "coder"},
	"spec": {
		"podSelector": {"matchLabels": {"app.kubernetes.io/name": "coder-workspace"}},
		"policyTypes": ["Egress"],
		"egress": [],
	},
}

test_production_workspace_policy_required if {
	"production audit render is missing required NetworkPolicy \"coder-workspace\"" in deny with input as []
}

test_production_workspace_policy_present if {
	input_documents := [{"path": "rendered.yaml", "contents": workspace_policy}]
	count(deny) == 0 with input as input_documents
}
