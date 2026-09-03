package main

import rego.v1

secret_env_name := `(?i)(TOKEN|SECRET|KEY|PASSWORD)`

workloads contains w if {
	input.kind == "Pod"
	w := {
		"kind": input.kind,
		"name": object.get(input, ["metadata", "name"], ""),
		"spec": input.spec,
		"labels": object.get(input, ["metadata", "labels"], {}),
	}
}

workloads contains w if {
	input.kind in {"Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "ReplicationController", "Job"}
	w := {
		"kind": input.kind,
		"name": object.get(input, ["metadata", "name"], ""),
		"spec": input.spec.template.spec,
		"labels": object.get(input.spec.template, ["metadata", "labels"], {}),
	}
}

workloads contains w if {
	input.kind == "CronJob"
	w := {
		"kind": input.kind,
		"name": object.get(input, ["metadata", "name"], ""),
		"spec": input.spec.jobTemplate.spec.template.spec,
		"labels": object.get(input.spec.jobTemplate.spec.template, ["metadata", "labels"], {}),
	}
}

containers(spec) := {c |
	some field in {"containers", "initContainers", "ephemeralContainers"}
	values := object.get(spec, field, [])
	is_array(values)
	some c in values
}

is_workspace(w) if w.labels["com.coder.resource"] == "true"

digest_pinned(image) if contains(image, "@sha256:")

protected_utd_variables := {
	"TF_VAR_gpu_workspace_utd_service_account",
	"TF_VAR_phi_workspace_utd_service_account",
}

reserved_network_identities := {
	"coder",
	"coder-logstream-kube",
	"coder-user-data-transfer",
	"langsmith-annotation-proxy",
	"langsmith-proxy",
}

approved_coder_server(w) if {
	w.kind == "Deployment"
	w.name == "coder"
	w.labels["app.kubernetes.io/name"] == "coder"
	w.spec.serviceAccountName == "coder"
	some c in object.get(w.spec, "containers", [])
	c.name == "coder"
	startswith(c.image, "us-central1-docker.pkg.dev/abridge-artifact-registry/coder/coder-server@sha256:")
}

approved_user_data_transfer(w) if {
	w.kind == "Job"
	startswith(w.name, "coder-user-data-transfer-")
	w.labels["app.kubernetes.io/name"] == "coder-user-data-transfer"
	w.spec.serviceAccountName == "coder"
	object.get(w.spec, "automountServiceAccountToken", null) == false
	some c in object.get(w.spec, "containers", [])
	c.name == "transfer"
	startswith(c.image, "us-central1-docker.pkg.dev/abridge-artifact-registry/coder/coder-user-data-transfer@sha256:")
}

approved_coder_service_account(w) if approved_coder_server(w)
approved_coder_service_account(w) if approved_user_data_transfer(w)

approved_reserved_identity(w, "coder") if approved_coder_server(w)
approved_reserved_identity(w, "coder-user-data-transfer") if approved_user_data_transfer(w)

approved_reserved_identity(w, name) if {
	name in {"coder-logstream-kube", "langsmith-annotation-proxy", "langsmith-proxy"}
	w.kind == "Deployment"
	w.name == name
	w.labels["app.kubernetes.io/name"] == name
	w.spec.serviceAccountName == name
}

approved_utd_environment(e) if {
	e.name == "TF_VAR_phi_workspace_utd_service_account"
	e.value == "coder-phi-workspace-utd"
}

deny contains msg if {
	kind := object.get(input, "kind", "")
	is_string(kind)
	endswith(kind, "List")
	is_array(object.get(input, "items", null))
	msg := sprintf("rendered manifest collection kind %q is not allowed; emit resources as individual documents", [kind])
}

deny contains msg if {
	some w in workloads
	some c in containers(w.spec)
	not digest_pinned(c.image)
	msg := sprintf("container %q image %q is not pinned by digest", [c.name, c.image])
}

deny contains msg if {
	some w in workloads
	object.get(w.spec, "serviceAccount", "") != ""
	msg := sprintf("workload %s/%s must not use deprecated serviceAccount; set reviewed serviceAccountName explicitly", [w.kind, w.name])
}

deny contains msg if {
	some w in workloads
	some field in {"hostIPC", "hostNetwork", "hostPID"}
	object.get(w.spec, field, false) == true
	msg := sprintf("workload %s/%s must not enable %s", [w.kind, w.name, field])
}

deny contains msg if {
	some w in workloads
	some c in containers(w.spec)
	object.get(c, ["securityContext", "privileged"], false) == true
	msg := sprintf("container %q in %s/%s must not be privileged", [c.name, w.kind, w.name])
}

deny contains msg if {
	some w in workloads
	some volume in object.get(w.spec, "volumes", [])
	object.get(volume, "hostPath", null) != null
	msg := sprintf("workload %s/%s must not mount hostPath volume %q", [w.kind, w.name, object.get(volume, "name", "")])
}

deny contains msg if {
	some w in workloads
	w.spec.serviceAccountName == "coder"
	not approved_coder_service_account(w)
	msg := sprintf("workload %s/%s must not use the coder provisioner ServiceAccount", [w.kind, w.name])
}

deny contains msg if {
	some w in workloads
	name := object.get(w.labels, "app.kubernetes.io/name", "")
	name in reserved_network_identities
	not approved_reserved_identity(w, name)
	msg := sprintf("workload %s/%s claims reserved network identity %q", [w.kind, w.name, name])
}

deny contains msg if {
	some w in workloads
	is_workspace(w)
	object.get(w.spec, "automountServiceAccountToken", null) != false
	msg := "workspace pod must set automountServiceAccountToken: false explicitly; omitting it inherits the Kubernetes default"
}

deny contains msg if {
	some w in workloads
	some c in containers(w.spec)
	some e in object.get(c, "env", [])
	regex.match(secret_env_name, e.name)
	object.get(e, ["valueFrom", "secretKeyRef"], null) == null
	msg := sprintf("container %q env %q must use valueFrom.secretKeyRef", [c.name, e.name])
}

deny contains msg if {
	some w in workloads
	some c in containers(w.spec)
	some e in object.get(c, "env", [])
	e.name in protected_utd_variables
	not approved_utd_environment(e)
	msg := sprintf("container %q has an unapproved %s value", [c.name, e.name])
}

# envFrom hides its keys from the manifest, so a protected name cannot be ruled
# out by inspection.
deny contains msg if {
	some w in workloads
	is_workspace(w)
	some c in containers(w.spec)
	some ef in object.get(c, "envFrom", [])
	object.get(ef, "configMapRef", null) != null
	msg := sprintf("container %q uses envFrom.configMapRef; its keys cannot be checked, name protected variables explicitly", [c.name])
}
