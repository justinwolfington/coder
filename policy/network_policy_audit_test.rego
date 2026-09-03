package kubernetes.network_audit

import rego.v1

fixture_exclusions := data.kubernetes.network.required_internet_exclusions

fixture_network_policy(name, selector, policy_types, ingress, egress) := {
	"apiVersion": "networking.k8s.io/v1",
	"kind": "NetworkPolicy",
	"metadata": {"name": name, "namespace": "coder"},
	"spec": {
		"podSelector": selector,
		"policyTypes": policy_types,
		"ingress": ingress,
		"egress": egress,
	},
}

fixture_baseline_rule := {"ports": [
	{"port": 53, "protocol": "TCP"},
	{"port": 443, "protocol": "TCP"},
	{"port": 53, "protocol": "UDP"},
]}

fixture_metadata_rule := {"to": [
	{"ipBlock": {"cidr": "169.254.0.0/16"}},
	{"ipBlock": {"cidr": "100.100.100.100/32"}},
]}

fixture_workspace(rules) := fixture_network_policy(
	"coder-workspace",
	{"matchLabels": {"app.kubernetes.io/name": "coder-workspace"}},
	["Egress"],
	[],
	rules,
)

fixture_proxy(name, workload_name) := fixture_network_policy(
	name,
	{"matchLabels": {"app.kubernetes.io/name": workload_name}},
	["Ingress"],
	[{
		"from": [{"ipBlock": {"cidr": "10.6.0.0/16"}}],
		"ports": [
			{"port": 8080, "protocol": "TCP"},
			{"port": 15006, "protocol": "TCP"},
		],
	}],
	[],
)

fixture_proxies := [
	fixture_proxy("langsmith-proxy-ingress", "langsmith-proxy"),
	fixture_proxy("langsmith-annotation-proxy-ingress", "langsmith-annotation-proxy"),
]

combined(policies) := [{"path": "rendered.yaml", "contents": policy} | some policy in policies]

test_current_audit_shape_allowed if {
	policies := array.concat([fixture_workspace([fixture_baseline_rule, fixture_metadata_rule])], fixture_proxies)
	count(deny) == 0 with input as combined(policies)
}

test_http_without_destination_denied if {
	backdoor := {"ports": [{"port": 80, "protocol": "TCP"}]}
	"audit coder-workspace contains an unreviewed egress rule" in deny with input as combined([fixture_workspace([fixture_baseline_rule, backdoor, fixture_metadata_rule])])
}

test_split_public_cidr_denied if {
	backdoor := {
		"ports": [{"port": 80, "protocol": "TCP"}],
		"to": [{"ipBlock": {"cidr": "0.0.0.0/1", "except": fixture_exclusions}}],
	}
	"audit coder-workspace contains an unreviewed egress rule" in deny with input as combined([fixture_workspace([fixture_baseline_rule, backdoor, fixture_metadata_rule])])
}

test_additional_internet_missing_cluster_exclusion_denied if {
	backdoor := {
		"ports": [{"port": 80, "protocol": "TCP"}],
		"to": [{"ipBlock": {
			"cidr": "0.0.0.0/0",
			"except": fixture_exclusions - {"172.48.0.0/22"},
		}}],
	}
	"audit coder-workspace contains an unreviewed egress rule" in deny with input as combined([fixture_workspace([fixture_baseline_rule, backdoor, fixture_metadata_rule])])
}

test_wrong_namespace_denied if {
	workspace := object.union(fixture_workspace([fixture_baseline_rule, fixture_metadata_rule]), {"metadata": {"name": "coder-workspace", "namespace": "wrong"}})
	"audit NetworkPolicy \"coder-workspace\" must resolve to namespace coder" in deny with input as combined([workspace])
}

test_workspace_ingress_backdoor_denied if {
	workspace := fixture_network_policy(
		"coder-workspace",
		{"matchLabels": {"app.kubernetes.io/name": "coder-workspace"}},
		["Ingress", "Egress"],
		[{}],
		[fixture_baseline_rule, fixture_metadata_rule],
	)
	"audit coder-workspace must apply only to egress" in deny with input as combined([workspace])
	"audit coder-workspace must not grant ingress" in deny with input as combined([workspace])
}

test_proxy_egress_backdoor_denied if {
	proxy := fixture_network_policy(
		"langsmith-proxy-ingress",
		{"matchLabels": {"app.kubernetes.io/name": "langsmith-proxy"}},
		["Ingress", "Egress"],
		[{}],
		[{}],
	)
	"audit langsmith-proxy-ingress must match the reviewed node ingress rule" in deny with input as combined([fixture_workspace([fixture_baseline_rule, fixture_metadata_rule]), proxy])
}

test_unknown_policy_denied if {
	backdoor := fixture_network_policy("backdoor", {}, ["Egress"], [], [{}])
	"audit render contains unreviewed NetworkPolicy \"backdoor\"" in deny with input as combined([fixture_workspace([fixture_baseline_rule, fixture_metadata_rule]), backdoor])
}

test_list_wrapped_policy_denied if {
	backdoor := fixture_network_policy("backdoor", {}, ["Ingress", "Egress"], [{}], [{}])
	collection := {
		"apiVersion": "v1",
		"kind": "List",
		"items": [backdoor],
	}
	"audit network policy render contains unsupported manifest collection kind \"List\"" in deny with input as combined([collection])
}
