package terraform.workspace

import rego.v1

allowed_resource_types := {
	"coder_agent",
	"coder_app",
	"coder_metadata",
	"coder_script",
	"kubernetes_deployment_v1",
	"kubernetes_persistent_volume_claim",
	"kubernetes_service_account_v1",
}

allowed_data_source_types := {
	"coder_parameter",
	"coder_workspace",
	"coder_workspace_owner",
}

allowed_provider_names := {"coder", "kubernetes"}

approved_provider_configs := {
	"coder": {"url": "${var.coder_url}"},
	"kubernetes": {"config_path": null},
}

approved_required_providers := {
	"coder": {
		"source": "coder/coder",
		"version": "2.18.0",
	},
	"kubernetes": {
		"source": "hashicorp/kubernetes",
		"version": "3.2.1",
	},
}

module_commit := "63892eae6a2264dc13683c3b9e6a305036e1aeb9"
secure_logger_module_source := sprintf("git::https://github.com/abridgeai/coder.git//modules/logger?ref=%s", [module_commit])

approved_module_sources := {
	"cpu_resources": sprintf("git::https://github.com/abridgeai/coder.git//modules/resources/cpu?ref=%s", [module_commit]),
	"dotfiles": "registry.coder.com/coder/dotfiles/coder",
	"git_utilities": sprintf("git::https://github.com/abridgeai/coder.git//modules/utilities/git?ref=%s", [module_commit]),
	"gpu_resources": sprintf("git::https://github.com/abridgeai/coder.git//modules/resources/gpu?ref=%s", [module_commit]),
	"ide_utilities": sprintf("git::https://github.com/abridgeai/coder.git//modules/utilities/ide?ref=%s", [module_commit]),
	"logger": secure_logger_module_source,
	"utd_bucket": sprintf("git::https://github.com/abridgeai/coder.git//modules/utilities/gcs-bucket?ref=%s", [module_commit]),
	"workspace_scripts": sprintf("git::https://github.com/abridgeai/coder.git//modules/utilities/workspace-scripts?ref=%s", [module_commit]),
}

profile_directories := {
	"cpu": "cpu-k8s",
	"gpu": "gpu-k8s",
	"phi": "phi-gpu-k8s",
}

approved_workspace_labels := {
	"cpu": {
		"app.kubernetes.io/instance": "coder-workspace-${data.coder_workspace.me.id}",
		"app.kubernetes.io/name": "coder-workspace",
		"app.kubernetes.io/part-of": "coder",
		"com.coder.resource": "true",
		"com.coder.user.id": "${data.coder_workspace_owner.me.id}",
		"com.coder.user.username": "${data.coder_workspace_owner.me.name}",
		"com.coder.workspace.id": "${data.coder_workspace.me.id}",
		"com.coder.workspace.name": "${data.coder_workspace.me.name}",
	},
	"gpu": {
		"app.kubernetes.io/instance": "coder-workspace-${data.coder_workspace.me.id}",
		"app.kubernetes.io/name": "coder-workspace",
		"app.kubernetes.io/part-of": "coder",
		"com.coder.resource": "true",
		"com.coder.user.id": "${data.coder_workspace_owner.me.id}",
		"com.coder.user.username": "${data.coder_workspace_owner.me.name}",
		"com.coder.workspace.id": "${data.coder_workspace.me.id}",
		"com.coder.workspace.name": "${data.coder_workspace.me.name}",
	},
	"phi": {
		"app.kubernetes.io/instance": "coder-phi-workspace-${data.coder_workspace.me.id}",
		"app.kubernetes.io/name": "coder-phi-workspace",
		"app.kubernetes.io/part-of": "coder",
		"com.coder.resource": "true",
		"com.coder.user.id": "${data.coder_workspace_owner.me.id}",
		"com.coder.user.username": "${data.coder_workspace_owner.me.name}",
		"com.coder.workspace.id": "${data.coder_workspace.me.id}",
		"com.coder.workspace.name": "${data.coder_workspace.me.name}",
		"com.coder.workspace.type": "phi",
	},
}

