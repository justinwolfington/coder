package kubernetes.network

import rego.v1

expected_internet_exclusions := {
	"0.0.0.0/8",
	"10.0.0.0/8",
	"100.64.0.0/10",
	"127.0.0.0/8",
	"169.254.0.0/16",
	"172.16.0.0/12",
	"172.32.0.0/12",
	"172.48.0.0/22",
	"192.0.0.0/24",
	"192.0.2.0/24",
	"192.168.0.0/16",
	"198.18.0.0/15",
	"198.51.100.0/24",
	"203.0.113.0/24",
	"224.0.0.0/4",
	"240.0.0.0/4",
}

fixture_selector(operator, values) := {"matchExpressions": [{
	"key": "app.kubernetes.io/name",
	"operator": operator,
	"values": values,
}]}

fixture_network_policy(name, pod_selector, policy_types, ingress, egress) := {
	"apiVersion": "networking.k8s.io/v1",
	"kind": "NetworkPolicy",
	"metadata": {"name": name, "namespace": "coder"},
	"spec": {
		"podSelector": pod_selector,
		"policyTypes": policy_types,
		"ingress": ingress,
		"egress": egress,
	},
}

fixture_internet_rule(cidr, exclusions) := {
	"ports": [{"port": 443, "protocol": "TCP"}],
	"to": [{"ipBlock": {"cidr": cidr, "except": exclusions}}],
}

fixture_database_rule := {
	"ports": [{"port": 5432, "protocol": "TCP"}],
	"to": [{"ipBlock": {"cidr": "10.6.0.104/32"}}],
}

fixture_control_plane_ingress := [
	{"from": [{"ipBlock": {"cidr": "10.12.0.0/16"}}]},
	{"from": [{"podSelector": {}}]},
]

baseline_policies := [
	fixture_network_policy("coder-workspace", fixture_selector("In", workspace_names), ["Egress"], [], [fixture_internet_rule("0.0.0.0/0", expected_internet_exclusions)]),
	fixture_network_policy("coder-default-deny", {}, ["Ingress", "Egress"], [], []),
	fixture_network_policy("coder-workspace-deny-ingress", fixture_selector("In", workspace_names), ["Ingress"], [], []),
	fixture_network_policy("coder-control-plane", fixture_selector("In", control_plane_names), ["Ingress", "Egress"], fixture_control_plane_ingress, []),
	fixture_network_policy("coder-database", fixture_selector("In", database_client_names), ["Egress"], [], [fixture_database_rule]),
]

combined(policies) := [{"path": "rendered.yaml", "contents": policy} | some policy in policies]

bundle_with(replacement) := combined(array.concat(
	[policy | some policy in baseline_policies; policy.metadata.name != replacement.metadata.name],
	[replacement],
))

test_secure_policy_bundle_allowed if count(deny) == 0 with input as combined(baseline_policies)

test_fixture_internet_rule_shape_allowed if {
	rule := fixture_internet_rule("0.0.0.0/0", expected_internet_exclusions)
	approved_internet_rule(rule, allowed_internet_ports)
}

test_fixture_internet_rule_keys if {
	rule := fixture_internet_rule("0.0.0.0/0", expected_internet_exclusions)
	object.keys(rule) == {"ports", "to"}
	object.keys(rule.to[0]) == {"ipBlock"}
	object.keys(rule.to[0].ipBlock) == {"cidr", "except"}
}

test_fixture_internet_rule_ports if {
	rule := fixture_internet_rule("0.0.0.0/0", expected_internet_exclusions)
	ports := {port | some port in rule.ports}
	count(rule.ports) == count(ports)
	ports == {{"port": 443, "protocol": "TCP"}}
	allowed_internet_ports == {
		{"port": 80, "protocol": "TCP"},
		{"port": 443, "protocol": "TCP"},
		{"port": 19302, "protocol": "UDP"},
	}
	count(ports - allowed_internet_ports) == 0
	{"port": 443, "protocol": "TCP"} in ports
}

test_fixture_internet_rule_exclusions if {
	rule := fixture_internet_rule("0.0.0.0/0", expected_internet_exclusions)
	exclusions := {cidr | some cidr in rule.to[0].ipBlock.except}
	count(rule.to[0].ipBlock.except) == count(exclusions)
	count(required_internet_exclusions - exclusions) == 0
}

