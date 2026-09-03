package kubernetes.network_audit

import rego.v1

import data.kubernetes.network.array_is_set
import data.kubernetes.network.effective_namespace
import data.kubernetes.network.exact_label_selector
import data.kubernetes.network.exact_policy_types
import data.kubernetes.network.eyes_service_rule
import data.kubernetes.network.llm_gateway_rule
import data.kubernetes.network.manifest_collections
import data.kubernetes.network.required_internet_exclusions
import data.kubernetes.network.strict_proxy_ingress

allowed_policy_names := {
	"coder-workspace",
	"langsmith-annotation-proxy-ingress",
	"langsmith-proxy-ingress",
}

allowed_additional_internet_ports := {
	{"port": 80, "protocol": "TCP"},
	{"port": 19302, "protocol": "UDP"},
}

documents contains document if {
	some item in input
	document := item.contents
}

network_policies contains policy if {
	some document in documents
	document.apiVersion == "networking.k8s.io/v1"
	document.kind == "NetworkPolicy"
	policy := document
}

policies_named(name) := {policy |
	some policy in network_policies
	effective_namespace(policy) == "coder"
	policy.metadata.name == name
}

policy_exists(name) if count(policies_named(name)) > 0

legacy_baseline_rule(rule) if {
	object.keys(rule) == {"ports"}
	array_is_set(rule.ports, {
		{"port": 53, "protocol": "TCP"},
		{"port": 53, "protocol": "UDP"},
		{"port": 443, "protocol": "TCP"},
	})
}

additional_internet_rule(rule) if {
	object.keys(rule) == {"ports", "to"}
	ports := {port | some port in rule.ports}
	count(rule.ports) == count(ports)
	count(ports) > 0
	count(ports - allowed_additional_internet_ports) == 0
	count(rule.to) == 1
	peer := rule.to[0]
	object.keys(peer) == {"ipBlock"}
	block := peer.ipBlock
	object.keys(block) == {"cidr", "except"}
	block.cidr == "0.0.0.0/0"
	exclusions := {cidr | some cidr in block.except}
	count(block.except) == count(exclusions)
	count(required_internet_exclusions - exclusions) == 0
}

metadata_rule(rule) if {
	object.keys(rule) == {"to"}
	array_is_set(rule.to, {
		{"ipBlock": {"cidr": "100.100.100.100/32"}},
		{"ipBlock": {"cidr": "169.254.0.0/16"}},
	})
}

allowed_workspace_rule(rule) if legacy_baseline_rule(rule)
allowed_workspace_rule(rule) if additional_internet_rule(rule)
allowed_workspace_rule(rule) if metadata_rule(rule)
allowed_workspace_rule(rule) if eyes_service_rule(rule)
allowed_workspace_rule(rule) if llm_gateway_rule(rule)

deny contains msg if {
	some policy in network_policies
	effective_namespace(policy) != "coder"
	msg := sprintf("audit NetworkPolicy %q must resolve to namespace coder", [policy.metadata.name])
}

deny contains msg if {
	some collection in manifest_collections
	msg := sprintf("audit network policy render contains unsupported manifest collection kind %q", [collection.kind])
}

deny contains msg if {
	some name in allowed_policy_names
	count(policies_named(name)) > 1
	msg := sprintf("audit render contains duplicate NetworkPolicy %q", [name])
}

deny contains msg if {
	some policy in network_policies
	not policy.metadata.name in allowed_policy_names
	msg := sprintf("audit render contains unreviewed NetworkPolicy %q", [policy.metadata.name])
}

deny contains msg if {
	some policy in policies_named("coder-workspace")
	not exact_label_selector(policy, "coder-workspace")
	msg := "audit coder-workspace must select only standard workspaces"
}

deny contains msg if {
	some policy in policies_named("coder-workspace")
	not exact_policy_types(policy, {"Egress"})
	msg := "audit coder-workspace must apply only to egress"
}

deny contains msg if {
	some policy in policies_named("coder-workspace")
	object.get(policy.spec, "ingress", []) != []
	msg := "audit coder-workspace must not grant ingress"
}

deny contains msg if {
	some policy in policies_named("coder-workspace")
	some rule in object.get(policy.spec, "egress", [])
	not allowed_workspace_rule(rule)
	msg := "audit coder-workspace contains an unreviewed egress rule"
}

deny contains msg if {
	some policy in policies_named("langsmith-proxy-ingress")
	not exact_label_selector(policy, "langsmith-proxy")
	msg := "audit langsmith-proxy-ingress must select only the LangSmith proxy"
}

deny contains msg if {
	some policy in policies_named("langsmith-proxy-ingress")
	not strict_proxy_ingress(policy)
	msg := "audit langsmith-proxy-ingress must match the reviewed node ingress rule"
}

deny contains msg if {
	some policy in policies_named("langsmith-annotation-proxy-ingress")
	not exact_label_selector(policy, "langsmith-annotation-proxy")
	msg := "audit langsmith-annotation-proxy-ingress must select only the annotation proxy"
}

deny contains msg if {
	some policy in policies_named("langsmith-annotation-proxy-ingress")
	not strict_proxy_ingress(policy)
	msg := "audit langsmith-annotation-proxy-ingress must match the reviewed node ingress rule"
}
