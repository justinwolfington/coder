---
display_name: CPU K8s
description: CPU-based Kubernetes development workspace with configurable repository cloning
icon: /emojis/1f33c.png
maintainer_github: abridgeai
verified: true
tags: [kubernetes, container, development, github, cursor]
---

# CPU K8s Template

This Coder template provisions Kubernetes Deployments as workspaces optimized for CPU-based development workloads with a lightweight, streamlined approach.

## Features

- **Dynamic Resource Allocation**: Configure CPU (4-16 cores), memory (8-64 GB), and home disk size (16-1024 GB)
- **Git Repository Integration**: Automatically clone repositories with git-config and cursor IDE support
- **Code Server**: Web-based VS Code environment with Python and Jupyter extensions
- **Persistent Storage**: Home directory persistence across workspace restarts
- **Advanced Monitoring**: Built-in metrics for CPU, memory, and disk usage
- **Lightweight Architecture**: Optimized for performance without additional monitoring sidecars

## Parameters

### Repository URL
- **Default**: `https://github.com/abridgeai/completion-service`
- **Description**: GitHub repository URL (leave empty for no repository)
- **Mutable**: Yes

### CPU Cores
- **Range**: 4-16 cores
- **Default**: 4 cores
- **Description**: The number of CPU cores allocated to the workspace

### Memory
- **Range**: 8-64 GB
- **Default**: 8 GB
- **Description**: The amount of memory allocated to the workspace

### Home Disk Size
- **Range**: 16-1024 GB
- **Default**: 16 GB
- **Description**: The size of the persistent home directory

## Applications

### Code Server
- **URL**: `http://localhost:13337`
- **Features**: Python and Jupyter extensions pre-installed
- **Health Check**: Built-in health monitoring

## Architecture

The template creates:

1. **Main Container**: Development environment with code-server
2. **Persistent Volume**: Home directory storage
3. **Kubernetes Deployment**: With pod anti-affinity rules
4. **Metadata Resources**: Workspace information display

## Resource Requirements

### Main Container
- **CPU**: User-defined (4-16 cores)
- **Memory**: User-defined (8-64 GB)
- **Storage**: User-defined (16-1024 GB)

## Security

- **Non-root**: Runs with user ID 1000
- **FS Group**: 1000 for file system permissions
- **Security Context**: Proper user and group isolation

## Use Cases

This template is ideal for:

- **CPU-Intensive Development**: Heavy computation and processing tasks
- **Code Review**: Lightweight workspace for code reviews and analysis
- **Testing**: Basic testing environments without monitoring overhead
- **Learning**: Educational and training purposes
- **Minimal Overhead**: When you need maximum performance without additional tools
- **Resource-Conscious**: Projects requiring dedicated CPU resources

For workspaces requiring advanced tracing and monitoring capabilities, consider using the `clinician-k8s` template with Arize Phoenix integration.

## Configuration

| Parameter | Description | Default | Range |
|-----------|-------------|---------|-------|
| Repository URL | GitHub repository URL (optional) | `https://github.com/abridgeai/completion-service` | - |
| CPU Cores | CPU allocation | 4 | 4-16 |
| Memory | RAM in GB | 8 | 8-64 |
| Storage | Disk space in GB | 16 | 16-1024 |

## Repository Management

- **Default Repository**: Automatically clones completion-service repository
- **Custom Repository**: Enter any GitHub repository URL for automatic cloning
- **No Repository**: Clear the URL field for a clean workspace
- **Clone Location**: Repository clones to `/home/vscode/{repo-name}` when URL provided

## Development Environment

### Container Details
- **Base Image**: `us-central1-docker.pkg.dev/abridge-artifact-registry/coder/base:de9c4c0`
- **User**: `vscode` with sudo access
- **Home Directory**: `/home/vscode`
- **Working Directory**: Opens in repository directory or home

### Available Tools
- **Python 3.11**: With UV package manager for fast dependency management
- **Google Cloud SDK**: For cloud development and deployment
- **Git**: Automatic SSH key management and configuration
- **VS Code Extensions**: Pre-installed Python and Jupyter extensions

### Development IDEs

**VS Code (Code-Server)**
- Full VS Code experience accessible via web browser
- Pre-configured with Python and Jupyter extensions
- Automatically opens in repository directory when available
- Built-in terminal and debugging capabilities

**Cursor IDE**
- Desktop IDE with AI assistance capabilities
- Connect directly from Cursor application
- Available via workspace applications tab
- Enhanced AI-powered development features

## Performance Optimizations

- **No Sidecars**: Minimal container footprint for maximum performance
- **Dedicated Resources**: All allocated CPU and memory available to development
- **Efficient Storage**: Persistent home directory with configurable sizing
- **Pod Anti-Affinity**: Ensures optimal node placement and resource distribution

## Usage

1. **Template Selection**: Choose CPU K8s template from available options
2. **Parameter Configuration**: Adjust CPU, memory, storage, and repository settings
3. **Workspace Launch**: Deploy and wait for workspace initialization
4. **Access Methods**: Connect via VS Code browser interface or Cursor IDE application
5. **Development**: Begin coding with full access to configured resources

## Prerequisites

- **Kubernetes Cluster**: Active cluster with storage provisioning support
- **GitHub Authentication**: External authentication configured for Git integration
- **Resource Availability**: Sufficient cluster resources for requested CPU/memory allocation

## Monitoring and Health

- **Resource Metrics**: Built-in CPU, memory, and disk usage monitoring
- **Health Checks**: Automatic container health monitoring and restart policies
- **Workspace Status**: Real-time status updates and resource utilization display
