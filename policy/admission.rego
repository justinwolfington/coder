package main

import rego.v1

# Development renders the stock upstream server, because values.dev.yaml sets no
# coder.image override the way staging and production do. Pinned to the exact
# reference: exempting the repository would pass any tag of it.
unpinned_images := {"ghcr.io/coder/coder:v2.35.4"}

secret_env_name := `(?i)(TOKEN|SECRET|KEY|PASSWORD)`

workloads contains w if {
	input.kind == "Pod"
	w := {"spec": input.spec, "labels": object.get(input, ["metadata", "labels"], {})}
}

workloads contains w if {
	input.kind in {"Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job"}
	w := {
		"spec": input.spec.template.spec,
		"labels": object.get(input.spec.template, ["metadata", "labels"], {}),
	}
}

workloads contains w if {
	input.kind == "CronJob"
	w := {
		"spec": input.spec.jobTemplate.spec.template.spec,
		"labels": object.get(input.spec.jobTemplate.spec.template, ["metadata", "labels"], {}),
	}
}

containers(spec) := array.concat(
	array.concat(
		object.get(spec, "containers", []),
		object.get(spec, "initContainers", []),
	),
	object.get(spec, "ephemeralContainers", []),
)

is_workspace(w) if w.labels["com.coder.resource"] == "true"

digest_pinned(image) if contains(image, "@sha256:")

digest_pinned(image) if image in unpinned_images

deny contains msg if {
	some w in workloads
	some c in containers(w.spec)
	not digest_pinned(c.image)
	msg := sprintf("container %q image %q is not pinned by digest", [c.name, c.image])
}

deny contains msg if {
	some w in workloads
	is_workspace(w)
	w.spec.serviceAccountName == "coder"
	msg := "workspace pod must not use the coder provisioner ServiceAccount"
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
	e.value != ""
	msg := sprintf("container %q env %q has a literal value; use valueFrom.secretKeyRef", [c.name, e.name])
}

deny contains msg if {
	some w in workloads
	some c in containers(w.spec)
	some e in object.get(c, "env", [])
	regex.match(secret_env_name, e.name)
	object.get(e, ["valueFrom", "configMapKeyRef"], null) != null
	msg := sprintf("container %q env %q reads from a ConfigMap; use valueFrom.secretKeyRef", [c.name, e.name])
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
