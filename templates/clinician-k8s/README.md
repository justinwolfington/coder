---
display_name: Clinician K8s
description: CPU-based Kubernetes development workspace with configurable repository cloning
icon: /emojis/1f33c.png
maintainer_github: abridgeai
verified: true
tags: [kubernetes, container, development, github, cursor]
---

# Clinician K8s Template

CPU-based Kubernetes development workspace with VS Code and Cursor IDE support.

## Features

- Single URL input for repository cloning
- VS Code (browser) and Cursor IDE integration
- Configurable resources: CPU, memory, storage
- Automatic Git setup with SSH keys
- Pre-configured development tools

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
