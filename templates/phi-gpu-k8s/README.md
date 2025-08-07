---
display_name: PHI Workspace
description: PHI-compliant GPU-accelerated Kubernetes workspace for secure ML/AI development
icon: /emojis/1f510.png
maintainer_github: abridgeai
verified: true
tags: [kubernetes, gpu, machine-learning, phi, security, compliance, github, cursor]
---

# PHI GPU K8s Template

PHI-compliant GPU-accelerated Kubernetes workspace for secure ML/AI development with NVIDIA GPU support and healthcare data compliance.

## Features

- **PHI Compliance**: Built-in PHI compliance mode and security controls
- **NVIDIA GPU Support**: L4, H100 accelerators with multi-GPU support
- **VS Code & Cursor IDE**: Web-based and desktop development environments
- **Git Integration**: Automatic repository cloning and configuration
- **Python & Jupyter**: Pre-installed extensions and ML frameworks
- **Root Access**: Unrestricted development environment with security boundaries
- **GPU Monitoring**: Real-time GPU utilization metrics
- **Security Enhanced**: PHI-specific environment variables and configurations

## Parameters

| Parameter | Range | Default | Description |
|-----------|-------|---------|-------------|
| Repository URL | - | phi-service | GitHub repository to clone |
| CPU Cores | 8-16 | 8 | CPU cores allocated |
| Memory | 16-1024 GB | 16 GB | Memory allocated |
| Home Disk | 64-1024 GB | 64 GB | Persistent storage size |
| GPU Type | - | None | None, NVIDIA L4, NVIDIA H100 (80GB) |
| GPU Count | 1-8 | 1 | Number of GPUs |

## Applications

### Code Server (Browser-Only)
- **Access**: `http://localhost:13337`
- **Features**: Python, Jupyter, GPU development tools
- **Security**: PHI compliance mode enabled, all insecure apps disabled
- **Restrictions**: No SSH, no desktop VSCode, no port forwarding, no web terminal

## Architecture

**Main Container:**
- PHI-compliant development environment with GPU access
- User-defined resources + GPU allocation
- Root user with CUDA pre-installed
- PHI environment variables enabled

**Storage:**
- Persistent home directory with PHI compliance
- Repository clones to `/root/{repo-name}`

## PHI Compliance Features

- **Environment Variables**: `PHI_WORKSPACE=true`, `PHI_COMPLIANCE_MODE=enabled`
- **Network Policies**: Dedicated PHI network isolation
- **Labels**: `coder-phi-workspace` for proper network segmentation
- **Annotations**: PHI-enabled workspace identification
- **File Transfer Blocking**: `CODER_AGENT_BLOCK_FILE_TRANSFER=true` blocks scp, rsync, ftp, and nc commands via SSH
- **Read-Only Root Filesystem**: Prevents installation of additional tools that could bypass security

## Prerequisites

- Kubernetes cluster with GPU nodes
- NVIDIA device plugin installed
- Node pools with `cloud.google.com/gke-accelerator` labels (GKE)
- PHI network policies configured

## Network Security

This template uses dedicated PHI network policies that:
- **Complete Network Isolation**: All egress traffic is blocked (no external network access)
- **Zero Trust Architecture**: No allowed services or external communication
- **Maximum Security**: PHI workspaces are completely air-gapped from external networks

## Use Cases

- PHI-compliant machine learning model training
- Healthcare data analysis with GPU acceleration
- Secure AI/ML research and development
- CUDA programming in compliant environments
- Protected health information processing
