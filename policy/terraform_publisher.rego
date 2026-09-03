package terraform.publisher

import rego.v1

allowed_document_keys := {"locals", "output", "provider", "resource", "terraform", "variable"}

approved_required_providers := {
	"coderd": {"source": "coder/coderd", "version": "0.0.23"},
}

approved_provider := {
	"token": "${var.coder_token}",
	"url": "${var.coder_url}",
}

approved_template_expressions := {
	"cpu-k8s": `${merge(local.cpu_timings,{display_name="KubernetesCPUWorkspace"description="LightweightKubernetesworkspaceforCPU-intensivetaskswithdevelopmenttools."icon="/emojis/1f4bb.png"directory="./cpu-k8s"environments=["development","staging","production"]})}`,
	"gcp-vm-modular": `${merge(local.gpu_timings,{display_name="GCPVMWorkspacewithDocker"description="GCPVMworkspacewithGPUsupportandDocker.FeaturesMLdevelopmenttoolsforMLOpsandScientists."icon="/icon/gcp.png"directory="./gcp-vm-modular"environments=["development","staging"]})}`,
	"gpu-k8s": `${merge(local.gpu_timings,{display_name="KubernetesGPUWorkspace"description="KubernetesworkspacewithGPUsupportforMLScientists(nodockercontainersupport)."icon="/emojis/1f35f.png"directory="./gpu-k8s"environments=["development","staging","production"]})}`,
	"phi-gpu-k8s": `${merge(local.phi_timings,{display_name="KubernetesPHIWorkspace"description="SecureKubernetesworkspacewithGPUsupportandenhancedsecurityforPHIcompliance."icon="/emojis/1f510.png"directory="./phi-gpu-k8s"environments=["development","production"]})}`,
}

approved_active_templates := `${{forname,configinlocal.templates:name=>configifcontains(config.environments,var.environment)}}`
approved_filtered_templates := `${{forname,configinlocal.active_templates:name=>configifvar.template_name==""||name==var.template_name}}`

approved_timing_locals := {
	"cpu_timings": "${merge(local.retention, local.failure_cleanup)}",
	"failure_cleanup": {"failure_ttl_ms": 7200000},
	"gpu_timings": `${merge({
    activity_bump_ms = 86400000  # 1d
    default_ttl_ms   = 172800000 # 2d auto-stop
  }, local.retention, local.failure_cleanup)}`,
	"phi_retention": {
		"allow_user_auto_stop": false,
		"default_ttl_ms": 259200000,
		"time_til_dormant_autodelete_ms": 345600000,
		"time_til_dormant_ms": 604800000,
	},
	"phi_timings": "${merge(local.gpu_timings, local.phi_retention)}",
	"retention": {
		"time_til_dormant_autodelete_ms": 604800000,
		"time_til_dormant_ms": 1814400000,
	},
	"standard_timings": "${merge(local.retention, local.failure_cleanup)}",
}

approved_local_names := {
	"active_templates",
	"cpu_timings",
	"failure_cleanup",
	"filtered_templates",
	"gpu_timings",
	"phi_retention",
	"phi_timings",
	"retention",
	"standard_timings",
	"templates",
}

approved_variables := {
	"coder_token": {
		"description": "Coder session token",
		"sensitive": true,
		"type": "${string}",
	},
	"coder_url": {
		"description": "Coder access URL",
		"type": "${string}",
	},
	"commit_sha": {
		"description": "Git commit SHA for version naming",
		"type": "${string}",
	},
	"environment": {
		"description": "Target environment (development, staging, production)",
		"type": "${string}",
		"validation": [{
			"condition": "${contains([\"development\", \"staging\", \"production\"], var.environment)}",
			"error_message": "Environment must be one of: development, staging, production",
		}],
	},
	"template_name": {
		"default": "",
		"description": "Specific template name to deploy (optional, deploys all if empty)",
		"type": "${string}",
	},
}

