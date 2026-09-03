package main

import rego.v1

# Compliant baseline; a test overrides only the field it is exercising.
workspace_pod(spec) := {
	"kind": "Pod",
	"metadata": {"labels": {"com.coder.resource": "true"}},
	"spec": object.union({"automountServiceAccountToken": false}, spec),
}

digest := "repo.example/app@sha256:0000000000000000000000000000000000000000000000000000000000000000"

test_digest_pinned_image_allowed if {
	count(deny) == 0 with input as workspace_pod({"containers": [{"name": "dev", "image": digest}]})
}

test_tagged_image_denied if {
	count(deny) == 1 with input as workspace_pod({"containers": [{"name": "dev", "image": "repo.example/app:v1"}]})
}

test_vendored_upstream_image_allowed if {
	count(deny) == 0 with input as workspace_pod({"containers": [{"name": "dev", "image": "ghcr.io/coder/coder:v2.35.4"}]})
}

# The exception is one exact reference, so a different tag of the same
# repository must still fail.
test_other_tag_of_exempt_repo_denied if {
	count(deny) == 1 with input as workspace_pod({"containers": [{"name": "dev", "image": "ghcr.io/coder/coder:attacker"}]})
}

test_provisioner_service_account_denied if {
	count(deny) == 1 with input as workspace_pod({
		"serviceAccountName": "coder",
		"containers": [{"name": "dev", "image": digest}],
	})
}

test_automount_token_denied if {
	count(deny) == 1 with input as workspace_pod({
		"automountServiceAccountToken": true,
		"containers": [{"name": "dev", "image": digest}],
	})
}

# Omitting the field inherits the Kubernetes default, so it is not safe.
test_automount_omitted_denied if {
	count(deny) == 1 with input as {
		"kind": "Pod",
		"metadata": {"labels": {"com.coder.resource": "true"}},
		"spec": {"containers": [{"name": "dev", "image": digest}]},
	}
}

test_plaintext_secret_env_denied if {
	count(deny) == 1 with input as workspace_pod({"containers": [{
		"name": "dev",
		"image": digest,
		"env": [{"name": "LANGSMITH_API_KEY", "value": "sk-live"}],
	}]})
}

test_secret_key_ref_env_allowed if {
	count(deny) == 0 with input as workspace_pod({"containers": [{
		"name": "dev",
		"image": digest,
		"env": [{"name": "LANGSMITH_API_KEY", "valueFrom": {"secretKeyRef": {"name": "s", "key": "k"}}}],
	}]})
}

test_configmap_key_ref_secret_env_denied if {
	count(deny) == 1 with input as workspace_pod({"containers": [{
		"name": "dev",
		"image": digest,
		"env": [{"name": "LANGSMITH_API_KEY", "valueFrom": {"configMapKeyRef": {"name": "c", "key": "k"}}}],
	}]})
}

test_env_from_configmap_denied if {
	count(deny) == 1 with input as workspace_pod({"containers": [{
		"name": "dev",
		"image": digest,
		"envFrom": [{"configMapRef": {"name": "c"}}],
	}]})
}

test_ephemeral_container_is_checked if {
	count(deny) == 1 with input as workspace_pod({
		"containers": [{"name": "dev", "image": digest}],
		"ephemeralContainers": [{"name": "debug", "image": "repo.example/app:v1"}],
	})
}

test_init_container_is_checked if {
	count(deny) == 1 with input as workspace_pod({
		"containers": [{"name": "dev", "image": digest}],
		"initContainers": [{"name": "setup", "image": "repo.example/app:v1"}],
	})
}

test_deployment_pod_template_is_checked if {
	count(deny) == 1 with input as {
		"kind": "Deployment",
		"spec": {"template": {
			"metadata": {"labels": {"com.coder.resource": "true"}},
			"spec": {
				"automountServiceAccountToken": false,
				"containers": [{"name": "dev", "image": "repo.example/app:v1"}],
			},
		}},
	}
}