test_required_exclusion_constant_matches_render_contract if {
	required_internet_exclusions == expected_internet_exclusions
}

test_missing_required_policy_denied if {
	policies := [policy | some policy in baseline_policies; policy.metadata.name != "coder-default-deny"]
	"enforced render is missing required NetworkPolicy \"coder-default-deny\"" in deny with input as combined(policies)
}

test_unknown_policy_denied if {
	backdoor := fixture_network_policy("workspace-backdoor", {}, ["Ingress", "Egress"], [{}], [{}])
	"enforced render contains unreviewed NetworkPolicy \"workspace-backdoor\"" in deny with input as combined(array.concat(baseline_policies, [backdoor]))
}

test_list_wrapped_policy_denied if {
	backdoor := fixture_network_policy("workspace-backdoor", {}, ["Ingress", "Egress"], [{}], [{}])
	collection := {
		"apiVersion": "v1",
		"kind": "List",
		"items": [backdoor],
	}
	input_documents := array.concat(combined(baseline_policies), [{"path": "rendered.yaml", "contents": collection}])
	"network policy render contains unsupported manifest collection kind \"List\"" in deny with input as input_documents
}

test_network_policy_list_wrapped_policy_denied if {
	backdoor := fixture_network_policy("workspace-backdoor", {}, ["Ingress", "Egress"], [{}], [{}])
	collection := {
		"apiVersion": "networking.k8s.io/v1",
		"kind": "NetworkPolicyList",
		"items": [backdoor],
	}
	input_documents := array.concat(combined(baseline_policies), [{"path": "rendered.yaml", "contents": collection}])
	"network policy render contains unsupported manifest collection kind \"NetworkPolicyList\"" in deny with input as input_documents
}

test_policy_in_wrong_namespace_denied if {
	policy := object.union(baseline_policies[1], {"metadata": {"name": "coder-default-deny", "namespace": "wrong"}})
	"NetworkPolicy \"coder-default-deny\" must resolve to namespace coder" in deny with input as bundle_with(policy)
	"enforced render is missing required NetworkPolicy \"coder-default-deny\"" in deny with input as bundle_with(policy)
}

test_empty_workspace_selector_denied if {
	workspace := fixture_network_policy("coder-workspace", {}, ["Egress"], [], [fixture_internet_rule("0.0.0.0/0", expected_internet_exclusions)])
	"coder-workspace must select only the two workspace workload names" in deny with input as bundle_with(workspace)
}

test_negative_workspace_selector_denied if {
	workspace := fixture_network_policy("coder-workspace", fixture_selector("NotIn", ["coder"]), ["Egress"], [], [fixture_internet_rule("0.0.0.0/0", expected_internet_exclusions)])
	"coder-workspace must select only the two workspace workload names" in deny with input as bundle_with(workspace)
}

test_workspace_ingress_backdoor_denied if {
	workspace := fixture_network_policy("coder-workspace", fixture_selector("In", workspace_names), ["Ingress", "Egress"], [{}], [fixture_internet_rule("0.0.0.0/0", expected_internet_exclusions)])
	"coder-workspace must apply only to egress" in deny with input as bundle_with(workspace)
	"coder-workspace must not grant ingress" in deny with input as bundle_with(workspace)
}

test_workspace_missing_cluster_exclusion_denied if {
	exclusions := expected_internet_exclusions - {"172.32.0.0/12"}
	workspace := fixture_network_policy("coder-workspace", fixture_selector("In", workspace_names), ["Egress"], [], [fixture_internet_rule("0.0.0.0/0", exclusions)])
	"coder-workspace contains an unreviewed egress rule" in deny with input as bundle_with(workspace)
}

test_workspace_split_public_cidr_denied if {
	workspace := fixture_network_policy("coder-workspace", fixture_selector("In", workspace_names), ["Egress"], [], [fixture_internet_rule("0.0.0.0/1", expected_internet_exclusions)])
	"coder-workspace contains an unreviewed egress rule" in deny with input as bundle_with(workspace)
}

test_workspace_all_ports_to_database_denied if {
	rule := {"to": [{"ipBlock": {"cidr": "10.6.0.104/32"}}]}
	workspace := fixture_network_policy("coder-workspace", fixture_selector("In", workspace_names), ["Egress"], [], [rule])
	"NetworkPolicy \"coder-workspace\" can reach database CIDR \"10.6.0.104/32\"" in deny with input as bundle_with(workspace)
}

