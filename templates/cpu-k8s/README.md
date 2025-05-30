---
display_name: CPU K8s
description: CPU-based Kubernetes development workspace
icon: /emojis/1f33c.png
maintainer_github: abridgeai
verified: true
tags: [kubernetes, development, github, cursor]
---

# CPU K8s Template

Lightweight CPU-based Kubernetes development workspace optimized for performance.

## Features

- **VS Code & Cursor IDE**: Web-based and desktop development environments
- **Git Integration**: Automatic repository cloning and configuration
- **Python & Jupyter**: Pre-installed extensions and support
- **Persistent Storage**: Home directory persists across restarts
- **Resource Monitoring**: Built-in CPU, memory, and disk metrics
- **Lightweight**: No sidecars for maximum performance

## Parameters

| Parameter | Range | Default | Description |
|-----------|-------|---------|-------------|
| Repository URL | - | completion-service | GitHub repository to clone |
| CPU Cores | 4-16 | 4 | CPU cores allocated |
| Memory | 8-64 GB | 8 GB | Memory allocated |
| Home Disk | 16-1024 GB | 16 GB | Persistent storage size |

## Applications

### Code Server
- **Access**: `http://localhost:13337`
- **Features**: Python, Jupyter extensions

## Architecture

**Main Container:**
- Development environment with code-server
- User-defined resources (4-16 CPU, 8-64GB RAM)
- Full resource allocation (no sidecars)

**Storage:**
- Persistent home directory
- Configurable disk size

## Use Cases

- CPU-intensive development
- Code review and analysis
- Testing environments
- Resource-conscious projects
