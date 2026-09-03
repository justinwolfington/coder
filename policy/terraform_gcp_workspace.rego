package terraform.gcp_workspace

import rego.v1

allowed_document_keys := {"data", "locals", "module", "moved", "output", "provider", "resource", "terraform", "variable"}

approved_required_providers := {
	"coder": {"source": "coder/coder", "version": "2.18.0"},
	"google": {"source": "hashicorp/google", "version": "7.42.0"},
}

approved_provider_configs := {
	"coder": {"url": "${var.coder_url}"},
	"google": {"project": "${local.env_config.project_id}", "zone": "${var.zone}"},
}

module_commit := "63892eae6a2264dc13683c3b9e6a305036e1aeb9"

approved_module_sources := {
	"code-server": "registry.coder.com/coder/code-server/coder",
	"dotfiles": "registry.coder.com/coder/dotfiles/coder",
	"git_utilities": sprintf("git::https://github.com/abridgeai/coder.git//modules/utilities/git?ref=%s", [module_commit]),
	"gpu_resources": sprintf("git::https://github.com/abridgeai/coder.git//modules/resources/gpu?ref=%s", [module_commit]),
	"ide_modules": sprintf("git::https://github.com/abridgeai/coder.git//modules/utilities/ide?ref=%s", [module_commit]),
}

approved_module_versions := {
	"code-server": "1.5.2",
	"dotfiles": "1.4.2",
}

approved_module_configs := {
	"code-server": {
		"agent_id": "${coder_agent.main.id}",
		"count": "${data.coder_workspace.me.start_count}",
		"folder": "/home/${lower(data.coder_workspace_owner.me.name)}",
		"source": approved_module_sources["code-server"],
		"version": approved_module_versions["code-server"],
	},
	"dotfiles": {
		"agent_id": "${coder_agent.main.id}",
		"count": "${data.coder_workspace.me.start_count}",
		"source": approved_module_sources.dotfiles,
		"version": approved_module_versions.dotfiles,
	},
	"git_utilities": {
		"agent_id": "${coder_agent.main.id}",
		"repo_url": "",
		"require_github_auth": false,
		"should_clone": false,
		"source": approved_module_sources.git_utilities,
		"start_count": "${data.coder_workspace.me.start_count}",
	},
	"gpu_resources": {
		"source": approved_module_sources.gpu_resources,
	},
	"ide_modules": {
		"agent_id": "${coder_agent.main.id}",
		"source": approved_module_sources.ide_modules,
		"start_count": "${data.coder_workspace.me.start_count}",
	},
}

approved_resource_names := {
	"coder_agent": {"main"},
	"coder_agent_instance": {"main"},
	"coder_metadata": {"workspace_info"},
	"google_compute_disk": {"home_disk", "vm_boot_disk"},
	"google_compute_instance": {"workspace"},
}

approved_data_source_names := {
	"coder_parameter": {"cpu_machine_type", "disk_size", "dl_image", "environment", "gpu_type"},
	"coder_workspace": {"me"},
	"coder_workspace_owner": {"me"},
}

approved_outputs := {
	"dl_image": {
		"description": "Deep learning image selected for the workspace",
		"value": "${data.coder_parameter.dl_image.value}",
	},
	"environment": {
		"description": "Environment configuration being used",
		"value": "${data.coder_parameter.environment.value}",
	},
	"gpu_config": {
		"description": "GPU configuration selected for the workspace",
		"value": "${data.coder_parameter.gpu_type.value}",
	},
	"instance_name": {
		"description": "Name of the created GCP compute instance",
		"value": "${google_compute_instance.workspace.name}",
	},
	"internal_ip": {
		"description": "Internal IP address of the compute instance",
		"value": "${google_compute_instance.workspace.network_interface[0].network_ip}",
	},
	"machine_type": {
		"description": "Machine type used for the compute instance",
		"value": "${local.machine_type}",
	},
	"network_config": {
		"description": "Network configuration for the selected environment",
		"value": {
			"network": "${local.env_config.network}",
			"subnetwork": "${local.env_config.subnetwork}",
		},
	},
	"project_id": {
		"description": "GCP project ID for the selected environment",
		"value": "${local.env_config.project_id}",
	},
	"zone": {
		"description": "GCP zone where the instance is running",
		"value": "${var.zone}",
	},
}

