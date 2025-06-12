# Coder Development Environment

This repository contains the configuration and templates for setting up development environments using Coder.

These environments are accessible at:

- Development: coder.abridge.coffee
- Staging: coder.abridge.cafe
- Production: coder.abridge.services

## Directory Structure

``` bash
coder/
├── docker-compose.yaml     # Local development setup
├── charts/                # Helm chart for Coder deployment
├── scripts/               # Utility scripts for setup and management
│   └── create_coder_tokens.sh  # Script to create machine user tokens
└── templates/             # Workspace templates
    ├── clinician-k8s/     # CPU-based workspace template
    ├── cpu-k8s/          # Lightweight CPU-based workspace template
    ├── gpu-k8s/          # GPU-based workspace template
    ├── phi-gpu-k8s/      # PHI-compliant secure GPU workspace template
    ├── gcp-vm-modular/    # GCP VM-based workspace template
    └── templates-config.json  # Template configuration
```

## Available Templates

### Clinician K8s Template

- **Purpose**: CPU-based development workspaces with integrated Arize Phoenix tracing and monitoring
- **Features**: VS Code, Cursor IDE, Arize Phoenix dashboard, Git integration, Python & Jupyter support, OTLP tracing pre-configured
- **Resources**: 4-16 CPU cores, 8-32GB RAM, 16-1024GB storage
- **Phoenix Sidecar**: 500m-1000m CPU, 512Mi-1Gi RAM for tracing
- **Base Image**: `us-central1-docker.pkg.dev/abridge-artifact-registry/coder/base:latest`
- **Phoenix Image**: `us-central1-docker.pkg.dev/abridge-artifact-registry/coder/phoenix:latest`
- **Use Cases**: Development with observability, debugging, performance monitoring, trace analysis

### CPU K8s Template

- **Purpose**: Lightweight CPU-based development workspaces optimized for performance
- **Features**: VS Code, Cursor IDE, Git integration, Python & Jupyter support, no sidecars for maximum performance
- **Resources**: 4-16 CPU cores, 8-32GB RAM, 16-1024GB storage
- **Base Image**: `us-central1-docker.pkg.dev/abridge-artifact-registry/coder/base:latest`
- **Use Cases**: CPU-intensive development, code review and analysis, testing environments, resource-conscious projects

### GPU K8s Template

- **Purpose**: GPU-accelerated workspaces for ML/AI development
- **Features**: NVIDIA GPU support, VS Code, Cursor IDE, simplified repository management
- **Resources**: 4-16 CPU cores, 16-1024GB RAM, 16-1024GB storage, configurable GPUs
- **GPU Support**: NVIDIA L4, H100 (80GB) with multi-GPU configuration
- **Base Image**: `us-central1-docker.pkg.dev/abridge-artifact-registry/coder/gpu:latest`

### PHI GPU K8s Template

- **Purpose**: PHI-compliant GPU-accelerated workspaces for secure healthcare ML/AI development
- **Features**: NVIDIA GPU support, browser-only VS Code, complete network isolation, PHI compliance mode
- **Security**: Zero egress network traffic, disabled SSH/port forwarding/desktop apps, air-gapped environment
- **Resources**: 4-16 CPU cores, 16-1024GB RAM, 16-1024GB storage, configurable GPUs
- **GPU Support**: NVIDIA L4, H100 (80GB) with multi-GPU configuration
- **Base Image**: `us-central1-docker.pkg.dev/abridge-artifact-registry/coder/phi-gpu:latest`
- **Network Policy**: Dedicated `networkPolicyPhi` with complete egress blocking for HIPAA/PHI compliance
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
- Ensure complete network isolation is working (no egress traffic allowed)
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