approved_template_resource := {
	"activity_bump_ms": "${try(each.value.activity_bump_ms, null)}",
	"allow_user_auto_stop": "${try(each.value.allow_user_auto_stop, null)}",
	"default_ttl_ms": "${try(each.value.default_ttl_ms, null)}",
	"deprecation_message": "${try(each.value.deprecation_message, \"\")}",
	"description": "${each.value.description}",
	"display_name": "${each.value.display_name}",
	"failure_ttl_ms": "${try(each.value.failure_ttl_ms, null)}",
	"for_each": "${local.filtered_templates}",
	"icon": "${each.value.icon}",
	"name": "${each.key}",
	"time_til_dormant_autodelete_ms": "${try(each.value.time_til_dormant_autodelete_ms, null)}",
	"time_til_dormant_ms": "${try(each.value.time_til_dormant_ms, null)}",
	"versions": [{
		"active": true,
		"directory": "${each.value.directory}",
		"message": "Auto-deploy ${var.commit_sha} to ${var.environment}",
		"name": "${var.commit_sha}",
	}],
}

approved_deployed_templates_output := {
	"description": "Templates deployed in this run",
	"value": {
		"environment": "${var.environment}",
		"templates": "${keys(local.filtered_templates)}",
		"version": "${var.commit_sha}",
	},
}

documents contains document if {
	some item in input
	document := item.contents
}

terraform_blocks contains block if {
	some document in documents
	some block in object.get(document, "terraform", [])
}

providers contains record if {
	some document in documents
	providers_by_name := object.get(document, "provider", {})
	some name, values in providers_by_name
	some value in values
	record := {"name": name, "value": value}
}

resources contains record if {
	some document in documents
	resources_by_type := object.get(document, "resource", {})
	some resource_type, resources_by_name in resources_by_type
	some name, resource_values in resources_by_name
	some resource in resource_values
	record := {"type": resource_type, "name": name, "value": resource}
}

outputs contains record if {
	some document in documents
	outputs_by_name := object.get(document, "output", {})
	some name, values in outputs_by_name
	some value in values
	record := {"name": name, "value": value}
}

variables := [record |
	some document_index, item in input
	document := item.contents
	variables_by_name := object.get(document, "variable", {})
	some name, values in variables_by_name
	some value_index, value in values
	record := {"document_index": document_index, "name": name, "value": value, "value_index": value_index}
]

template_maps contains templates if {
	some document in documents
	some local_values in object.get(document, "locals", [])
	templates := object.get(local_values, "templates", null)
	templates != null
}

local_assignments(key) := [record |
	some document_index, item in input
	document := item.contents
	some block_index, local_values in object.get(document, "locals", [])
	value := object.get(local_values, key, null)
	value != null
	record := {"block_index": block_index, "document_index": document_index, "value": value}
]

active_template_assignments := local_assignments("active_templates")
filtered_template_assignments := local_assignments("filtered_templates")

local_names := {name |
	some document in documents
	some local_values in object.get(document, "locals", [])
	some name in object.keys(local_values)
}

dangerous_expression(value) if {
	is_string(value)
	without_block_comments := regex.replace(value, `(?s)/\*.*?\*/`, "")
	without_line_comments := regex.replace(without_block_comments, `(?m)//[^\n]*`, "")
	without_comments := regex.replace(without_line_comments, `(?m)#[^\n]*`, "")
	regex.match(`(?i)\b(file|filebase64|fileexists|fileset|nonsensitive|templatefile)\s*\(`, without_comments)
}

normalize_expression(expression) := regex.replace(expression, `\s+`, "")

approved_resource_identity(record) if {
	record.type == "coderd_template"
	record.name == "templates"
}

deny contains msg if {
	some document in documents
	some key in object.keys(document)
	not key in allowed_document_keys
	msg := sprintf("template publisher contains unapproved top-level block %q", [key])
}

deny contains msg if {
	some document in documents
	some value
	walk(document, [_, value])
	dangerous_expression(value)
	msg := "template publisher must not evaluate local files or declassify sensitive values"
}

deny contains msg if {
	count(terraform_blocks) != 1
	msg := sprintf("template publisher must define exactly one terraform block, found %d", [count(terraform_blocks)])
}

deny contains msg if {
	some block in terraform_blocks
	block != {"required_providers": [approved_required_providers]}
	msg := "template publisher required providers must match the reviewed source and version"
}

deny contains msg if {
	count(providers) != 1
	msg := sprintf("template publisher must define exactly one coderd provider, found %d", [count(providers)])
}

