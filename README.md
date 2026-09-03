# Coder Development Environment

This repository contains the configuration and templates for setting up development environments using Coder.

These environments are accessible at:

- Development: coder.abridge.coffee
- Staging: coder.abridge.cafe
- Production: coder.abridge.services

## Directory Structure

``` bash
coder/
├── docker-compose.yaml           # Local development setup
├── charts/                       # Helm chart for Coder deployment
├── scripts/                      # Utility scripts for setup and management
│   ├── create_coder_tokens.sh    # Script to create machine user tokens
│   └── update-to-version.sh      # Script to update module references to version tags
├── modules/                      # Shared modules for Coder templates
│   ├── resources/                # Resource parameter modules
│   │   ├── cpu/                  # CPU resource parameters and costs
│   │   └── gpu/                  # GPU resource parameters and costs
│   └── utilities/                # Utility modules
│       ├── git/                  # Git configuration
│       └── ide/                  # IDE configuration
└── templates/                    # Workspace templates
    ├── cpu-k8s/                  # Lightweight CPU-based workspace template
    ├── gpu-k8s/                  # GPU-based workspace template
    ├── phi-gpu-k8s/              # PHI-compliant secure GPU workspace template
    ├── gcp-vm-modular/           # GCP VM-based workspace template
    └── templates-config.tf       # Template configuration
    └── main.tf                   # Template Publisher
```

## Available Templates


### CPU K8s Template

- **Purpose**: Lightweight CPU-based development workspaces optimized for performance
- **Features**: VS Code, Cursor IDE, Git integration, Python & Jupyter support, no sidecars for maximum performance
- **Resources**: 8-16 CPU cores, 16-32GB RAM, 64-1024GB storage
- **Base Image**: `us-central1-docker.pkg.dev/abridge-artifact-registry/coder/base:latest`
- **Use Cases**: CPU-intensive development, code review and analysis, testing environments, resource-conscious projects

### GPU K8s Template

- **Purpose**: GPU-accelerated workspaces for ML/AI development
- **Features**: NVIDIA GPU support, VS Code, Cursor IDE, simplified repository management
- **Resources**: 8-16 CPU cores, 16-32GB RAM, 64-1024GB storage, configurable GPUs
- **GPU Support**: NVIDIA L4, H100 (80GB) with multi-GPU configuration
- **Base Image**: `us-central1-docker.pkg.dev/abridge-artifact-registry/coder/gpu:latest`

### PHI GPU K8s Template

- **Purpose**: PHI-compliant GPU-accelerated workspaces for secure healthcare ML/AI development
- **Features**: NVIDIA GPU support, browser-only VS Code, default-deny egress, PHI compliance mode
- **Security**: Default-deny egress with an explicit allowlist, disabled SSH/port forwarding/desktop apps
- **Resources**: 8-16 CPU cores, 16-32GB RAM, 64-1024GB storage, configurable GPUs
- **GPU Support**: NVIDIA L4, H100 (80GB) with multi-GPU configuration
- **Base Image**: `us-central1-docker.pkg.dev/abridge-artifact-registry/coder/phi-gpu:latest`
- **Network Policy**: Dedicated `networkPolicyPhi` plus an Istio `REGISTRY_ONLY` sidecar. Egress is denied by default and permitted only to the hosts in `phiIstio.commonAllowedHosts` and the per-environment `phiIstio.allowedHosts`. That allowlist currently includes public package registries, model hubs and third-party APIs, so this is not an air-gapped environment.
- **Use Cases**: Healthcare data analysis, PHI-compliant ML training, secure AI research, protected health information processing

### GCP VM Modular Template

- **Purpose**: GPU-accelerated Google Cloud VM workspaces for ML/AI development
- **Features**: NVIDIA GPU support, VS Code, Cursor IDE, deep learning environments, security hardening
- **Resources**: e2-standard-4 to a3-highgpu-8g machine types, configurable disk size
- **GPU Support**: NVIDIA L4 (1x, 2x), H100 80GB (8x) with local SSD for H100
- **Base Image**: Google Deep Learning Platform images (PyTorch, TensorFlow, Common Framework, Ubuntu 22.04)

## Quick Start

### Local Development

1. Start the local development environment:

   ``` bash
   docker-compose up -d
   ```

2. Access Coder at <http://localhost:7080>

### Kubernetes Deployment

1. Update the values in `charts/coder/values.yaml`
2. Deploy using Helm:

   ``` bash
   helm install coder ./charts/coder
   ```

### Creating Machine User Tokens

Use the provided script to create machine user tokens:

``` bash
./scripts/create_coder_tokens.sh https://coder.abridge.coffee
```

## Module Version Management

