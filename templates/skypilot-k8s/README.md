---
display_name: SkyPilot K8s
description: CPU-based Kubernetes development workspace with SkyPilot integration
icon: /emojis/2601.png
maintainer_github: abridgeai
verified: true
tags: [kubernetes, skypilot, development, github, cursor, cloud]
---

# SkyPilot K8s Template

CPU-based Kubernetes development workspace with integrated SkyPilot for multi-cloud orchestration.

## Features

- **VS Code & Cursor IDE**: Web-based and desktop development environments
- **SkyPilot Integration**: Pre-installed SkyPilot for multi-cloud deployments
- **Multi-Cloud Support**: Ready for Kubernetes and GCP backends
- **Git Integration**: Automatic repository cloning and configuration
- **Python & Jupyter**: Pre-installed extensions and support
- **Persistent Storage**: Home directory persists across restarts
- **Shared Storage**: Access to shared data and home directories across workspaces
- **Resource Monitoring**: Built-in CPU, memory, and disk metrics
- **Lightweight**: No sidecars for maximum performance

## SkyPilot Configuration

The workspace automatically installs SkyPilot with:
- **Package**: `skypilot-nightly[kubernetes,gcp]==1.0.0.dev20250624`
- **Manual Setup**: Configure API and backends as needed

### Manual Configuration Steps

After workspace startup, you'll need to configure SkyPilot:

```bash
# Configure SkyPilot API login
sky api login --get-token -e https://skypilot.abridge.coffee  # for development
# or
sky api login --get-token -e https://skypilot.abridge.services  # for production

# Check SkyPilot configuration
sky check
```

## Storage Configuration

The workspace provides access to multiple storage volumes for different use cases:

### Storage Volumes

1. **Workspace Home Directory** (`/home/vscode`)
   - **Type**: Workspace-specific PVC
   - **Access Mode**: ReadWriteOnce
   - **Purpose**: Private workspace files and configurations
   - **Persistence**: Unique per workspace, isolated from other workspaces

2. **Shared Data Volume** (`/data`)
   - **Type**: Shared PVC (`data-pvc`)
   - **Access Mode**: ReadWriteMany
   - **Purpose**: Common datasets, models, and shared resources
   - **Persistence**: Shared across all workspaces

3. **Shared Home Volume** (`/shared/home`)
   - **Type**: Shared PVC (`home-pvc`)
   - **Access Mode**: ReadWriteMany
   - **Purpose**: Shared home directory resources and common configurations
   - **Persistence**: Shared across all workspaces

### PVC References

The shared PVCs are created and managed by the [skypilot-api-server](https://github.com/abridgeai/skypilot-api-server) Helm chart:

- **Data PVC**: [data-pvc.yaml](https://github.com/abridgeai/skypilot-api-server/blob/env/development/charts/templates/data-pvc.yaml)
- **Home PVC**: [home-pvc.yaml](https://github.com/abridgeai/skypilot-api-server/blob/env/development/charts/templates/home-pvc.yaml)

### Storage Use Cases

- **Private Development**: Use `/home/vscode` for personal workspace files
- **Shared Datasets**: Access common data from `/data`
- **Shared Resources**: Access shared tools and configurations from `/shared/home`
- **Collaboration**: Share files with other workspaces via shared volumes

## Parameters

| Parameter | Range | Default | Description |
|-----------|-------|---------|-------------|
| Repository URL | - | completion-service | GitHub repository to clone |
| CPU Cores | 8-16 | 8 | CPU cores allocated |
| Memory | 16-32 GB | 16 GB | Memory allocated |
| Home Disk | 64-1024 GB | 64 GB | Persistent storage size |

## Applications

### Code Server
- **Access**: `http://localhost:13337`
- **Features**: Python, Jupyter extensions

## SkyPilot Commands

Available SkyPilot commands:
- `sky status`: Check SkyPilot cluster status
- `sky check`: Verify SkyPilot configuration
- `sky launch`: Launch workloads on cloud resources
- `sky`: Full SkyPilot CLI access

## Architecture

**Main Container:**
- Development environment with code-server
- SkyPilot CLI pre-installed
- User-defined resources (8-16 CPU, 16-32GB RAM)
- Full resource allocation (no sidecars)

**Storage:**
- Workspace-specific persistent home directory (`/home/vscode`)
- Shared data volume (`/data`) for common datasets and resources
- Shared home volume (`/shared/home`) for shared configurations
- Configurable workspace disk size

## Use Cases

- Multi-cloud ML workload orchestration
- SkyPilot development and testing
- Cloud-native application development
- Distributed computing experiments
- Cost-optimized cloud resource management

## Available Endpoints

- **Development**: `https://skypilot.abridge.coffee`
- **Production**: `https://skypilot.abridge.services`