deny contains msg if {
	some record in providers
	record.name != "coderd"
	msg := sprintf("template publisher contains unapproved provider %q", [record.name])
}

deny contains msg if {
	some record in providers
	record.name == "coderd"
	record.value != approved_provider
	msg := "template publisher coderd provider must use only the workflow URL and token variables"
}

deny contains msg if {
	count(resources) != 1
	msg := sprintf("template publisher must define exactly one resource, found %d", [count(resources)])
}

deny contains msg if {
	some record in resources
	not approved_resource_identity(record)
	msg := sprintf("template publisher contains unapproved resource %s.%s", [record.type, record.name])
}

deny contains msg if {
	some record in resources
	count(object.get(record.value, "provisioner", [])) > 0
	msg := sprintf("template publisher resource %s.%s must not run provisioners", [record.type, record.name])
}

deny contains msg if {
	some record in resources
	record.type == "coderd_template"
	record.name == "templates"
	record.value != approved_template_resource
	msg := "template publisher coderd_template must preserve reviewed directory and version routing"
}

deny contains msg if {
	count(outputs) != 1
	msg := sprintf("template publisher must define exactly one reviewed output, found %d", [count(outputs)])
}

deny contains msg if {
	some record in outputs
	record.name != "deployed_templates"
	msg := sprintf("template publisher contains unapproved output %q", [record.name])
}

deny contains msg if {
	some record in outputs
	record.name == "deployed_templates"
	record.value != approved_deployed_templates_output
	msg := "template publisher deployed_templates output must preserve the reviewed non-sensitive summary"
}

deny contains msg if {
	count(variables) != count(approved_variables)
	msg := sprintf("template publisher must define exactly %d reviewed variables, found %d", [count(approved_variables), count(variables)])
}

deny contains msg if {
	variable_names := {record.name | some record in variables}
	variable_names != object.keys(approved_variables)
	msg := "template publisher variable identities must exactly match the reviewed set"
}

deny contains msg if {
	some name in object.keys(approved_variables)
	matching := [record | some record in variables; record.name == name]
	count(matching) != 1
	msg := sprintf("template publisher variable %q must be defined exactly once", [name])
}

deny contains msg if {
	some record in variables
	record.name in object.keys(approved_variables)
	record.value != approved_variables[record.name]
	msg := sprintf("template publisher variable %q must preserve the reviewed type and validation", [record.name])
}

deny contains msg if {
	count(template_maps) != 1
	msg := sprintf("template publisher must define exactly one template map, found %d", [count(template_maps)])
}

deny contains msg if {
	some templates in template_maps
	object.keys(templates) != object.keys(approved_template_expressions)
	msg := "template publisher template inventory must match the reviewed directories"
}

deny contains msg if {
	some templates in template_maps
	some name, expected in approved_template_expressions
	normalize_expression(object.get(templates, name, "")) != expected
	msg := sprintf("template publisher configuration for %q must match the reviewed directory and environments", [name])
}

deny contains msg if {
	local_names != approved_local_names
	msg := "template publisher local identities must exactly match the reviewed set"
}

deny contains msg if {
	some name in object.keys(approved_timing_locals)
	assignments := local_assignments(name)
	count(assignments) != 1
	msg := sprintf("template publisher local %q must be defined exactly once", [name])
}

deny contains msg if {
	some name, expected in approved_timing_locals
	some assignment in local_assignments(name)
	assignment.value != expected
	msg := sprintf("template publisher local %q must preserve the reviewed lifecycle settings", [name])
}

deny contains msg if {
	count(active_template_assignments) != 1
	msg := sprintf("template publisher must define active_templates exactly once, found %d", [count(active_template_assignments)])
}

deny contains msg if {
	some assignment in active_template_assignments
	normalize_expression(assignment.value) != approved_active_templates
	msg := "template publisher active_templates expression must preserve the environment allowlist"
}

deny contains msg if {
	count(filtered_template_assignments) != 1
	msg := sprintf("template publisher must define filtered_templates exactly once, found %d", [count(filtered_template_assignments)])
}

deny contains msg if {
	some assignment in filtered_template_assignments
	normalize_expression(assignment.value) != approved_filtered_templates
	msg := "template publisher filtered_templates expression must preserve exact-name filtering"
}