test_workspace_omitted_port_to_database_denied if {
	rule := {
		"ports": [{"protocol": "TCP"}],
		"to": [{"ipBlock": {"cidr": "10.6.0.104/32"}}],
	}
	workspace := fixture_network_policy("coder-workspace", fixture_selector("In", workspace_names), ["Egress"], [], [rule])
	"NetworkPolicy \"coder-workspace\" can reach database CIDR \"10.6.0.104/32\"" in deny with input as bundle_with(workspace)
}

test_workspace_port_range_to_database_denied if {
	rule := {
		"ports": [{"port": 5000, "endPort": 6000, "protocol": "TCP"}],
		"to": [{"ipBlock": {"cidr": "10.0.0.0/8"}}],
	}
	workspace := fixture_network_policy("coder-workspace", fixture_selector("In", workspace_names), ["Egress"], [], [rule])
	"NetworkPolicy \"coder-workspace\" can reach database CIDR \"10.6.0.104/32\"" in deny with input as bundle_with(workspace)
}

test_workspace_unreviewed_internal_peer_denied if {
	rule := {
		"ports": [{"port": 443, "protocol": "TCP"}],
		"to": [{"ipBlock": {"cidr": "10.7.0.0/16"}}],
	}
	workspace := fixture_network_policy("coder-workspace", fixture_selector("In", workspace_names), ["Egress"], [], [rule])
	"coder-workspace contains an unreviewed egress rule" in deny with input as bundle_with(workspace)
}

test_control_plane_unbounded_egress_denied if {
	policy := fixture_network_policy("coder-control-plane", fixture_selector("In", control_plane_names), ["Ingress", "Egress"], fixture_control_plane_ingress, [{}])
	"coder-control-plane contains an unreviewed egress rule" in deny with input as bundle_with(policy)
	"NetworkPolicy \"coder-control-plane\" grants database-capable egress to every destination" in deny with input as bundle_with(policy)
}

test_control_plane_unbounded_ingress_denied if {
	policy := fixture_network_policy("coder-control-plane", fixture_selector("In", control_plane_names), ["Ingress", "Egress"], [{}], [])
	"coder-control-plane ingress must contain only reviewed gateway and same-namespace peers" in deny with input as bundle_with(policy)
}

test_broad_database_selector_denied if {
	policy := fixture_network_policy("coder-database", fixture_selector("NotIn", ["coder-workspace"]), ["Egress"], [], [fixture_database_rule])
	"coder-database must select only coderd and the user data transfer Job" in deny with input as bundle_with(policy)
}

test_unbounded_database_policy_denied if {
	policy := fixture_network_policy("coder-database", fixture_selector("In", database_client_names), ["Egress"], [], [{}])
	"coder-database must allow only TCP/5432 to one database /32" in deny with input as bundle_with(policy)
}

test_user_data_transfer_backdoor_denied if {
	policy := fixture_network_policy("coder-user-data-transfer", {"matchLabels": {"app.kubernetes.io/name": "coder-user-data-transfer"}}, ["Egress"], [], [{}])
	"coder-user-data-transfer contains an unreviewed egress rule" in deny with input as combined(array.concat(baseline_policies, [policy]))
}

test_langsmith_proxy_egress_backdoor_denied if {
	policy := fixture_network_policy("langsmith-proxy-ingress", {"matchLabels": {"app.kubernetes.io/name": "langsmith-proxy"}}, ["Ingress", "Egress"], [{}], [{}])
	"langsmith-proxy-ingress must match the reviewed node ingress rule" in deny with input as combined(array.concat(baseline_policies, [policy]))
}

test_langsmith_proxy_unbounded_ingress_denied if {
	policy := fixture_network_policy("langsmith-proxy-ingress", {"matchLabels": {"app.kubernetes.io/name": "langsmith-proxy"}}, ["Ingress"], [{}], [])
	"langsmith-proxy-ingress must match the reviewed node ingress rule" in deny with input as combined(array.concat(baseline_policies, [policy]))
}

test_workspace_deny_policy_cannot_grant_ingress if {
	policy := fixture_network_policy("coder-workspace-deny-ingress", fixture_selector("In", workspace_names), ["Ingress"], [{}], [])
	"coder-workspace-deny-ingress must not reopen ingress" in deny with input as bundle_with(policy)
}