approved_variables := {
	"coder_url": {
		"default": "",
		"description": "Coder access URL for the provider.",
		"type": "${string}",
	},
	"disk_size": {
		"default": 100,
		"description": "Boot disk size in GB",
		"type": "${number}",
		"validation": [{
			"condition": "${var.disk_size >= 50 && var.disk_size <= 2000}",
			"error_message": "Disk size must be between 50-2000 GB.",
		}],
	},
	"zone": {
		"default": "us-central1-a",
		"description": "Google Cloud zone for the compute instance",
		"type": "${string}",
		"validation": [{
			"condition": `${contains([
      "us-central1-a", "us-central1-b", "us-central1-c", "us-central1-f"
    ], var.zone)}`,
			"error_message": "Zone must be in us-central1 region.",
		}],
	},
}

approved_environment_configs := {
	"development": {
		"network": "development-vpc",
		"project_id": "client-dev-e301d",
		"service_account_email": "467615904598-compute@developer.gserviceaccount.com",
		"subnetwork": "development-ml",
	},
	"production": {
		"network": "production-vpc",
		"project_id": "abridge-client-prod",
		"service_account_email": "146004356782-compute@developer.gserviceaccount.com",
		"subnetwork": "production-ml",
	},
	"staging": {
		"network": "staging-vpc",
		"project_id": "abridge-client-staging",
		"service_account_email": "959950361719-compute@developer.gserviceaccount.com",
		"subnetwork": "staging-ml",
	},
}

approved_dl_images := {
	"common-cu128-ubuntu-2204-nvidia-570-v20260320": "projects/deeplearning-platform-release/global/images/common-cu128-ubuntu-2204-nvidia-570-v20260320",
	"common-cu129-ubuntu-2204-nvidia-580-v20260611": "projects/deeplearning-platform-release/global/images/common-cu129-ubuntu-2204-nvidia-580-v20260611",
	"common-cu129-ubuntu-2204-nvidia-580-v20260804": "projects/deeplearning-platform-release/global/images/common-cu129-ubuntu-2204-nvidia-580-v20260804",
	"pytorch-2-7-cu128-ubuntu-2204-nvidia-570-v20260320": "projects/deeplearning-platform-release/global/images/pytorch-2-7-cu128-ubuntu-2204-nvidia-570-v20260320",
	"pytorch-2-9-cu129-ubuntu-2204-nvidia-580-v20260611": "projects/deeplearning-platform-release/global/images/pytorch-2-9-cu129-ubuntu-2204-nvidia-580-v20260611",
	"pytorch-2-9-cu129-ubuntu-2204-nvidia-580-v20260730": "projects/deeplearning-platform-release/global/images/pytorch-2-9-cu129-ubuntu-2204-nvidia-580-v20260730",
	"ubuntu-2404-noble-amd64-v20260517": "projects/ubuntu-os-cloud/global/images/ubuntu-2404-noble-amd64-v20260517",
	"ubuntu-2404-noble-amd64-v20260723": "projects/ubuntu-os-cloud/global/images/ubuntu-2404-noble-amd64-v20260723",
}

approved_env_config_expression := "${local.environment_configs[data.coder_parameter.environment.value]}"
approved_image_expression := "${local.dl_images[data.coder_parameter.dl_image.value]}"
approved_startup_script_expression := `${templatefile("${path.module}/startup.tftpl", {
    username  = lower(data.coder_workspace_owner.me.name)
    useremail = data.coder_workspace_owner.me.email
    gpu_type  = data.coder_parameter.gpu_type.value
    dl_image  = data.coder_parameter.dl_image.value
  })}`

