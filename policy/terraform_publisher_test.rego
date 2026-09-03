package terraform.publisher

import rego.v1

secure_locals := object.union(approved_timing_locals, {
	"templates": approved_template_expressions,
	"active_templates": approved_active_templates,
	"filtered_templates": approved_filtered_templates,
})

secure_variables := {
	"coder_token": [approved_variables.coder_token],
	"coder_url": [approved_variables.coder_url],
	"commit_sha": [approved_variables.commit_sha],
	"environment": [approved_variables.environment],
	"template_name": [approved_variables.template_name],
}

secure_input := [
	{
		"path": "templates/main.tf",
		"contents": {
			"terraform": [{"required_providers": [approved_required_providers]}],
			"provider": {"coderd": [approved_provider]},
			"resource": {"coderd_template": {"templates": [approved_template_resource]}},
			"output": {"deployed_templates": [approved_deployed_templates_output]},
		},
	},
	{
		"path": "templates/templates-config.tf",
		"contents": {
			"locals": [secure_locals],
			"variable": secure_variables,
		},
	},
]

test_secure_template_publisher_allowed if count(deny) == 0 with input as secure_input

test_publisher_local_exec_denied if {
	backdoor := {
		"path": "templates/backdoor.tf",
		"contents": {"resource": {"terraform_data": {"backdoor": [{
			"provisioner": {"local-exec": [{"command": "id"}]},
		}]}}},
	}
	input_documents := array.concat(secure_input, [backdoor])
	"template publisher contains unapproved resource terraform_data.backdoor" in deny with input as input_documents
	"template publisher resource terraform_data.backdoor must not run provisioners" in deny with input as input_documents
}

test_publisher_provider_redirect_denied if {
	bad_provider := object.union(approved_provider, {"url": "https://attacker.invalid"})
	first := object.union(secure_input[0], {"contents": object.union(secure_input[0].contents, {
		"provider": {"coderd": [bad_provider]},
	})})
	input_documents := [first, secure_input[1]]
	"template publisher coderd provider must use only the workflow URL and token variables" in deny with input as input_documents
}

test_publisher_extra_provider_denied if {
	providers := {
		"coderd": [approved_provider],
		"evil": [{}],
	}
	first := object.union(secure_input[0], {"contents": object.union(secure_input[0].contents, {"provider": providers})})
	input_documents := [first, secure_input[1]]
	"template publisher contains unapproved provider \"evil\"" in deny with input as input_documents
}

test_publisher_directory_redirect_denied if {
	bad_templates := object.union(approved_template_expressions, {"cpu-k8s": `${merge({directory="/"},local.cpu_timings)}`})
	second := object.union(secure_input[1], {"contents": {"locals": [{
		"templates": bad_templates,
		"active_templates": approved_active_templates,
		"filtered_templates": approved_filtered_templates,
	}]}})
	input_documents := [secure_input[0], second]
	"template publisher configuration for \"cpu-k8s\" must match the reviewed directory and environments" in deny with input as input_documents
}

test_publisher_partial_routing_override_denied if {
	override := {
		"path": "templates/override.tf",
		"contents": {"locals": [{
			"filtered_templates": `${{evil={directory="/"}}}`,
		}]},
	}
	input_documents := array.concat(secure_input, [override])
	"template publisher must define filtered_templates exactly once, found 2" in deny with input as input_documents
	"template publisher filtered_templates expression must preserve exact-name filtering" in deny with input as input_documents
}

test_publisher_encoded_token_output_denied if {
	bad_output := object.union(approved_deployed_templates_output, {
		"value": "${base64encode(nonsensitive(var.coder_token))}",
	})
	first_contents := object.union(secure_input[0].contents, {
		"output": {"deployed_templates": [bad_output]},
	})
	first := object.union(secure_input[0], {"contents": first_contents})
	input_documents := [first, secure_input[1]]
	"template publisher deployed_templates output must preserve the reviewed non-sensitive summary" in deny with input as input_documents
}

test_publisher_timing_token_disclosure_denied if {
	bad_locals := object.union(secure_locals, {
		"gpu_timings": `${merge(local.retention, {deprecation_message=nonsensitive # comment
        (var.coder_token)})}`,
	})
	second_contents := object.union(secure_input[1].contents, {"locals": [bad_locals]})
	second := object.union(secure_input[1], {"contents": second_contents})
	input_documents := [secure_input[0], second]
	"template publisher local \"gpu_timings\" must preserve the reviewed lifecycle settings" in deny with input as input_documents
	"template publisher must not evaluate local files or declassify sensitive values" in deny with input as input_documents
}

test_publisher_coder_token_must_remain_sensitive if {
	bad_token := object.union(approved_variables.coder_token, {"sensitive": false})
	variables := object.union(secure_variables, {"coder_token": [bad_token]})
	second_contents := object.union(secure_input[1].contents, {"variable": variables})
	second := object.union(secure_input[1], {"contents": second_contents})
	input_documents := [secure_input[0], second]
	"template publisher variable \"coder_token\" must preserve the reviewed type and validation" in deny with input as input_documents
}
