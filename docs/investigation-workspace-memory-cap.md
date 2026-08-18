# Investigation: 32 GB workspace memory cap

Date: 2026-08-12. Revised 2026-08-18 (see "Revision" at the bottom).
Trigger: https://weareabridge.slack.com/archives/C091DKJHSG0/p1786548406293389 — John Giorgi
reports being kicked out of his Kubernetes CPU workspace whenever RAM hits 100%. Claude Code
spawning subagents eats ~35 GB (known upstream issue), so this is blocking for him.

Status: diagnosed. Recommendation is 48 GiB; see "Open decision".

## Answer

The 32 GB cap is a Terraform validation in this repo. It is **not** a compute-class limit and
**not** a node-size limit.

## Evidence

### 1. Where the cap lives

`modules/resources/cpu/common_parameters.tf`:

```hcl
data "coder_parameter" "cpu" {
  validation { min = 8;  max = 16 }
}

data "coder_parameter" "memory" {
  validation { min = 16; max = 32 }   # this is the 32 GB John sees
}
```

Both are `mutable = true`, so a user can change them on an existing workspace with a restart —
once the ceiling is raised.

### 2. Why he is killed rather than throttled

`templates/cpu-k8s/main.tf:304-313` sets `requests == limits` for the `dev` container:

```hcl
resources {
  requests = { cpu = "...", memory = "${...}Gi" }
  limits   = { cpu = "...", memory = "${...}Gi" }
}
```

Equal requests and limits means Guaranteed QoS. At 32Gi the container is OOMKilled, the
Deployment recreates the pod, and the session drops. That is exactly the reported symptom
("kicked off when RAM usage hits 100%"), not a scheduler eviction and not a Coder-side timeout.

### 3. The compute class is not the constraint

`infrastructure/configsync/fleet/abridge-prod-fleet-e3cf/abridge-client-prod/us-central1/ml-triton-cluster/cpu-compute-class.yaml`:

```yaml
kind: ComputeClass
metadata:
  name: cpu-coder-class
spec:
  priorities:
    - machineFamily: c3d
      minCores: 4
      spot: false
    - machineFamily: c3
      minCores: 4
      spot: false
  nodePoolAutoCreation:
    enabled: true
  whenUnsatisfiable: DoNotScaleUp
```

Only a `minCores` floor. No upper bound, no machineType pin, so NAP may select any shape in
these families, including the highmem variants.

The ladder changed after this doc was written. It was `machineFamily: c2d` only; it is now c3d
then c3, because workspace homes moved to the `hyperdisk-balanced` StorageClass and c2d cannot
attach Hyperdisk. Dev and staging are merged, prod is infrastructure#11026. The c2d rung is being
removed rather than kept as fallback, so the memory ceiling has to be priced against c3d shapes.

`templates/cpu-k8s/main.tf:238-240` pins workspaces to this class via
`node_selector = { "cloud.google.com/compute-class" = "cpu-coder-class" }`.

### 4. What NAP actually provisions today

```
gcloud container node-pools list --cluster ml-triton-cluster \
  --region us-central1 --project abridge-client-prod
```

Measured 2026-08-18 across nodes labelled `cloud.google.com/compute-class=cpu-coder-class` in
prod usc1:

| instance type | nodes | capacity | allocatable | GKE reserve |
|---|---|---|---|---|
| `c2d-highcpu-32` | 12 | 62.8 GiB | **57.3 GiB** | 5.5 GiB |
| `c3d-highcpu-30` | 3 | 57.9 GiB | **52.6 GiB** | 5.2 GiB |
| `c2d-highcpu-16` | 1 | 31.3 GiB | **27.7 GiB** | 3.6 GiB |

NAP is choosing **highcpu** shapes (2 GB per vCPU), the cheapest family that satisfies the
current 16 vCPU / 32 GB maximum.

The earlier ~58 GB estimate for `c2d-highcpu-32` was derived from the GKE reserve formula and is
now confirmed by measurement at 57.3 GiB.

The number that matters going forward is `c3d-highcpu-30` at **52.6 GiB allocatable**, because
the ladder now leads with c3d. That is about 5 GiB less than the c2d-highcpu-32 this doc was
originally priced against.

The single `c2d-highcpu-16` node has 27.7 GiB allocatable and cannot host even a maximum-size
32 GiB workspace today.