approved_coder_agent := {
	"arch": "amd64",
	"auth": "google-instance-identity",
	"dynamic": {"metadata": [
		{
			"content": [{
				"display_name": "GPU Usage",
				"interval": 15,
				"key": "gpu_usage",
				"script": "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits || echo 'N/A'",
				"timeout": 10,
			}],
			"for_each": "${local.gpu_config.gpu_count > 0 ? [1] : []}",
		},
		{
			"content": [{
				"display_name": "GPU Memory",
				"interval": 15,
				"key": "gpu_memory",
				"script": "nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits || echo 'N/A'",
				"timeout": 10,
			}],
			"for_each": "${local.gpu_config.gpu_count > 0 ? [1] : []}",
		},
	]},
	"env": {
		"HOME": "/home/${lower(data.coder_workspace_owner.me.name)}",
		"USER": "${lower(data.coder_workspace_owner.me.name)}",
	},
	"metadata": [
		{
			"display_name": "CPU Usage",
			"interval": 15,
			"key": "cpu_usage",
			"script": "coder stat cpu",
			"timeout": 10,
		},
		{
			"display_name": "Memory Usage",
			"interval": 15,
			"key": "memory_usage",
			"script": "coder stat mem",
			"timeout": 10,
		},
	],
	"os": "linux",
	"startup_script": "${local.startup_script}",
}

approved_coder_metadata := {
	"count": "${data.coder_workspace.me.start_count}",
	"daily_cost": "${local.gpu_config.gpu_count > 0 ? lookup(module.gpu_resources.gpu_cost_per_unit, local.gpu_config.gpu_type, 0) * local.gpu_config.gpu_count : lookup(local.cpu_cost_per_day, local.machine_type, 0)}",
	"item": [
		{
			"key": "Machine Type",
			"value": "${local.machine_type}",
		},
		{
			"key": "GPU Configuration",
			"value": "${local.gpu_config.gpu_count > 0 ? \"${local.gpu_config.gpu_count}x ${local.gpu_config.gpu_type}\" : \"CPU Only\"}",
		},
		{
			"key": "Deep Learning Image",
			"value": "${data.coder_parameter.dl_image.value}",
		},
		{
			"key": "Zone",
			"value": "${var.zone}",
		},
		{
			"key": "Disk Size",
			"value": "${data.coder_parameter.disk_size.value} GB (Recommended: ${local.recommended_disk_size} GB for %{if local.gpu_config.gpu_count > 0}GPU%{else}CPU%{endif} workloads)",
		},
		{
			"key": "Local SSDs",
			"value": "${local.gpu_config.local_ssd_description}",
		},
		{
			"key": "Reservation",
			"value": "Shared reservations used automatically when available",
		},
		{
			"key": "Reservation Strategy",
			"value": "${local.selected_reservation != null && local.selected_reservation != \"\" ? \"Specific reservation: ${local.selected_reservation}\" : \"Any available reservation (cost-optimized)\"}",
		},
		{
			"key": "Internal IP",
			"value": "${google_compute_instance.workspace.network_interface[0].network_ip}",
		},
	],
	"resource_id": "${google_compute_instance.workspace.id}",
}

approved_instance_keys := {
	"attached_disk",
	"boot_disk",
	"desired_status",
	"dynamic",
	"labels",
	"machine_type",
	"metadata",
	"metadata_startup_script",
	"name",
	"network_interface",
	"scheduling",
	"service_account",
	"shielded_instance_config",
	"zone",
}

approved_instance_boot_disk := [{
	"auto_delete": false,
	"source": "${google_compute_disk.vm_boot_disk.self_link}",
}]

approved_instance_attached_disk := [{
	"device_name": "home",
	"mode": "READ_WRITE",
	"source": "${google_compute_disk.home_disk.self_link}",
}]

approved_instance_startup_script := "#!/bin/bash\nmkdir -p /home/${lower(data.coder_workspace_owner.me.name)}\n${coder_agent.main.init_script}\n"

approved_instance_service_account := [{
	"email": "${local.env_config.service_account_email}",
	"scopes": [
		"https://www.googleapis.com/auth/devstorage.read_only",
		"https://www.googleapis.com/auth/logging.write",
		"https://www.googleapis.com/auth/monitoring.write",
		"https://www.googleapis.com/auth/service.management.readonly",
		"https://www.googleapis.com/auth/servicecontrol",
		"https://www.googleapis.com/auth/trace.append",
	],
}]