approved_template_annotations := {
	"cpu": `${merge(local.annotations,{"sidecar.istio.io/inject"="false"})}`,
	"gpu": `${merge(local.annotations,{"sidecar.istio.io/inject"="true""gke-gcsfuse/volumes"=module.utd_bucket.gcsfuse_annotation"traffic.sidecar.istio.io/excludeOutboundIPRanges"=module.utd_bucket.istio_ip_exclusion"proxy.istio.io/config"=jsonencode({holdApplicationUntilProxyStarts=true})})}`,
	"phi": `${merge(local.annotations,{"sidecar.istio.io/inject"="true""gke-gcsfuse/volumes"=module.utd_bucket.gcsfuse_annotation"traffic.sidecar.istio.io/excludeOutboundIPRanges"=module.utd_bucket.istio_ip_exclusion"proxy.istio.io/config"=jsonencode({holdApplicationUntilProxyStarts=true})})}`,
}

approved_pod_security_contexts := {
	"cpu": [{"fs_group": "1000", "run_as_non_root": true, "run_as_user": "1000"}],
	"gpu": [{"fs_group": 0, "run_as_non_root": false, "run_as_user": 0}],
	"phi": [{"fs_group": 0, "run_as_non_root": false, "run_as_user": 0}],
}

approved_dev_security_contexts := {
	"cpu": [{"run_as_user": "1000"}],
	"gpu": [{
		"allow_privilege_escalation": true,
		"read_only_root_filesystem": false,
		"run_as_user": 0,
	}],
	"phi": [{
		"allow_privilege_escalation": false,
		"capabilities": [{"drop": ["NET_RAW", "SETGID", "SETUID"]}],
		"read_only_root_filesystem": true,
		"run_as_user": 0,
	}],
}

approved_dev_envs := {
	"cpu": {
		{"name": "CODER_AGENT_TOKEN", "value": "${coder_agent.main.token}"},
		{"name": "CODER_AGENT_SUBSYSTEM", "value": "exectrace"},
		{"name": "GITHUB_TOKEN", "value": "${module.git_utilities.github_token}"},
		{"name": "JUDGES_OPENAI_BASE_URL", "value": "${var.judges_openai_base_url}"},
	},
	"gpu": {
		{"name": "CODER_AGENT_TOKEN", "value": "${coder_agent.main.token}"},
		{"name": "CODER_AGENT_SUBSYSTEM", "value": "exectrace"},
		{"name": "GITHUB_TOKEN", "value": "${module.git_utilities.github_token}"},
	},
	"phi": {
		{"name": "CODER_AGENT_BLOCK_FILE_TRANSFER", "value": "true"},
		{"name": "CODER_AGENT_TOKEN", "value": "${coder_agent.main.token}"},
		{"name": "GITHUB_TOKEN", "value": "${module.git_utilities.github_token}"},
		{
			"name": "LAUNCHDARKLY_NOTEGEN_READONLY_ACCESS_TOKEN",
			"value_from": [{"secret_key_ref": [{
				"key": "LAUNCHDARKLY_NOTEGEN_READONLY_ACCESS_TOKEN",
				"name": "coder-notegen-launchdarkly-secrets",
				"optional": true,
			}]}],
		},
		{"name": "PHI_COMPLIANCE_MODE", "value": "enabled"},
		{"name": "PHI_WORKSPACE", "value": "true"},
	},
}

approved_static_volumes := {
	"cpu": {{
		"name": "home",
		"persistent_volume_claim": [{"claim_name": "${kubernetes_persistent_volume_claim.home.metadata[0].name}"}],
	}},
	"gpu": {{
		"name": "home",
		"persistent_volume_claim": [{"claim_name": "${kubernetes_persistent_volume_claim.home.metadata[0].name}"}],
	}},
	"phi": {
		{
			"name": "home",
			"persistent_volume_claim": [{"claim_name": "${kubernetes_persistent_volume_claim.home.metadata[0].name}"}],
		},
		{"empty_dir": [{}], "name": "tmp-volume"},
	},
}

approved_dev_volume_mounts := {
	"cpu": {{"mount_path": "${local.home_dir}", "name": "home", "read_only": false}},
	"gpu": {{"mount_path": "${local.home_dir}", "name": "home", "read_only": false}},
	"phi": {
		{"mount_path": "${local.home_dir}", "name": "home", "read_only": false},
		{"mount_path": "/tmp", "name": "tmp-volume"},
	},
}

