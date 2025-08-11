---
display_name: GPU K8s
description: GPU-accelerated Kubernetes workspace for ML/AI development
icon: /emojis/1f916.png
maintainer_github: abridgeai
verified: true
tags: [kubernetes, gpu, machine-learning, development, github, cursor]
---

# GPU K8s Template

GPU-accelerated Kubernetes workspace for ML/AI development with NVIDIA GPU support.

## Features

- **NVIDIA GPU Support**: L4, H100 accelerators with multi-GPU support
- **VS Code & Cursor IDE**: Web-based and desktop development environments
- **Git Integration**: Automatic repository cloning and configuration
- **Python & Jupyter**: Pre-installed extensions and ML frameworks
- **Root Access**: Unrestricted development environment
- **GPU Monitoring**: Real-time GPU utilization metrics

## Parameters

| Parameter | Range | Default | Description |
|-----------|-------|---------|-------------|
| Repository URL | - | bilrost | GitHub repository to clone |
| CPU Cores | 8-16 | 8 | CPU cores allocated |
| Memory | 16-32 GB | 16 GB | Memory allocated |
| Home Disk | 64-1024 GB | 64 GB | Persistent storage size |
| GPU Type | - | None | None, NVIDIA L4, NVIDIA H100 (80GB) |
| GPU Count | 1-8 | 1 | Number of GPUs |

## Applications

### Code Server
- **Access**: `http://localhost:13337`
- **Features**: Python, Jupyter, GPU development tools

## Architecture

**Main Container:**
- Development environment with GPU access
- User-defined resources + GPU allocation
- Root user with CUDA pre-installed

**Storage:**
- Persistent home directory
- Repository clones to `/root/{repo-name}`

## Prerequisites

- Kubernetes cluster with GPU nodes
- NVIDIA device plugin installed
- Node pools with `cloud.google.com/gke-accelerator` labels (GKE)

## Use Cases

- Machine learning model training
- GPU-accelerated computation
- AI/ML research and development
- CUDA programming