approved_instance_network := [{
	"network": "projects/${local.env_config.project_id}/global/networks/${local.env_config.network}",
	"nic_type": "GVNIC",
	"subnetwork": "projects/${local.env_config.project_id}/regions/us-central1/subnetworks/${local.env_config.subnetwork}",
}]

approved_instance_metadata := {
	"block-project-ssh-keys": "TRUE",
	"enable-guest-attributes": "TRUE",
	"enable-osconfig": "TRUE",
	"enable-oslogin": "TRUE",
}

approved_shielded_config := [{
	"enable_integrity_monitoring": true,
	"enable_secure_boot": false,
	"enable_vtpm": true,
}]

approved_moved_block := {
	"from": "${google_compute_instance.workspace[0]}",
	"to": "${google_compute_instance.workspace}",
}

documents := [document |
	some item in input
	document := item.contents
]

terraform_blocks := [block |
	some document in documents
	some block in object.get(document, "terraform", [])
]

providers := [record |
	some document_index, item in input
	document := item.contents
	providers_by_name := object.get(document, "provider", {})
	some name, values in providers_by_name
	some value_index, value in values
	record := {"document_index": document_index, "name": name, "value": value, "value_index": value_index}
]

modules := [record |
	some document_index, item in input
	document := item.contents
	modules_by_name := object.get(document, "module", {})
	some name, values in modules_by_name
	some value_index, value in values
	record := {"document_index": document_index, "name": name, "value": value, "value_index": value_index}
]

resources := [record |
	some document_index, item in input
	document := item.contents
	resources_by_type := object.get(document, "resource", {})
	some resource_type, resources_by_name in resources_by_type
	some name, values in resources_by_name
	some value_index, value in values
	record := {"document_index": document_index, "type": resource_type, "name": name, "value": value, "value_index": value_index}
]

data_sources := [record |
	some document_index, item in input
	document := item.contents
	sources_by_type := object.get(document, "data", {})
	some source_type, sources_by_name in sources_by_type
	some name, values in sources_by_name
	some value_index, value in values
	record := {"document_index": document_index, "type": source_type, "name": name, "value": value, "value_index": value_index}
]

outputs := [record |
	some document_index, item in input
	document := item.contents
	outputs_by_name := object.get(document, "output", {})
	some name, values in outputs_by_name
	some value_index, value in values
	record := {"document_index": document_index, "name": name, "value": value, "value_index": value_index}
]

variables := [record |
	some document_index, item in input
	document := item.contents
	variables_by_name := object.get(document, "variable", {})
	some name, values in variables_by_name
	some value_index, value in values
	record := {"document_index": document_index, "name": name, "value": value, "value_index": value_index}
]

local_assignments(key) := [value |
	some document in documents
	some local_values in object.get(document, "locals", [])
	value := object.get(local_values, key, null)
	value != null
]

environment_configs := local_assignments("environment_configs")
env_configs := local_assignments("env_config")
dl_images := local_assignments("dl_images")
images := local_assignments("image")
startup_scripts := local_assignments("startup_script")

moved_blocks := [block |
	some document in documents
	some block in object.get(document, "moved", [])
]

instances := [instance |
	some record in resources
	record.type == "google_compute_instance"
	record.name == "workspace"
	instance := record.value
]

resource_identities := {sprintf("%s.%s", [record.type, record.name]) | some record in resources}
approved_resource_identities := {sprintf("%s.%s", [resource_type, name]) |
	some resource_type, names in approved_resource_names
	some name in names
}

data_source_identities := {sprintf("%s.%s", [record.type, record.name]) | some record in data_sources}
approved_data_source_identities := {sprintf("%s.%s", [source_type, name]) |
	some source_type, names in approved_data_source_names
	some name in names
}

dangerous_local_file_expression(value) if {
	is_string(value)
	without_block_comments := regex.replace(value, `(?s)/\*.*?\*/`, "")
	without_line_comments := regex.replace(without_block_comments, `(?m)//[^\n]*`, "")
	without_comments := regex.replace(without_line_comments, `(?m)#[^\n]*`, "")
	regex.match(`(?i)\b(file|filebase64|fileexists|fileset|templatefile)\s*\(`, without_comments)
	value != approved_startup_script_expression
}