approved_dev_keys := {
	"cpu": {"command", "env", "image", "image_pull_policy", "name", "resources", "security_context", "volume_mount"},
	"gpu": {"command", "dynamic", "env", "image", "image_pull_policy", "name", "resources", "security_context", "volume_mount"},
	"phi": {"command", "dynamic", "env", "image", "image_pull_policy", "name", "resources", "security_context", "volume_mount"},
}

approved_pod_keys := {
	"cpu": {"affinity", "automount_service_account_token", "container", "node_selector", "security_context", "service_account_name", "volume"},
	"gpu": {"automount_service_account_token", "container", "dynamic", "node_selector", "security_context", "service_account_name", "volume"},
	"phi": {"automount_service_account_token", "container", "dynamic", "node_selector", "security_context", "service_account_name", "volume"},
}

approved_exectrace_container := {
	"command": [
		"/opt/exectrace",
		"--init-address", "127.0.0.1:56123",
		"--label", "workspace_id=${data.coder_workspace.me.id}",
		"--label", "workspace_name=${data.coder_workspace.me.name}",
		"--label", "user_id=${data.coder_workspace_owner.me.id}",
		"--label", "username=${data.coder_workspace_owner.me.name}",
		"--label", "user_email=${data.coder_workspace_owner.me.email}",
	],
	"image": "${module.logger.exectrace_image}",
	"image_pull_policy": "Always",
	"name": "exectrace",
	"security_context": [{"privileged": true, "run_as_group": "0", "run_as_user": "0"}],
}

utd_dynamic_volume := {
	"volume": [{
		"content": [{
			"csi": [{
				"driver": "${volume.value.csi.driver}",
				"volume_attributes": "${volume.value.csi.volume_attributes}",
			}],
			"name": "${volume.value.name}",
		}],
		"for_each": "${module.utd_bucket.volume != null ? [module.utd_bucket.volume] : []}",
	}],
}

utd_dynamic_volume_mount := {
	"volume_mount": [{
		"content": [{
			"mount_path": "${volume_mount.value.mount_path}",
			"name": "${volume_mount.value.name}",
			"read_only": "${volume_mount.value.read_only}",
		}],
		"for_each": "${module.utd_bucket.volume_mount != null ? [module.utd_bucket.volume_mount] : []}",
	}],
}

phi_dynamic_environment := [
	{
		"content": [{
			"name": "LANGSMITH_ENDPOINT",
			"value": "${var.langsmith_endpoint}",
		}],
		"for_each": "${!local.utd_bucket_enabled && var.langsmith_endpoint != \"\" ? [1] : []}",
	},
	{
		"content": [{
			"name": "LANGSMITH_ANNOTATION_ENDPOINT",
			"value": "${var.langsmith_annotation_endpoint}",
		}],
		"for_each": "${!local.utd_bucket_enabled && var.langsmith_annotation_endpoint != \"\" ? [1] : []}",
	},
]

allowed_pod_dynamic_blocks := {{}, utd_dynamic_volume}

allowed_dev_dynamic_blocks := {
	{},
	utd_dynamic_volume_mount,
	object.union(utd_dynamic_volume_mount, {"env": phi_dynamic_environment}),
}

digest_composed_base_images := {
	"${local.base_image_repo}@${local.base_image_digest}",
	"${local.base_image_repo}@${local.base_image_digests[local.image_suffix]}",
}

approved_service_account_expressions := {
	"${kubernetes_service_account_v1.workspace.metadata[0].name}",
	"${local.utd_bucket_enabled?(var.gpu_workspace_utd_service_account):(kubernetes_service_account_v1.workspace[0].metadata[0].name)}",
	"${local.utd_bucket_enabled?(var.phi_workspace_utd_service_account):(kubernetes_service_account_v1.workspace[0].metadata[0].name)}",
}

documents contains document if {
	some item in input
	document := item.contents
}

template_profiles contains profile if {
	some item in input
	path := object.get(item, "path", "")
	some profile, directory in profile_directories
	startswith(path, sprintf("templates/%s/", [directory]))
}

template_profile := profile if {
	count(template_profiles) == 1
	some profile in template_profiles
}

array_matches_set(values, expected) if {
	count(values) == count(expected)
	{value | some value in values} == expected
}

