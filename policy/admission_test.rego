package main

import rego.v1

# Compliant baseline; a test overrides only the field it is exercising.
workspace_pod(spec) := {
	"kind": "Pod",
	"metadata": {"name": "workspace", "labels": {"com.coder.resource": "true"}},
	"spec": object.union({"automountServiceAccountToken": false}, spec),
}

digest := "repo.example/app@sha256:0000000000000000000000000000000000000000000000000000000000000000"

test_digest_pinned_image_allowed if {
	count(deny) == 0 with input as workspace_pod({"containers": [{"name": "dev", "image": digest}]})
}

test_tagged_image_denied if {
	count(deny) == 1 with input as workspace_pod({"containers": [{"name": "dev", "image": "repo.example/app:v1"}]})
}

test_tagged_upstream_image_denied if {
	count(deny) == 1 with input as workspace_pod({"containers": [{"name": "dev", "image": "ghcr.io/coder/coder:v2.35.4"}]})
}

test_other_upstream_tag_denied if {
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

test_empty_secret_env_denied if {
	count(deny) == 1 with input as workspace_pod({"containers": [{
		"name": "dev",
		"image": digest,
		"env": [{"name": "API_KEY", "value": ""}],
	}]})
}

test_field_ref_secret_env_denied if {
	count(deny) == 1 with input as workspace_pod({"containers": [{
		"name": "dev",
		"image": digest,
		"env": [{"name": "API_KEY", "valueFrom": {"fieldRef": {"fieldPath": "metadata.name"}}}],
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

test_ephemeral_container_secret_env_is_checked if {
	count(deny) == 1 with input as workspace_pod({
		"containers": [{"name": "dev", "image": digest}],
		"ephemeralContainers": [{
			"name": "debug",
			"image": digest,
			"env": [{"name": "API_KEY", "value": "debug-secret"}],
		}],
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

test_manifest_list_denied if {
	input_document := {
		"apiVersion": "v1",
		"kind": "List",
		"items": [{
			"apiVersion": "apps/v1",
			"kind": "Deployment",
			"metadata": {"name": "workspace-backdoor"},
			"spec": {},
		}],
	}
	count(deny) == 1 with input as input_document
}

test_unreviewed_coder_identity_denied if {
	input_document := {
		"kind": "Deployment",
		"metadata": {"name": "workspace-backdoor"},
		"spec": {"template": {
			"metadata": {"labels": {"app.kubernetes.io/name": "coder"}},
			"spec": {
				"serviceAccountName": "coder",
				"containers": [{"name": "dev", "image": digest}],
			},
		}},
	}
	messages := deny with input as input_document
	"workload Deployment/workspace-backdoor must not use the coder provisioner ServiceAccount" in messages
	"workload Deployment/workspace-backdoor claims reserved network identity \"coder\"" in messages
}

test_reviewed_coder_server_identity_allowed if {
	input_document := {
		"kind": "Deployment",
		"metadata": {"name": "coder"},
		"spec": {"template": {
			"metadata": {"labels": {"app.kubernetes.io/name": "coder"}},
			"spec": {
				"serviceAccountName": "coder",
				"containers": [{
					"name": "coder",
					"image": "us-central1-docker.pkg.dev/abridge-artifact-registry/coder/coder-server@sha256:0000000000000000000000000000000000000000000000000000000000000000",
				}],
			},
		}},
	}
	count(deny) == 0 with input as input_document
}

test_unapproved_utd_service_account_value_denied if {
	input_document := {
		"kind": "Deployment",
		"metadata": {"name": "coder"},
		"spec": {"template": {
			"metadata": {"labels": {"app.kubernetes.io/name": "coder"}},
			"spec": {
				"serviceAccountName": "coder",
				"containers": [{
					"name": "coder",
					"image": "us-central1-docker.pkg.dev/abridge-artifact-registry/coder/coder-server@sha256:0000000000000000000000000000000000000000000000000000000000000000",
					"env": [{"name": "TF_VAR_phi_workspace_utd_service_account", "value": "coder"}],
				}],
			},
		}},
	}
	"container \"coder\" has an unapproved TF_VAR_phi_workspace_utd_service_account value" in deny with input as input_document
}

test_host_access_denied if {
	input_document := {
		"kind": "DaemonSet",
		"metadata": {"name": "host-backdoor"},
		"spec": {"template": {
			"metadata": {"labels": {}},
			"spec": {
				"hostPID": true,
				"serviceAccountName": "coder",
				"containers": [{
					"name": "backdoor",
					"image": digest,
					"securityContext": {"privileged": true},
				}],
				"volumes": [{"name": "host", "hostPath": {"path": "/"}}],
			},
		}},
	}
	messages := deny with input as input_document
	"workload DaemonSet/host-backdoor must not enable hostPID" in messages
	"container \"backdoor\" in DaemonSet/host-backdoor must not be privileged" in messages
	"workload DaemonSet/host-backdoor must not mount hostPath volume \"host\"" in messages
	"workload DaemonSet/host-backdoor must not use the coder provisioner ServiceAccount" in messages
}

test_replication_controller_host_access_denied if {
	input_document := {
		"kind": "ReplicationController",
		"metadata": {"name": "host-backdoor"},
		"spec": {"template": {
			"metadata": {"labels": {"app.kubernetes.io/name": "coder"}},
			"spec": {
				"hostNetwork": true,
				"serviceAccountName": "coder",
				"containers": [{
					"name": "backdoor",
					"image": digest,
					"securityContext": {"privileged": true},
				}],
				"volumes": [{"name": "host", "hostPath": {"path": "/"}}],
			},
		}},
	}
	messages := deny with input as input_document
	"workload ReplicationController/host-backdoor must not enable hostNetwork" in messages
	"container \"backdoor\" in ReplicationController/host-backdoor must not be privileged" in messages
	"workload ReplicationController/host-backdoor must not mount hostPath volume \"host\"" in messages
	"workload ReplicationController/host-backdoor must not use the coder provisioner ServiceAccount" in messages
	"workload ReplicationController/host-backdoor claims reserved network identity \"coder\"" in messages
}

test_deprecated_service_account_field_denied if {
	input_document := {
		"kind": "Deployment",
		"metadata": {"name": "workspace-backdoor"},
		"spec": {"template": {
			"metadata": {"labels": {}},
			"spec": {
				"serviceAccount": "coder",
				"containers": [{"name": "dev", "image": digest}],
			},
		}},
	}
	"workload Deployment/workspace-backdoor must not use deprecated serviceAccount; set reviewed serviceAccountName explicitly" in deny with input as input_document
}

test_null_optional_container_lists_do_not_skip_regular_containers if {
	input_document := {
		"kind": "Pod",
		"metadata": {"name": "null-list-backdoor"},
		"spec": {
			"containers": [{
				"name": "backdoor",
				"image": "repo.example/backdoor:latest",
				"securityContext": {"privileged": true},
			}],
			"ephemeralContainers": null,
			"initContainers": null,
		},
	}
	messages := deny with input as input_document
	"container \"backdoor\" image \"repo.example/backdoor:latest\" is not pinned by digest" in messages
	"container \"backdoor\" in Pod/null-list-backdoor must not be privileged" in messages
}