deny contains msg if {
	some document in documents
	some key in object.keys(document)
	not key in allowed_document_keys
	msg := sprintf("GCP workspace template contains unapproved top-level block %q", [key])
}

deny contains msg if {
	some document in documents
	some value
	walk(document, [_, value])
	dangerous_local_file_expression(value)
	msg := "GCP workspace template must not read local files"
}

deny contains msg if {
	count(terraform_blocks) != 1
	msg := sprintf("GCP workspace template must define exactly one terraform block, found %d", [count(terraform_blocks)])
}

deny contains msg if {
	some block in terraform_blocks
	block != {"required_providers": [approved_required_providers]}
	msg := "GCP workspace required providers must match the reviewed sources and versions"
}

deny contains msg if {
	count(providers) != 2
	msg := sprintf("GCP workspace template must define exactly two reviewed providers, found %d", [count(providers)])
}

deny contains msg if {
	provider_names := {record.name | some record in providers}
	provider_names != object.keys(approved_provider_configs)
	msg := "GCP workspace provider identities must exactly match the reviewed set"
}

deny contains msg if {
	some name in object.keys(approved_provider_configs)
	matching := [record | some record in providers; record.name == name]
	count(matching) != 1
	msg := sprintf("GCP workspace provider %q must be defined exactly once", [name])
}

deny contains msg if {
	some record in providers
	not record.name in object.keys(approved_provider_configs)
	msg := sprintf("GCP workspace template contains unapproved provider %q", [record.name])
}

deny contains msg if {
	some record in providers
	record.name in object.keys(approved_provider_configs)
	record.value != approved_provider_configs[record.name]
	msg := sprintf("GCP workspace provider %q has unapproved configuration", [record.name])
}

deny contains msg if {
	count(modules) != count(approved_module_sources)
	msg := sprintf("GCP workspace template must define exactly %d reviewed modules, found %d", [count(approved_module_sources), count(modules)])
}

deny contains msg if {
	module_names := {record.name | some record in modules}
	module_names != object.keys(approved_module_sources)
	msg := "GCP workspace module identities must exactly match the reviewed set"
}

deny contains msg if {
	some name in object.keys(approved_module_sources)
	matching := [record | some record in modules; record.name == name]
	count(matching) != 1
	msg := sprintf("GCP workspace module %q must be defined exactly once", [name])
}

deny contains msg if {
	some record in modules
	not record.name in object.keys(approved_module_sources)
	msg := sprintf("GCP workspace template contains unapproved module %q", [record.name])
}

deny contains msg if {
	some record in modules
	record.name in object.keys(approved_module_sources)
	source := object.get(record.value, "source", "")
	source != approved_module_sources[record.name]
	msg := sprintf("GCP workspace module %q has unapproved source %q", [record.name, source])
}

deny contains msg if {
	some record in modules
	record.name in object.keys(approved_module_versions)
	object.get(record.value, "version", "") != approved_module_versions[record.name]
	msg := sprintf("GCP workspace module %q must remain pinned to version %s", [record.name, approved_module_versions[record.name]])
}

deny contains msg if {
	some record in modules
	record.name in object.keys(approved_module_configs)
	record.value != approved_module_configs[record.name]
	msg := sprintf("GCP workspace module %q must preserve the reviewed inputs", [record.name])
}

deny contains msg if {
	count(resources) != 6
	msg := sprintf("GCP workspace template must define exactly six reviewed resources, found %d", [count(resources)])
}

deny contains msg if {
	resource_identities != approved_resource_identities
	msg := "GCP workspace resource identities must exactly match the reviewed set"
}

deny contains msg if {
	some resource_type, names in approved_resource_names
	some name in names
	matching := [record |
		some record in resources
		record.type == resource_type
		record.name == name
	]
	count(matching) != 1
	msg := sprintf("GCP workspace resource %s.%s must be defined exactly once", [resource_type, name])
}

