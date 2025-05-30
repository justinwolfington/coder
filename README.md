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
    ├── gpu-k8s/          # GPU-based workspace template
    └── templates-config.json  # Template configuration
```

## Available Templates

### Clinician K8s Template

- **Purpose**: CPU-based development workspaces for general development
- **Features**: VS Code, Cursor IDE, simplified repository management, GitHub integration
- **Resources**: 4-16 CPU cores, 8-64GB RAM, 16-1024GB storage
- **Base Image**: `us-central1-docker.pkg.dev/abridge-artifact-registry/coder/base:latest`

### GPU K8s Template

- **Purpose**: GPU-accelerated workspaces for ML/AI development
- **Features**: NVIDIA GPU support, VS Code, Cursor IDE, simplified repository management
- **Resources**: 4-16 CPU cores, 16-1024GB RAM, 16-1024GB storage, configurable GPUs
- **GPU Support**: NVIDIA L4, H100 (80GB) with multi-GPU configuration
- **Base Image**: `us-central1-docker.pkg.dev/abridge-artifact-registry/coder/gpu:latest`

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

**Performance Issues**
- Adjust resource limits based on workload requirements
- Monitor workspace metrics via built-in monitoring
- Use higher memory allocations for resource-intensive tasks