workspace_local_labels contains labels if {
	some document in documents
	some local_values in object.get(document, "locals", [])
	labels := object.get(local_values, "labels", null)
	labels != null
}

terraform_blocks contains block if {
	some document in documents
	some block in object.get(document, "terraform", [])
}

modules contains record if {
	some document in documents
	modules_by_name := object.get(document, "module", {})
	some name, module_values in modules_by_name
	some module in module_values
	record := {"name": name, "value": module}
}

modules_named(name) := {module |
	some record in modules
	record.name == name
	module := record.value
}

resources contains record if {
	some document in documents
	resources_by_type := object.get(document, "resource", {})
	some resource_type, resources_by_name in resources_by_type
	some name, resource_values in resources_by_name
	some resource in resource_values
	record := {"type": resource_type, "name": name, "value": resource}
}

providers contains record if {
	some document in documents
	providers_by_name := object.get(document, "provider", {})
	some name, provider_values in providers_by_name
	some provider in provider_values
	record := {"name": name, "value": provider}
}

providers_named(name) := {provider |
	some record in providers
	record.name == name
	provider := record.value
}

workspace_deployments contains record if {
	some document in documents
	resources := object.get(document, "resource", {})
	deployments_by_name := object.get(resources, "kubernetes_deployment_v1", {})
	some name
	some deployment in deployments_by_name[name]
	record := {"name": name, "value": deployment}
}

workspace_pod_specs contains record if {
	some deployment_record in workspace_deployments
	some deployment_spec in object.get(deployment_record.value, "spec", [])
	some template in object.get(deployment_spec, "template", [])
	some pod_spec in object.get(template, "spec", [])
	record := {"deployment": deployment_record.name, "value": pod_spec}
}

workspace_pod_templates contains record if {
	some deployment_record in workspace_deployments
	some deployment_spec in object.get(deployment_record.value, "spec", [])
	some template in object.get(deployment_spec, "template", [])
	record := {"deployment": deployment_record.name, "value": template}
}

workspace_service_accounts contains record if {
	some document in documents
	resources := object.get(document, "resource", {})
	service_accounts_by_name := object.get(resources, "kubernetes_service_account_v1", {})
	some name
	some service_account in service_accounts_by_name[name]
	record := {"name": name, "value": service_account}
}

base_image_references contains image if {
	some document in documents
	some local_values in object.get(document, "locals", [])
	image := object.get(local_values, "base_image", "")
	image != ""
}

base_image_digests contains digest if {
	some document in documents
	some local_values in object.get(document, "locals", [])
	digest := object.get(local_values, "base_image_digest", "")
	digest != ""
}

base_image_digests contains digest if {
	some document in documents
	some local_values in object.get(document, "locals", [])
	digests := object.get(local_values, "base_image_digests", {})
	some name
	digest := digests[name]
}

workspace_containers contains record if {
	some pod_record in workspace_pod_specs
	some container in object.get(pod_record.value, "container", [])
	record := {"kind": "container", "value": container}
}

workspace_containers contains record if {
	some pod_record in workspace_pod_specs
	some container in object.get(pod_record.value, "init_container", [])
	record := {"kind": "init_container", "value": container}
}

workspace_containers contains record if {
	some pod_record in workspace_pod_specs
	some container in object.get(pod_record.value, "ephemeral_container", [])
	record := {"kind": "ephemeral_container", "value": container}
}

variables_named(name) := {variable |
	some document in documents
	variables := object.get(document, "variable", {})
	some variable in object.get(variables, name, [])
}

normalize_expression(expression) := regex.replace(expression, `\s+`, "")

approved_container(container) if {
	container.name == "dev"
	container.image == "${local.base_image}"
}

approved_container(container) if {
	container.name == "exectrace"
	container.image == "${module.logger.exectrace_image}"
}

utd_variable_name(expression) := "gpu_workspace_utd_service_account" if {
	contains(expression, "var.gpu_workspace_utd_service_account")
}

utd_variable_name(expression) := "phi_workspace_utd_service_account" if {
	contains(expression, "var.phi_workspace_utd_service_account")
}

required_utd_precondition(name) := "${!local.utd_bucket_enabled||var.gpu_workspace_utd_service_account!=\"\"}" if {
	name == "gpu_workspace_utd_service_account"
}