Templates use Git tags instead of commit hashes to prevent orphaned references:

```bash
# Update all templates to a version
./scripts/update-to-version.sh v1.1.0

# Or use GitHub Actions: "Publish Coder Templates" → enter module_version
```

**Workflow:**

1. Create tag: Actions → "Create Version Tag"
2. Deploy: Actions → "Publish Coder Templates" (optionally specify `module_version`)
3. Different environments can use different versions

## Prerequisites

- Kubernetes cluster with proper storage configuration
- For GPU template: GPU nodes with NVIDIA device plugin installed
- For PHI template: Kubernetes cluster with network policy support and `networkPolicyPhi` configuration enabled
- For GCP VM template: Google Cloud Platform project with Compute Engine API enabled, VPC network configured, and sufficient GPU quotas
- GitHub external authentication configured for Git integration

## Troubleshooting

**Template Deployment Issues**
- Verify Kubernetes provider is configured in Coder
- Check container registry access permissions
- Ensure proper storage classes are available

**GitHub Integration Issues**
- Ensure GitHub external auth is configured in Coder deployment
- Check user has linked GitHub account in Coder settings
- Verify GitHub app has `admin:public_key` scope for SSH key management

**GPU Template Issues**
- Verify GPU device plugin is installed: `kubectl get daemonset -n kube-system`
- Check GPU node labels match template configuration
- Ensure sufficient GPU resources are available

**PHI Template Issues**
- Verify network policies are enabled: `kubectl get networkpolicy -n coder`
- Check `networkPolicyPhi` configuration in values files
- Confirm PHI workspaces have `coder-phi-workspace` label
- Ensure egress is default-deny: traffic to a host outside the `phiIstio` allowlist should be refused by the sidecar
- Verify browser-only access restrictions (SSH/desktop apps disabled)

**GCP VM Template Issues**
- Verify GCP credentials and project permissions
- Check GPU quotas in the specified region/zone
- Ensure VPC network and subnet are properly configured
- Confirm service account has required compute instance permissions

**Performance Issues**
- Adjust resource limits based on workload requirements
- Monitor workspace metrics via built-in monitoring
- Use higher memory allocations for resource-intensive tasks

## Extra Features

### Audit Logging

Audit logging enables auditors to monitor user operations across the deployment. This feature tracks events at the Coder server level (does not track logs for in-workspace processes), providing visibility into administrative actions and user activities.

**Access Methods:**
- **UI**: Navigate to Coder Homepage → Admin Settings → Audit Logs
- **GCP Logs Explorer**: Use the following query:

```logql
resource.labels.location="us-central1"
resource.labels.cluster_name="ml-triton-cluster"
resource.type="k8s_container"
resource.labels.namespace_name="coder"
resource.labels.container_name="coder"
SEARCH("`coderd: audit_log`")
```

For detailed information about logged events, see the [Coder Audit Logs documentation](https://coder.com/docs/admin/security/audit-logs).

### Process Logging

Process logging captures all system-level processes executing within workspaces, providing fine-grained visibility into workspace activities. This feature complements audit logging by tracking workspace-level events.

**Requirements:**
- Only available on Linux in Kubernetes environments
- Additional configuration required (see documentation)

**Access via GCP Logs Explorer:**

```logql
resource.labels.location="us-central1"
resource.labels.cluster_name="ml-triton-cluster"
resource.type="k8s_container"
resource.labels.namespace_name="coder"
resource.labels.container_name="exectrace"
```

For configuration details, see the [Workspace Process Logging documentation](https://coder.com/docs/admin/templates/extending-templates/process-logging#configuring-custom-templates-to-use-workspace-process-logging).

### Private Python Packages (Artifact Registry)

Workspace images ship `keyring` with the `keyrings.google-artifactregistry-auth` backend and set `UV_KEYRING_PROVIDER=subprocess`, so `uv` fetches Artifact Registry credentials on demand. Put `oauth2accesstoken` in the index URL as the username and leave the password unset:

```bash
uv pip install \
  --index-url https://oauth2accesstoken@us-python.pkg.dev/abridge-artifact-registry/python-virtual/simple/ \
  <package>
```

Do not export a token from `.bashrc`. A bare `gcloud auth print-access-token` there runs on every non-interactive shell, including the seven metadata scripts the workspace agent spawns every 15 seconds, which mints a fresh token about once every two seconds for the life of the workspace. The token also expires after an hour, so any shell open longer than that is left holding a dead credential.

### Feature Availability by Template

| Template | Process Logging |
|----------|-----------------|
| CPU K8s | Yes |
| GPU K8s | Yes |
| PHI GPU K8s | No |
| GCP VM Modular | No |
