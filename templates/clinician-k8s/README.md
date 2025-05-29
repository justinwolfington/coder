---
display_name: Completion Service
description: Provision Kubernetes Deployments as Coder workspaces, with completion-service cloned, uv and gcloud CLI installed
icon: /emojis/1f33c.png
maintainer_github: abridgeai
verified: true
tags: [kubernetes, container, completion-service, development, github, cursor]
---

## Table of Contents

- [Completion Service Development on Kubernetes](#completion-service-development-on-kubernetes)
  - [Features](#features)
  - [Architecture](#architecture)
  - [Container Details](#container-details)
  - [Workspace Creation Form](#workspace-creation-form)
  - [GitHub Integration](#github-integration)
  - [Repository Selection](#repository-selection)
  - [Resource Customization](#resource-customization)
  - [Development Environments](#development-environments)
  - [Usage](#usage)
  - [Available Tools](#available-tools)
  - [Customization \& Troubleshooting](#customization--troubleshooting)

# Completion Service Development on Kubernetes

A Kubernetes workspace template optimized for completion service development with optional GitHub integration and multiple IDE options.

## Features

- **🔧 Optional GitHub Integration**: Automatic repository cloning and SSH key management
- **🖱️ Multiple IDEs**: Choose between VS Code (code-server) and Cursor IDE
- **⚙️ Resource Configuration**: Customize CPU, memory, and storage
- **🔑 Automatic SSH Setup**: GitHub SSH keys automatically uploaded (when enabled)
- **📊 Performance Monitoring**: CPU, memory, and disk usage metrics
- **🐍 Development Tools**: Python with UV package manager, Google Cloud SDK
- **🏗️ Pre-configured Environment**: Access to essential Abridge services

## Architecture

- Kubernetes deployment with a single pod
- Persistent volume for `/home/vscode`
- Code-Server instance (VS Code in browser)
- Cursor IDE integration for desktop development
- Conditional Git repository cloning and SSH key management

## Container Details

- Base image: `us-central1-docker.pkg.dev/abridge-artifact-registry/coder/base:1402364`
- Package Management: UV with `keyring` and `keyrings.google-artifactregistry-auth`
- Git configuration and SSH key management (when GitHub integration enabled)

## Workspace Creation Form

When creating a workspace, parameters appear in this order:

1. **Repository Selection**: Choose which repository to clone
2. **Custom Repository Name**: If "Custom Repository" selected, specify repository name
3. **Enable GitHub Integration**: Toggle GitHub features on/off
4. **CPU Cores**: 4-16 cores (default: 4)
5. **Memory**: 8-32GB RAM (default: 8GB)
6. **Home Disk Size**: 16-1024GB (default: 16GB)

## GitHub Integration

When **Enable GitHub Integration** is set to `true`:

✅ **Automatic Repository Cloning**: Selected repositories are cloned to `/home/vscode/{repo-name}`
✅ **Git Configuration**: User name and email automatically configured from Coder profile
✅ **SSH Key Upload**: Public SSH keys automatically uploaded to GitHub account
✅ **Seamless Git Operations**: Push/pull without manual authentication

When **Enable GitHub Integration** is set to `false`:

❌ **No Repository Cloning**: Clean workspace without any repositories
❌ **No Git Configuration**: Manual Git setup required if needed
❌ **No SSH Keys**: Manual SSH key management required
✅ **Faster Startup**: Quicker workspace initialization

> **Note**: GitHub integration requires GitHub external authentication to be configured in your Coder deployment.

## Repository Selection

1. **Completion Service**: Clones the `abridgeai/completion-service` repository
2. **Custom Repository**: Clone any repository from the `abridgeai` GitHub organization

Repositories are cloned to `/home/vscode/{repo-name}` when GitHub integration is enabled.

## Resource Customization

- **CPU**: 4-16 cores (default: 4)
- **Memory**: 8-32GB RAM (default: 8GB)
- **Storage**: 16-1024GB (default: 16GB)

## Development Environments

### **🖥️ VS Code (Code-Server)**
- Full VS Code experience in the browser
- Pre-installed extensions: Python, Jupyter
- Accessible via workspace dashboard
- Opens in repository directory (when cloned)

### **🖱️ Cursor IDE**
- Desktop IDE with AI assistance
- Connect directly from Cursor application
- Seamless remote development experience
- Available via workspace applications

## Usage

1. **Create Workspace**: Use this template from Coder dashboard
2. **Configure Options**:
   - Choose repository (if GitHub integration enabled)
   - Set resource requirements
   - Toggle GitHub integration as needed
3. **Start Workspace**: Wait for initialization to complete
4. **Choose IDE**: Access via Code-Server or Cursor
5. **Start Developing**: Repository ready (if cloned), Git configured (if enabled)

## Available Tools

- **🐍 Python 3.11**: Default Python environment
- **📦 UV**: Fast Python package manager with keyring support
- **☁️ Google Cloud SDK**: Access with `gcloud` command
- **🔧 Git**: Pre-configured with user identity (when GitHub integration enabled)
- **🔑 SSH**: Keys automatically managed (when GitHub integration enabled)
- **📊 Monitoring**: Built-in CPU, memory, and disk usage metrics

## Customization & Troubleshooting

### **Adding Repositories**
- Update `repo_map` in `locals` section of `main.tf`
- Add new options to `repo_selection` parameter

### **GitHub Integration Issues**
- Ensure GitHub external auth is configured in Coder deployment
- Check user has linked GitHub account in Coder settings
- Verify GitHub app has `admin:public_key` scope

### **Performance Tuning**
- Adjust default resource limits in template parameters
- Monitor workspace metrics via built-in monitoring

### **Support**
- Check workspace logs for initialization errors
- Contact Abridge DevOps team for deployment-specific issues
- Review Coder documentation for general troubleshooting