required_utd_precondition(name) := "${!local.utd_bucket_enabled||var.phi_workspace_utd_service_account!=\"\"}" if {
	name == "phi_workspace_utd_service_account"
}

deployment_has_precondition(deployment, expected) if {
	some lifecycle in object.get(deployment, "lifecycle", [])
	some precondition in object.get(lifecycle, "precondition", [])
	normalize_expression(precondition.condition) == expected
}

deny contains msg if {
	count(workspace_deployments) != 1
	msg := sprintf("workspace template must define exactly one kubernetes_deployment_v1, found %d", [count(workspace_deployments)])
}

deny contains msg if {
	count(workspace_pod_specs) != 1
	msg := sprintf("workspace template must define exactly one deployment pod spec, found %d", [count(workspace_pod_specs)])
}

deny contains msg if {
	count(workspace_service_accounts) != 1
	msg := sprintf("workspace template must define exactly one kubernetes_service_account_v1, found %d", [count(workspace_service_accounts)])
}

deny contains msg if {
	some document in documents
	resources := object.get(document, "resource", {})
	some resource_type, resources_by_name in resources
	count(resources_by_name) > 0
	not resource_type in allowed_resource_types
	msg := sprintf("workspace template contains unapproved resource type %q", [resource_type])
}

deny contains msg if {
	some document in documents
	data_sources := object.get(document, "data", {})
	some data_source_type, sources_by_name in data_sources
	count(sources_by_name) > 0
	not data_source_type in allowed_data_source_types
	msg := sprintf("workspace template contains unapproved data source type %q", [data_source_type])
}

deny contains msg if {
	some document in documents
	providers := object.get(document, "provider", {})
	some provider_name, provider_blocks in providers
	count(provider_blocks) > 0
	not provider_name in allowed_provider_names
	msg := sprintf("workspace template contains unapproved provider block %q", [provider_name])
}

deny contains msg if {
	some name in allowed_provider_names
	count(providers_named(name)) != 1
	msg := sprintf("workspace template must define exactly one %s provider block", [name])
}

deny contains msg if {
	some record in providers
	record.name in allowed_provider_names
	record.value != approved_provider_configs[record.name]
	msg := sprintf("workspace provider %q has unapproved configuration", [record.name])
}

deny contains msg if {
	count(terraform_blocks) != 1
	msg := sprintf("workspace template must define exactly one terraform block, found %d", [count(terraform_blocks)])
}

deny contains msg if {
	some block in terraform_blocks
	object.keys(block) != {"required_providers"}
	msg := "workspace terraform block may contain only required_providers"
}

deny contains msg if {
	some block in terraform_blocks
	required := object.get(block, "required_providers", [])
	count(required) != 1
	msg := "workspace terraform block must define one reviewed required_providers block"
}

deny contains msg if {
	some block in terraform_blocks
	some required in object.get(block, "required_providers", [])
	required != approved_required_providers
	msg := "workspace required providers must match the reviewed sources and versions"
}

deny contains msg if {
	some record in modules
	not record.name in object.keys(approved_module_sources)
	msg := sprintf("workspace template contains unapproved module %q", [record.name])
}

deny contains msg if {
	some record in resources
	count(object.get(record.value, "provisioner", [])) > 0
	msg := sprintf("workspace resource %s.%s must not run provisioners", [record.type, record.name])
}

deny contains msg if {
	some record in modules
	record.name in object.keys(approved_module_sources)
	record.value.source != approved_module_sources[record.name]
	msg := sprintf("workspace module %q has unapproved source %q", [record.name, record.value.source])
}

deny contains msg if {
	some record in modules
	record.name == "dotfiles"
	object.get(record.value, "version", "") != "1.4.2"
	msg := "workspace dotfiles module must remain pinned to version 1.4.2"
}

deny contains msg if {
	count(template_profiles) != 1
	msg := sprintf("workspace policy input must resolve to exactly one reviewed template profile, found %d", [count(template_profiles)])
}

deny contains msg if {
	count(workspace_local_labels) != 1
	msg := sprintf("workspace template must define exactly one reviewed local labels map, found %d", [count(workspace_local_labels)])
}