deny contains msg if {
	some record in resources
	not record.type in object.keys(approved_resource_names)
	msg := sprintf("GCP workspace template contains unapproved resource type %q", [record.type])
}

deny contains msg if {
	some record in resources
	record.type in object.keys(approved_resource_names)
	not record.name in approved_resource_names[record.type]
	msg := sprintf("GCP workspace template contains unapproved resource %s.%s", [record.type, record.name])
}

deny contains msg if {
	some record in resources
	count(object.get(record.value, "provisioner", [])) > 0
	msg := sprintf("GCP workspace resource %s.%s must not run provisioners", [record.type, record.name])
}

deny contains msg if {
	count(data_sources) != 7
	msg := sprintf("GCP workspace template must define exactly seven reviewed data sources, found %d", [count(data_sources)])
}

deny contains msg if {
	data_source_identities != approved_data_source_identities
	msg := "GCP workspace data source identities must exactly match the reviewed set"
}

deny contains msg if {
	some source_type, names in approved_data_source_names
	some name in names
	matching := [record |
		some record in data_sources
		record.type == source_type
		record.name == name
	]
	count(matching) != 1
	msg := sprintf("GCP workspace data source %s.%s must be defined exactly once", [source_type, name])
}

deny contains msg if {
	some record in data_sources
	not record.type in object.keys(approved_data_source_names)
	msg := sprintf("GCP workspace template contains unapproved data source type %q", [record.type])
}

deny contains msg if {
	some record in data_sources
	record.type in object.keys(approved_data_source_names)
	not record.name in approved_data_source_names[record.type]
	msg := sprintf("GCP workspace template contains unapproved data source %s.%s", [record.type, record.name])
}

deny contains msg if {
	count(outputs) != count(approved_outputs)
	msg := sprintf("GCP workspace template must define exactly %d reviewed outputs, found %d", [count(approved_outputs), count(outputs)])
}

deny contains msg if {
	output_names := {record.name | some record in outputs}
	output_names != object.keys(approved_outputs)
	msg := "GCP workspace output identities must exactly match the reviewed set"
}

deny contains msg if {
	some name in object.keys(approved_outputs)
	matching := [record | some record in outputs; record.name == name]
	count(matching) != 1
	msg := sprintf("GCP workspace output %q must be defined exactly once", [name])
}

deny contains msg if {
	some record in outputs
	record.name in object.keys(approved_outputs)
	record.value != approved_outputs[record.name]
	msg := sprintf("GCP workspace output %q must preserve the reviewed non-sensitive value", [record.name])
}

deny contains msg if {
	count(variables) != count(approved_variables)
	msg := sprintf("GCP workspace template must define exactly %d reviewed variables, found %d", [count(approved_variables), count(variables)])
}

deny contains msg if {
	variable_names := {record.name | some record in variables}
	variable_names != object.keys(approved_variables)
	msg := "GCP workspace variable identities must exactly match the reviewed set"
}

deny contains msg if {
	some name in object.keys(approved_variables)
	matching := [record | some record in variables; record.name == name]
	count(matching) != 1
	msg := sprintf("GCP workspace variable %q must be defined exactly once", [name])
}

deny contains msg if {
	some record in variables
	record.name in object.keys(approved_variables)
	record.value != approved_variables[record.name]
	msg := sprintf("GCP workspace variable %q must preserve the reviewed type, default, and validation", [record.name])
}

deny contains msg if {
	count(environment_configs) != 1
	msg := sprintf("GCP workspace template must define exactly one reviewed environment map, found %d", [count(environment_configs)])
}

deny contains msg if {
	count(env_configs) != 1
	msg := sprintf("GCP workspace template must define exactly one environment selector, found %d", [count(env_configs)])
}

deny contains msg if {
	some config in env_configs
	config != approved_env_config_expression
	msg := "GCP workspace environment selector must use the reviewed environment map"
}

deny contains msg if {
	count(dl_images) != 1
	msg := sprintf("GCP workspace template must define exactly one reviewed boot image map, found %d", [count(dl_images)])
}

deny contains msg if {
	some image_map in dl_images
	image_map != approved_dl_images
	msg := "GCP workspace boot images must match the reviewed immutable image map"
}