### 5. Quota headroom

```
gcloud compute regions describe us-central1 --project abridge-client-prod \
  --flatten="quotas[]" --format="value(quotas.metric,quotas.usage,quotas.limit)"
```

```
CPUS       1535  / 27500
C2D_CPUS  15120  / 20000
```

About 4,880 c2d vCPU of headroom in prod us-central1. Real, but not unlimited.

## Cost of each ceiling

- **48 GiB** - fits `c3d-highcpu-30` (52.6 GiB allocatable) with no new machine shape. But it
  takes 91% of the node, leaving ~4.6 GiB for the exectrace sidecar and system overhead, which in
  practice means one workspace per node. A 32 GiB workspace leaves room to co-schedule a second.
  So this is not free: it is cheap in engineering effort while roughly doubling node count per
  workspace. That is a packing and cost change, not just a validation number.
- **64 GiB and above** - does not fit `c3d-highcpu-30` at all, so NAP must move to `c3d-standard`
  (4 GB/vCPU) or `c3d-highmem` (8 GB/vCPU). The compute class permits both, but nothing has
  forced that path in this cluster yet, so it is unproven here.

Note: `modules/resources/cpu/costs.tf:1-5` sets `ram_cost_per_gb = 0`, so the cost estimate
shown in the workspace UI (`templates/cpu-k8s/main.tf:358-359`) will not move when RAM is
raised. If the ceiling goes up meaningfully, that default is now misleading.

## Shipping constraints

1. `modules/resources/cpu` is a shared module consumed at `?ref=v1.12.1` by four templates:
   `templates/cpu-k8s`, `templates/gpu-k8s`, `templates/clinician-k8s`, `templates/phi-gpu-k8s`.
   Raising the validation is a one-line edit but needs a module tag plus four `?ref=` bumps.
   The `coder_parameter` definitions are imported wholesale by every consumer, so the new
   ceiling lands on all four templates at once.
2. A template-only PR does not deploy. `push-coder-templates` only fires after an artifact build
   on main — merged is not the same as deployed.
3. Adding or changing a `coder_parameter` without a matching value in `tests/templates/*.json`
   hangs CI on a TTY picker. Changing an existing validation range should be safe, but confirm
   the fixtures still satisfy the new min/max.
4. Dev deploys from `env/development` (ArgoCD); templates deploy from `main` via workflow.

## Unverified

- Direct cluster API access failed when this was written; resolved 2026-08-18, read live via the
  `gke_abridge-client-prod_us-central1_ml-triton-cluster` context. Section 4 allocatable figures
  are now measured and the formula-derived estimate proved accurate. The 48 GB "essentially free"
  claim did **not** survive: true against c2d-highcpu-32, false against the c3d-highcpu-30 the
  ladder now provisions.
- Whether NAP will actually select `c2d-highmem` when a pod requests a high memory-to-CPU ratio.
  The class allows it; it has never been exercised in this cluster.
- Cluster-level NAP shows only `autoscalingProfile: BALANCED` with no `resourceLimits`, so no
  cluster-wide cap was found. Not fully chased down.

## Open decision

Raise `max` to **48 GiB**. It fits the `c3d-highcpu-30` shape NAP now provisions without forcing
an unproven machine family, and stays a validation change plus a module release. Go in knowing it
shifts packing to roughly one workspace per node, which 32 GiB does not.

64 GiB is worse than this doc originally implied: it no longer fits the shape NAP builds, so it
relies on NAP selecting c3d-standard or c3d-highmem, never exercised in this cluster.

Sisil asked how urgent this is and whether John can work off coreweave or devspaces meanwhile;
John's blocker on that is whether Teleport service access works from devspaces, still unanswered.

Also worth saying out loud: more RAM buys headroom, it does not fix Claude Code's memory
behaviour. If subagent usage keeps growing, this ceiling gets revisited.


## Revision 2026-08-18

The compute class underneath this investigation changed between writing it and acting on it.
`cpu-coder-class` moved from a c2d-only ladder to c3d then c3, as part of putting workspace homes
on `hyperdisk-balanced` (c2d cannot attach Hyperdisk). Sections 3 and 4 and the cost analysis are
re-based on that. The diagnosis in sections 1 and 2 is unaffected: the cap is a Terraform
validation and the OOMKill is a Guaranteed-QoS consequence, neither of which depends on the node
family.