deny contains msg if {
	profile := template_profile
	some labels in workspace_local_labels
	labels != approved_workspace_labels[profile]
	msg := sprintf("%s workspace local labels must match the reviewed network and admission identity", [profile])
}

deny contains msg if {
	count(workspace_pod_templates) != 1
	msg := sprintf("workspace template must define exactly one deployment pod template, found %d", [count(workspace_pod_templates)])
}

deny contains msg if {
	some template_record in workspace_pod_templates
	metadata := object.get(template_record.value, "metadata", [])
	count(metadata) != 1
	msg := "workspace deployment pod template must define exactly one metadata block"
}

deny contains msg if {
	profile := template_profile
	some template_record in workspace_pod_templates
	some metadata in object.get(template_record.value, "metadata", [])
	object.get(metadata, "labels", "") != "${local.labels}"
	msg := sprintf("%s workspace pod template labels must use local.labels", [profile])
}

deny contains msg if {
	profile := template_profile
	some template_record in workspace_pod_templates
	some metadata in object.get(template_record.value, "metadata", [])
	annotations := object.get(metadata, "annotations", "")
	normalize_expression(annotations) != approved_template_annotations[profile]
	msg := sprintf("%s workspace pod annotations must preserve the reviewed mesh controls", [profile])
}

deny contains msg if {
	some pod_record in workspace_pod_specs
	object.get(pod_record.value, "automount_service_account_token", null) != false
	msg := "workspace deployment must set automount_service_account_token = false"
}

deny contains msg if {
	some pod_record in workspace_pod_specs
	some field in {"host_ipc", "host_network", "host_pid"}
	object.get(pod_record.value, field, false) != false
	msg := sprintf("workspace deployment must not enable %s", [field])
}

deny contains msg if {
	some pod_record in workspace_pod_specs
	dynamic := object.get(pod_record.value, "dynamic", {})
	not dynamic in allowed_pod_dynamic_blocks
	msg := "workspace pod spec contains unapproved dynamic blocks"
}

deny contains msg if {
	some pod_record in workspace_pod_specs
	some volume in object.get(pod_record.value, "volume", [])
	count(object.get(volume, "host_path", [])) > 0
	msg := "workspace deployment must not mount host paths"
}

deny contains msg if {
	profile := template_profile
	some pod_record in workspace_pod_specs
	count(object.keys(pod_record.value) - approved_pod_keys[profile]) > 0
	msg := sprintf("%s workspace pod spec contains unreviewed fields", [profile])
}

deny contains msg if {
	profile := template_profile
	some pod_record in workspace_pod_specs
	object.get(pod_record.value, "security_context", []) != approved_pod_security_contexts[profile]
	msg := sprintf("%s workspace pod security context must match the reviewed settings", [profile])
}

deny contains msg if {
	profile := template_profile
	some pod_record in workspace_pod_specs
	not array_matches_set(object.get(pod_record.value, "volume", []), approved_static_volumes[profile])
	msg := sprintf("%s workspace pod volumes must match the reviewed PVC and temporary volumes", [profile])
}

deny contains msg if {
	some pod_record in workspace_pod_specs
	some container in object.get(pod_record.value, "container", [])
	container.name == "dev"
	some security_context in object.get(container, "security_context", [])
	object.get(security_context, "privileged", false) != false
	msg := "workspace dev container must not be privileged"
}

deny contains msg if {
	some pod_record in workspace_pod_specs
	service_account_name := object.get(pod_record.value, "service_account_name", "")
	not normalize_expression(service_account_name) in approved_service_account_expressions
	msg := sprintf("workspace deployment has an unapproved service_account_name expression: %q", [service_account_name])
}

deny contains msg if {
	some deployment_record in workspace_deployments
	some deployment_spec in object.get(deployment_record.value, "spec", [])
	some template in object.get(deployment_spec, "template", [])
	some pod_spec in object.get(template, "spec", [])
	service_account_name := object.get(pod_spec, "service_account_name", "")
	variable_name := utd_variable_name(service_account_name)
	expected := required_utd_precondition(variable_name)
	not deployment_has_precondition(deployment_record.value, expected)
	msg := sprintf("workspace deployment using %s must fail when UTD is enabled and the variable is empty", [variable_name])
}