deny contains msg if {
	count(images) != 1
	msg := sprintf("GCP workspace template must define exactly one boot image selector, found %d", [count(images)])
}

deny contains msg if {
	some image in images
	image != approved_image_expression
	msg := "GCP workspace boot image selector must use the reviewed image map"
}

deny contains msg if {
	count(startup_scripts) != 1
	msg := sprintf("GCP workspace template must define exactly one startup script renderer, found %d", [count(startup_scripts)])
}

deny contains msg if {
	some script in startup_scripts
	script != approved_startup_script_expression
	msg := "GCP workspace startup script must render the reviewed template and inputs"
}

deny contains msg if {
	count(moved_blocks) != 1
	msg := sprintf("GCP workspace template must define exactly one reviewed moved block, found %d", [count(moved_blocks)])
}

deny contains msg if {
	some block in moved_blocks
	block != approved_moved_block
	msg := "GCP workspace moved block must preserve the reviewed instance state migration"
}

deny contains msg if {
	some config in environment_configs
	config != approved_environment_configs
	msg := "GCP workspace environment projects, networks, and ServiceAccounts must match the reviewed map"
}

deny contains msg if {
	some record in resources
	record.type == "coder_agent"
	record.name == "main"
	record.value != approved_coder_agent
	msg := "GCP workspace Coder agent must preserve the reviewed identity, environment, and executable scripts"
}

deny contains msg if {
	some record in resources
	record.type == "coder_metadata"
	record.name == "workspace_info"
	record.value != approved_coder_metadata
	msg := "GCP workspace metadata must preserve the reviewed non-sensitive fields"
}

deny contains msg if {
	some document in documents
	contains(json.marshal(document), "module.git_utilities.github_token")
	msg := "GCP workspace template must not expose the GitHub access token"
}

deny contains msg if {
	some record in resources
	record.type == "google_compute_disk"
	record.name == "vm_boot_disk"
	object.get(record.value, "image", "") != "${local.image}"
	msg := "GCP workspace boot disk must use the reviewed image selector"
}

deny contains msg if {
	some instance in instances
	object.keys(instance) != approved_instance_keys
	msg := "GCP workspace instance contains unreviewed configuration fields"
}

deny contains msg if {
	some instance in instances
	object.get(instance, "boot_disk", []) != approved_instance_boot_disk
	msg := "GCP workspace instance must boot from the reviewed managed disk"
}

deny contains msg if {
	some instance in instances
	object.get(instance, "attached_disk", []) != approved_instance_attached_disk
	msg := "GCP workspace instance must attach only the reviewed persistent home disk"
}

deny contains msg if {
	some instance in instances
	object.get(instance, "metadata_startup_script", "") != approved_instance_startup_script
	msg := "GCP workspace instance startup metadata must run only the reviewed Coder initialization"
}

deny contains msg if {
	some instance in instances
	object.get(instance, "service_account", []) != approved_instance_service_account
	msg := "GCP workspace instance must use the reviewed environment ServiceAccount and OAuth scopes"
}

deny contains msg if {
	some instance in instances
	object.get(instance, "network_interface", []) != approved_instance_network
	msg := "GCP workspace instance must remain on the reviewed private network without an external address"
}

deny contains msg if {
	some instance in instances
	object.get(instance, "metadata", {}) != approved_instance_metadata
	msg := "GCP workspace instance must preserve OS Login and block project SSH keys"
}

deny contains msg if {
	some instance in instances
	object.get(instance, "can_ip_forward", false) != false
	msg := "GCP workspace instance must not enable IP forwarding"
}

deny contains msg if {
	some instance in instances
	object.get(instance, "shielded_instance_config", []) != approved_shielded_config
	msg := "GCP workspace instance must preserve the reviewed Shielded VM settings"
}

deny contains msg if {
	some instance in instances
	dynamic := object.get(instance, "dynamic", {})
	object.keys(dynamic) != {"guest_accelerator", "reservation_affinity", "scratch_disk"}
	msg := "GCP workspace instance contains unreviewed dynamic blocks"
}
