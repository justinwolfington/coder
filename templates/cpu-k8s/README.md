---
display_name: Clinician K8s
description: CPU-based Kubernetes development workspace with configurable repository cloning
icon: /emojis/1f33c.png
maintainer_github: abridgeai
verified: true
tags: [kubernetes, container, development, github, cursor]
---

# CPU K8s Template

This Coder template provisions basic Kubernetes Deployments as workspaces focused on CPU-based development workloads.

## Features

- **Dynamic Resource Allocation**: Configure CPU (4-16 cores), memory (8-64 GB), and home disk size (16-1024 GB)
- **Git Repository Integration**: Automatically clone repositories with git-config and cursor IDE support
- **Code Server**: Web-based VS Code environment with Python and Jupyter extensions
- **Persistent Storage**: Home directory persistence across workspace restarts
- **Basic Monitoring**: Built-in metrics for CPU, memory, and disk usage
- **Lightweight**: No additional sidecars or monitoring tools

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

- **General Development**: CPU-intensive development work
- **Code Review**: Lightweight workspace for code reviews
- **Testing**: Basic testing environments
- **Learning**: Educational and training purposes
- **Minimal Overhead**: When you don't need additional monitoring tools

For workspaces requiring advanced tracing and monitoring, consider using the `clinician-k8s` template with Arize Phoenix integration.

## Configuration

| Parameter | Description | Default | Range |
|-----------|-------------|---------|-------|
| Repository URL | GitHub repository URL (optional) | `https://github.com/abridgeai/completion-service` | - |
| CPU Cores | CPU allocation | 4 | 4-16 |
| Memory | RAM in GB | 8 | 8-64 |
| Storage | Disk space in GB | 16 | 16-1024 |

## Repository Management

- **Default**: Clones completion-service repository
- **Custom Repository**: Enter any GitHub repository URL
- **No Repository**: Clear field for clean workspace

Repository clones to `/home/vscode/{repo-name}` when URL provided.

## Container Details

- **Base Image**: `us-central1-docker.pkg.dev/abridge-artifact-registry/coder/base:de9c4c0`
- **User**: `vscode` with sudo access
- **Home**: `/home/vscode`

## Available Tools

- Python 3.11 with UV package manager
- Google Cloud SDK
- Git with automatic SSH key management
- VS Code (browser) and Cursor IDE

## Development Environment

**VS Code (Code-Server)**

- Full VS Code experience in browser
- Pre-installed Python and Jupyter extensions
- Opens in repository directory or home

**Cursor IDE**

- Desktop IDE with AI assistance
- Connect from Cursor application
- Available via workspace applications

## Usage

1. Select template and configure parameters
2. Launch workspace
3. Access via VS Code or Cursor IDE

## Prerequisites

- Kubernetes cluster with storage support
- GitHub external authentication for Git integration
