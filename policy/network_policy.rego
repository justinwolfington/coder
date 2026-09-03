package kubernetes.network

import rego.v1

required_policy_names := {
	"coder-control-plane",
	"coder-database",
	"coder-default-deny",
	"coder-workspace",
	"coder-workspace-deny-ingress",
}

allowed_policy_names := required_policy_names | {
	"coder-user-data-transfer",
	"langsmith-annotation-proxy-ingress",
	"langsmith-proxy-ingress",
}

# These are the special-use, pod, service, and synthetic node ranges in the
# enforced CI renders. A broad Internet peer must exclude every one of them.
required_internet_exclusions := {
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

workspace_names := {"coder-phi-workspace", "coder-workspace"}

control_plane_names := {
	"coder",
	"coder-logstream-kube",
	"langsmith-annotation-proxy",
	"langsmith-proxy",
}

database_client_names := {"coder", "coder-user-data-transfer"}

allowed_gateway_cidrs := {
	"10.12.0.0/16",
	"35.191.0.0/16",
	"130.211.0.0/22",
}

allowed_internet_ports := {
	{"port": 80, "protocol": "TCP"},
	{"port": 443, "protocol": "TCP"},
	{"port": 19302, "protocol": "UDP"},
}

# These are the private HTTPS endpoints declared in the three environment
# values files. New private peers require an explicit policy review.
allowed_private_https_cidrs := {
	"10.6.0.3/32",
	"10.6.0.178/32",
	"10.6.2.223/32",
	"10.52.0.101/32",
	"10.52.0.138/32",
	"10.75.0.48/32",
	"10.75.0.104/32",
	"10.165.0.38/32",
	"10.165.0.80/32",
}

documents contains document if {
	some item in input
	document := item.contents
}

manifest_collections contains document if {
	some document in documents
	kind := object.get(document, "kind", "")
	is_string(kind)
	endswith(kind, "List")
	is_array(object.get(document, "items", null))
}

network_policies contains policy if {
	some document in documents
	document.apiVersion == "networking.k8s.io/v1"
	document.kind == "NetworkPolicy"
	policy := document
}

effective_namespace(policy) := object.get(policy.metadata, "namespace", "coder")

policies_named(name) := {policy |
	some policy in network_policies
	effective_namespace(policy) == "coder"
	policy.metadata.name == name
}

policy_exists(name) if count(policies_named(name)) > 0

array_is_set(values, expected) if {
	count(values) == count(expected)
	{value | some value in values} == expected
}

exact_positive_selector(policy, allowed_names) if {
	object.get(policy.spec.podSelector, "matchLabels", {}) == {}
	expressions := object.get(policy.spec.podSelector, "matchExpressions", [])
	count(expressions) == 1
	expression := expressions[0]
	object.keys(expression) == {"key", "operator", "values"}
	expression.key == "app.kubernetes.io/name"
	expression.operator == "In"
	array_is_set(expression.values, allowed_names)
}

exact_label_selector(policy, name) if {
	policy.spec.podSelector == {"matchLabels": {"app.kubernetes.io/name": name}}
}

exact_policy_types(policy, expected) if {
	array_is_set(object.get(policy.spec, "policyTypes", []), expected)
}

exact_rule(rule, expected_ports, expected_destinations) if {
	object.keys(rule) == {"ports", "to"}
	array_is_set(rule.ports, expected_ports)
	array_is_set(rule.to, expected_destinations)
}

approved_internet_rule(rule, permitted_ports) if {
	object.keys(rule) == {"ports", "to"}
	ports := {port | some port in rule.ports}
	count(rule.ports) == count(ports)
	count(ports - permitted_ports) == 0
	{"port": 443, "protocol": "TCP"} in ports
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

private_https_rule(rule) if {
	some cidr in allowed_private_https_cidrs
	exact_rule(
		rule,
		{{"port": 443, "protocol": "TCP"}},
		{{"ipBlock": {"cidr": cidr}}},
	)
}

dns_rule(rule) if {
	exact_rule(
		rule,
		{
			{"port": 53, "protocol": "TCP"},
			{"port": 53, "protocol": "UDP"},
		},
		{{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": "kube-system"}}}},
	)
}

workspace_broker_rule(rule) if {
	exact_rule(
		rule,
		{
			{"port": 80, "protocol": "TCP"},
			{"port": 8080, "protocol": "TCP"},
		},
		{{"podSelector": {"matchExpressions": [{
			"key": "app.kubernetes.io/name",
			"operator": "In",
			"values": ["coder", "langsmith-proxy", "langsmith-annotation-proxy"],
		}]}}},
	)
}

istiod_rule(rule) if {
	exact_rule(
		rule,
		{
			{"port": 15012, "protocol": "TCP"},
			{"port": 15014, "protocol": "TCP"},
		},
		{{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": "istio-system"}}}},
	)
}

workspace_metadata_rule(rule) if {
	object.keys(rule) == {"to"}
	array_is_set(rule.to, {
		{"ipBlock": {"cidr": "100.100.100.100/32"}},
		{"ipBlock": {"cidr": "169.254.20.10/32"}},
		{"ipBlock": {"cidr": "169.254.169.252/32"}},
		{"ipBlock": {"cidr": "169.254.169.254/32"}},
	})
}

control_plane_metadata_rule(rule) if {
	object.keys(rule) == {"to"}
	array_is_set(rule.to, {
		{"ipBlock": {"cidr": "169.254.20.10/32"}},
		{"ipBlock": {"cidr": "169.254.169.252/32"}},
		{"ipBlock": {"cidr": "169.254.169.254/32"}},
	})
}

eyes_service_rule(rule) if {
	exact_rule(
		rule,
		{{"port": 8000, "protocol": "TCP"}},
		{{
			"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": "eyes-v1"}},
			"podSelector": {"matchLabels": {
				"app.kubernetes.io/instance": "eyes-v1",
				"app.kubernetes.io/name": "eyes-new",
			}},
		}},
	)
}

llm_gateway_rule(rule) if {
	exact_rule(
		rule,
		{{"port": 80, "protocol": "TCP"}},
		{{
			"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": "llm-gateway"}},
			"podSelector": {"matchLabels": {
				"app": "llm-gateway-evals",
				"component": "gateway-service",
			}},
		}},
	)
}

allowed_workspace_rule(rule) if dns_rule(rule)
allowed_workspace_rule(rule) if approved_internet_rule(rule, allowed_internet_ports)
allowed_workspace_rule(rule) if private_https_rule(rule)
allowed_workspace_rule(rule) if workspace_broker_rule(rule)
allowed_workspace_rule(rule) if istiod_rule(rule)
allowed_workspace_rule(rule) if workspace_metadata_rule(rule)
allowed_workspace_rule(rule) if eyes_service_rule(rule)
allowed_workspace_rule(rule) if llm_gateway_rule(rule)

control_plane_https_rule(rule) if {
	exact_rule(
		rule,
		{{"port": 443, "protocol": "TCP"}},
		{{"ipBlock": {"cidr": "0.0.0.0/0"}}},
	)
}

same_namespace_rule(rule) if {
	object.keys(rule) == {"to"}
	array_is_set(rule.to, {{"podSelector": {}}})
}

allowed_control_plane_rule(rule) if dns_rule(rule)
allowed_control_plane_rule(rule) if control_plane_https_rule(rule)
allowed_control_plane_rule(rule) if same_namespace_rule(rule)
allowed_control_plane_rule(rule) if control_plane_metadata_rule(rule)

allowed_transfer_rule(rule) if dns_rule(rule)
allowed_transfer_rule(rule) if approved_internet_rule(rule, {{"port": 443, "protocol": "TCP"}})
allowed_transfer_rule(rule) if workspace_metadata_rule(rule)

database_cidrs contains cidr if {
	some policy in policies_named("coder-database")
	some rule in object.get(policy.spec, "egress", [])
	some destination in object.get(rule, "to", [])
	cidr := object.get(destination, ["ipBlock", "cidr"], "")
	cidr != ""
}

ip_block_excludes(block, target) if {
	some excluded in object.get(block, "except", [])
	net.cidr_contains(excluded, target)
}

ip_block_allows(block, target) if {
	net.cidr_contains(block.cidr, target)
	not ip_block_excludes(block, target)
}

rule_allows_database_port(rule) if count(object.get(rule, "ports", [])) == 0

rule_allows_database_port(rule) if {
	some port in object.get(rule, "ports", [])
	object.get(port, "protocol", "TCP") == "TCP"
	object.get(port, "port", null) == null
}

rule_allows_database_port(rule) if {
	some port in object.get(rule, "ports", [])
	object.get(port, "protocol", "TCP") == "TCP"
	is_string(port.port)
}

rule_allows_database_port(rule) if {
	some port in object.get(rule, "ports", [])
	object.get(port, "protocol", "TCP") == "TCP"
	is_number(port.port)
	end_port := object.get(port, "endPort", port.port)
	port.port <= 5432
	end_port >= 5432
}

exact_database_egress(policy) if {
	object.get(policy.spec, "ingress", []) == []
	egress := object.get(policy.spec, "egress", [])
	count(egress) == 1
	rule := egress[0]
	ports := object.get(rule, "ports", [])
	array_is_set(ports, {{"port": 5432, "protocol": "TCP"}})
	object.keys(rule) == {"ports", "to"}
	count(rule.to) == 1
	peer := rule.to[0]
	object.keys(peer) == {"ipBlock"}
	block := peer.ipBlock
	object.keys(block) == {"cidr"}
	regex.match(`^[0-9.]+/32$`, block.cidr)
	net.cidr_is_valid(block.cidr)
}

strict_ingress_only(policy) if {
	exact_policy_types(policy, {"Ingress"})
	object.get(policy.spec, "egress", []) == []
}

gateway_ingress_rule(rule) if {
	object.keys(rule) == {"from"}
	count(rule.from) > 0
	peers := {peer | some peer in rule.from}
	count(rule.from) == count(peers)
	every peer in rule.from {
		object.keys(peer) == {"ipBlock"}
		object.keys(peer.ipBlock) == {"cidr"}
		peer.ipBlock.cidr in allowed_gateway_cidrs
	}
}

same_namespace_ingress_rule(rule) if {
	object.keys(rule) == {"from"}
	array_is_set(rule.from, {{"podSelector": {}}})
}

allowed_control_plane_ingress_rule(rule) if gateway_ingress_rule(rule)
allowed_control_plane_ingress_rule(rule) if same_namespace_ingress_rule(rule)

control_plane_ingress_complete(policy) if {
	ingress := object.get(policy.spec, "ingress", [])
	count(ingress) == 2
	every rule in ingress {
		allowed_control_plane_ingress_rule(rule)
	}
	some gateway_rule in ingress
	gateway_ingress_rule(gateway_rule)
	some namespace_rule in ingress
	same_namespace_ingress_rule(namespace_rule)
}

proxy_ingress_rule(rule) if {
	object.keys(rule) == {"from", "ports"}
	array_is_set(rule.ports, {
		{"port": 8080, "protocol": "TCP"},
		{"port": 15006, "protocol": "TCP"},
	})
	array_is_set(rule.from, {{"ipBlock": {"cidr": "10.6.0.0/16"}}})
}

strict_proxy_ingress(policy) if {
	strict_ingress_only(policy)
	ingress := object.get(policy.spec, "ingress", [])
	count(ingress) == 1
	proxy_ingress_rule(ingress[0])
}

deny contains msg if {
	some collection in manifest_collections
	msg := sprintf("network policy render contains unsupported manifest collection kind %q", [collection.kind])
}

deny contains msg if {
	some policy in network_policies
	effective_namespace(policy) != "coder"
	msg := sprintf("NetworkPolicy %q must resolve to namespace coder", [policy.metadata.name])
}

deny contains msg if {
	some name in required_policy_names
	not policy_exists(name)
	msg := sprintf("enforced render is missing required NetworkPolicy %q", [name])
}

deny contains msg if {
	some name in allowed_policy_names
	count(policies_named(name)) > 1
	msg := sprintf("enforced render contains duplicate NetworkPolicy %q", [name])
}

deny contains msg if {
	some policy in network_policies
	not policy.metadata.name in allowed_policy_names
	msg := sprintf("enforced render contains unreviewed NetworkPolicy %q", [policy.metadata.name])
}

deny contains msg if {
	some policy in policies_named("coder-workspace")
	not exact_positive_selector(policy, workspace_names)
	msg := "coder-workspace must select only the two workspace workload names"
}

deny contains msg if {
	some policy in policies_named("coder-workspace")
	not exact_policy_types(policy, {"Egress"})
	msg := "coder-workspace must apply only to egress"
}

deny contains msg if {
	some policy in policies_named("coder-workspace")
	object.get(policy.spec, "ingress", []) != []
	msg := "coder-workspace must not grant ingress"
}

deny contains msg if {
	some policy in policies_named("coder-workspace")
	some rule in object.get(policy.spec, "egress", [])
	not allowed_workspace_rule(rule)
	msg := "coder-workspace contains an unreviewed egress rule"
}

deny contains msg if {
	some policy in policies_named("coder-control-plane")
	not exact_positive_selector(policy, control_plane_names)
	msg := "coder-control-plane must select only the named control-plane workloads"
}

deny contains msg if {
	some policy in policies_named("coder-control-plane")
	not exact_policy_types(policy, {"Egress", "Ingress"})
	msg := "coder-control-plane must apply to ingress and egress"
}

deny contains msg if {
	some policy in policies_named("coder-control-plane")
	some rule in object.get(policy.spec, "egress", [])
	not allowed_control_plane_rule(rule)
	msg := "coder-control-plane contains an unreviewed egress rule"
}

deny contains msg if {
	some policy in policies_named("coder-control-plane")
	not control_plane_ingress_complete(policy)
	msg := "coder-control-plane ingress must contain only reviewed gateway and same-namespace peers"
}

deny contains msg if {
	some policy in policies_named("coder-database")
	not exact_positive_selector(policy, database_client_names)
	msg := "coder-database must select only coderd and the user data transfer Job"
}

deny contains msg if {
	some policy in policies_named("coder-database")
	not exact_policy_types(policy, {"Egress"})
	msg := "coder-database must apply only to egress"
}

deny contains msg if {
	some policy in policies_named("coder-database")
	not exact_database_egress(policy)
	msg := "coder-database must allow only TCP/5432 to one database /32"
}

deny contains msg if {
	some policy in network_policies
	policy.metadata.name != "coder-database"
	some rule in object.get(policy.spec, "egress", [])
	rule_allows_database_port(rule)
	count(object.get(rule, "to", [])) == 0
	msg := sprintf("NetworkPolicy %q grants database-capable egress to every destination", [policy.metadata.name])
}

deny contains msg if {
	some policy in network_policies
	policy.metadata.name != "coder-database"
	some rule in object.get(policy.spec, "egress", [])
	rule_allows_database_port(rule)
	some destination in object.get(rule, "to", [])
	block := object.get(destination, "ipBlock", {})
	object.get(block, "cidr", "") != ""
	some database_cidr in database_cidrs
	ip_block_allows(block, database_cidr)
	msg := sprintf("NetworkPolicy %q can reach database CIDR %q", [policy.metadata.name, database_cidr])
}

deny contains msg if {
	some policy in policies_named("coder-default-deny")
	policy.spec.podSelector != {}
	msg := "coder-default-deny must select every pod"
}

deny contains msg if {
	some policy in policies_named("coder-default-deny")
	not exact_policy_types(policy, {"Egress", "Ingress"})
	msg := "coder-default-deny must deny ingress and egress"
}

deny contains msg if {
	some policy in policies_named("coder-default-deny")
	count(object.get(policy.spec, "ingress", [])) + count(object.get(policy.spec, "egress", [])) > 0
	msg := "coder-default-deny must not reopen traffic"
}

deny contains msg if {
	some policy in policies_named("coder-workspace-deny-ingress")
	not exact_positive_selector(policy, workspace_names)
	msg := "coder-workspace-deny-ingress must select only workspaces"
}

deny contains msg if {
	some policy in policies_named("coder-workspace-deny-ingress")
	not strict_ingress_only(policy)
	msg := "coder-workspace-deny-ingress must remain ingress-only"
}

deny contains msg if {
	some policy in policies_named("coder-workspace-deny-ingress")
	count(object.get(policy.spec, "ingress", [])) > 0
	msg := "coder-workspace-deny-ingress must not reopen ingress"
}

deny contains msg if {
	some policy in policies_named("coder-user-data-transfer")
	not exact_label_selector(policy, "coder-user-data-transfer")
	msg := "coder-user-data-transfer must select only the migration Job"
}

deny contains msg if {
	some policy in policies_named("coder-user-data-transfer")
	not exact_policy_types(policy, {"Egress"})
	msg := "coder-user-data-transfer must apply only to egress"
}

deny contains msg if {
	some policy in policies_named("coder-user-data-transfer")
	some rule in object.get(policy.spec, "egress", [])
	not allowed_transfer_rule(rule)
	msg := "coder-user-data-transfer contains an unreviewed egress rule"
}

deny contains msg if {
	some policy in policies_named("langsmith-proxy-ingress")
	not exact_label_selector(policy, "langsmith-proxy")
	msg := "langsmith-proxy-ingress must select only the LangSmith proxy"
}

deny contains msg if {
	some policy in policies_named("langsmith-proxy-ingress")
	not strict_proxy_ingress(policy)
	msg := "langsmith-proxy-ingress must match the reviewed node ingress rule"
}

deny contains msg if {
	some policy in policies_named("langsmith-annotation-proxy-ingress")
	not exact_label_selector(policy, "langsmith-annotation-proxy")
	msg := "langsmith-annotation-proxy-ingress must select only the annotation proxy"
}

deny contains msg if {
	some policy in policies_named("langsmith-annotation-proxy-ingress")
	not strict_proxy_ingress(policy)
	msg := "langsmith-annotation-proxy-ingress must match the reviewed node ingress rule"
}
