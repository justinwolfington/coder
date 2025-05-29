---
display_name: GPU K8s
description: GPU-accelerated Kubernetes development workspace for ML/AI workloads
icon: /emojis/1f916.png
maintainer_github: abridgeai
verified: true
tags: [kubernetes, gpu, machine-learning, development, github, cursor]
---

# GPU K8s Template

GPU-accelerated Kubernetes workspace for ML/AI development with NVIDIA GPU support.

## Features

- NVIDIA GPU acceleration (L4, H100)
- VS Code (browser) and Cursor IDE integration
- Single URL input for repository cloning
- Configurable resources: CPU, memory, storage, GPUs
- Real-time monitoring including GPU usage
- Root access for unrestricted development

## Configuration

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| Repository URL | GitHub repository URL (optional) | `https://github.com/abridgeai/completion-service` | - |
| CPU Cores | CPU allocation | 4 | 4-16 |
| Memory | RAM in GB | 16 | 16-1024 |
| Storage | Disk space in GB | 16 | 16-1024 |
| GPU Type | GPU accelerator | None | None, NVIDIA L4, NVIDIA H100 (80GB) |
| GPU Count | Number of GPUs | 1 | 1-8 |

## Repository Management

- **Default**: Clones completion-service repository
- **Custom Repository**: Enter any GitHub repository URL
- **No Repository**: Clear field for clean workspace

Repository clones to `/root/{repo-name}` when URL provided.

## Container Details

- **Base Image**: `us-central1-docker.pkg.dev/abridge-artifact-registry/coder/gpu:de9c4c0`
- **User**: Root with full GPU access
- **Home**: `/root`
- **GPU**: NVIDIA drivers and CUDA pre-installed

## Development Environment

**VS Code (code-server)**

- Full VS Code experience in browser
- Pre-installed Python and Jupyter extensions
- GPU development tools available

**Cursor IDE**

- Desktop IDE with AI assistance
- Direct connection from Cursor application
- Advanced GPU development features

## Prerequisites

- Kubernetes cluster with GPU nodes and NVIDIA device plugin
- Node pools labeled with `cloud.google.com/gke-accelerator` (for GKE)
- GitHub external authentication for Git integration

## Usage

1. **Create Workspace**
   - Select template and configure parameters
   - Choose GPU type and count
   - Launch workspace

2. **Access Applications**
   - VS Code opens automatically in browser
   - Cursor IDE available in workspace applications

## Monitoring

Built-in metrics: CPU, memory, GPU utilization, disk usage

---

**Note**: Requires Kubernetes cluster with GPU support and NVIDIA drivers.