deny contains msg if {
	some pod_record in workspace_pod_specs
	service_account_name := object.get(pod_record.value, "service_account_name", "")
	variable_name := utd_variable_name(service_account_name)
	count(variables_named(variable_name)) != 1
	msg := sprintf("workspace template must declare exactly one %s variable", [variable_name])
}

deny contains msg if {
	some pod_record in workspace_pod_specs
	service_account_name := object.get(pod_record.value, "service_account_name", "")
	variable_name := utd_variable_name(service_account_name)
	some variable in variables_named(variable_name)
	object.get(variable, "default", null) != ""
	msg := sprintf("%s must default to empty so the UTD precondition controls its use", [variable_name])
}

deny contains msg if {
	some service_account_record in workspace_service_accounts
	object.get(service_account_record.value, "automount_service_account_token", null) != false
	msg := "workspace ServiceAccount must set automount_service_account_token = false"
}

deny contains msg if {
	count(base_image_references) != 1
	msg := sprintf("workspace template must define exactly one base_image reference, found %d", [count(base_image_references)])
}

deny contains msg if {
	some image in base_image_references
	not image in digest_composed_base_images
	msg := sprintf("workspace base_image %q is not composed from the declared digest", [image])
}

deny contains msg if {
	count(base_image_digests) == 0
	msg := "workspace template must define at least one base image digest"
}

deny contains msg if {
	some digest in base_image_digests
	not regex.match(`^sha256:[a-f0-9]{64}$`, digest)
	msg := sprintf("workspace base image digest %q is invalid", [digest])
}

deny contains msg if {
	some pod_record in workspace_pod_specs
	containers := [container | some container in object.get(pod_record.value, "container", []); container.name == "dev"]
	count(containers) != 1
	msg := sprintf("workspace pod spec must define exactly one dev container, found %d", [count(containers)])
}

deny contains msg if {
	some record in workspace_containers
	not approved_container(record.value)
	msg := sprintf("workspace %s %q has unapproved image expression %q", [record.kind, object.get(record.value, "name", ""), object.get(record.value, "image", "")])
}

deny contains msg if {
	some record in workspace_containers
	record.kind != "container"
	msg := sprintf("workspace template contains unreviewed %s %q", [record.kind, object.get(record.value, "name", "")])
}

deny contains msg if {
	some record in workspace_containers
	record.value.name == "exectrace"
	record.value != approved_exectrace_container
	msg := "workspace exectrace container must match the reviewed privileged logger sidecar"
}

deny contains msg if {
	some record in workspace_containers
	record.value.name == "exectrace"
	count(modules_named("logger")) != 1
	msg := "workspace exectrace container requires the reviewed logger module"
}

deny contains msg if {
	some record in workspace_containers
	record.value.name == "dev"
	dynamic := object.get(record.value, "dynamic", {})
	not dynamic in allowed_dev_dynamic_blocks
	msg := "workspace dev container contains unapproved dynamic blocks"
}

deny contains msg if {
	profile := template_profile
	some record in workspace_containers
	record.value.name == "dev"
	object.keys(record.value) != approved_dev_keys[profile]
	msg := sprintf("%s workspace dev container contains unreviewed fields", [profile])
}

deny contains msg if {
	profile := template_profile
	some record in workspace_containers
	record.value.name == "dev"
	object.get(record.value, "security_context", []) != approved_dev_security_contexts[profile]
	msg := sprintf("%s workspace dev security context must match the reviewed settings", [profile])
}

deny contains msg if {
	profile := template_profile
	some record in workspace_containers
	record.value.name == "dev"
	not array_matches_set(object.get(record.value, "env", []), approved_dev_envs[profile])
	msg := sprintf("%s workspace dev environment must match the reviewed sources", [profile])
}

deny contains msg if {
	profile := template_profile
	some record in workspace_containers
	record.value.name == "dev"
	not array_matches_set(object.get(record.value, "volume_mount", []), approved_dev_volume_mounts[profile])
	msg := sprintf("%s workspace dev volume mounts must match the reviewed volumes", [profile])
}

deny contains msg if {
	some record in workspace_containers
	record.value.name != "dev"
	count(object.get(record.value, "dynamic", {})) > 0
	msg := sprintf("workspace %s %q must not contain dynamic blocks", [record.kind, record.value.name])
}
