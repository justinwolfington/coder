package kubernetes.network_audit_required

import rego.v1

fixture_policy(name) := {
	"apiVersion": "networking.k8s.io/v1",
	"kind": "NetworkPolicy",
	"metadata": {"name": name, "namespace": "coder"},
	"spec": {},
}

test_required_audit_policies_present if {
	input_documents := [
		{"path": "rendered.yaml", "contents": fixture_policy("langsmith-proxy-ingress")},
		{"path": "rendered.yaml", "contents": fixture_policy("langsmith-annotation-proxy-ingress")},
	]
	count(deny) == 0 with input as input_documents
}

test_required_audit_policy_missing if {
	input_documents := [{"path": "rendered.yaml", "contents": fixture_policy("langsmith-annotation-proxy-ingress")}]
	"audit render is missing required NetworkPolicy \"langsmith-proxy-ingress\"" in deny with input as input_documents
}
