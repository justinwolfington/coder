---
display_name: Clinician Kubernetes Workspace
description: Provision specialized Kubernetes workspaces for clinical development
icon: /icon/k8s.svg
maintainer_github: abridgeai
verified: true
tags: [kubernetes, container, clinical, development]
---

# Clinician Development on Kubernetes

A Kubernetes workspace template optimized for clinical development with pre-configured access to Abridge services.

## Features

- **Git Integration**: Clone repositories with a simple dropdown selection
- **Resource Configuration**: Customize CPU (4-8 cores), memory (6-8GB), and storage
- **Pre-configured Environment**: Access to EYES, ELMS, and other internal services
- **Code-Server**: VS Code in the browser
- **Performance Monitoring**: CPU, memory, and disk usage metrics
- **Development Tools**: Python with UV package manager, Google Cloud SDK

## Architecture

- Kubernetes deployment with a single pod
- Persistent volume for `/home/vscode` (data persists between restarts)
- Code-Server instance (VS Code in browser)
- Automatic Git repository cloning to `/home/vscode/{repo-name}`

## Container Details

- Base image: `us-central1-docker.pkg.dev/abridge-artifact-registry/coder/base:641aa9e`
- Authentication: Uses automatic Kubernetes credential detection
- Security: Runs as non-root user
- Package Management: UV automatically installed in user's home directory
- User: Container uses the VS Code devcontainer user with home directory at `/home/vscode`

## Workspace Creation Form

When creating a workspace, parameters appear in this order:
1. Repository Selection (dropdown)
2. Custom Repository URL (if "Custom Repository" selected)
3. CPU
4. Memory
5. Home disk size

## Repository Selection

1. **Completion Service**: Clones the completion-service repository
2. **Custom Repository**: Clone any Git repository

Repositories are cloned to `/home/vscode/{repo-name}`.

## Resource Customization

- **CPU**: Choose between 4, 6, or 8 cores
- **Memory**: Select 6GB or 8GB of RAM
- **Storage**: Configure persistent storage size (default: 10GB)

## Usage

1. Create a workspace with this template
2. Select repository and configure resources
3. Start the workspace
4. Connect via web IDE or SSH

## Environment Variables

The workspace includes environment variables for internal services:
```
EYES_API_URL=http://eyes-v1-eyes-new-api.eyes-v1.svc.cluster.local/api
ELMS_API_URL=http://elms-api.elms.svc.cluster.local
ELMS_BASE_URL=http://elms-api.elms.svc.cluster.local
PF_TRACING_SKIP_EXPORTER_SETUP=false
PF_DISABLE_TRACING=false
PATH="$HOME/.local/bin:$PATH"
```

These variables are automatically loaded in bash, zsh, and profile scripts.

## Available Tools

- **UV**: Fast Python package manager (automatically installed at `~/.local/bin/uv`)
- **Google Cloud SDK**: Access with `gcloud` command
- **Python 3.11**: Default Python environment

## Customization & Troubleshooting

- Add repositories to the selection dropdown in the Terraform configuration
- Customize the base image with additional tools
- Check workspace logs for errors if you encounter issues
- The initialization script will automatically install UV if not found
- For more help, contact the Abridge DevOps team
