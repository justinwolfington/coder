---
display_name: Clinician K8s
description: Kubernetes development workspace with Arize Phoenix tracing
icon: /emojis/1f33c.png
maintainer_github: abridgeai
verified: true
tags: [kubernetes, development, github, cursor, monitoring, tracing]
---

# Clinician K8s Template

CPU-based Kubernetes development workspace with integrated Arize Phoenix tracing and monitoring.

## Features

- **VS Code & Cursor IDE**: Web-based development environment
- **Arize Phoenix**: Built-in tracing and monitoring dashboard
- **Git Integration**: Automatic repository cloning and configuration
- **Python & Jupyter**: Pre-installed extensions and support
- **Persistent Storage**: Home directory persists across restarts
- **Resource Monitoring**: Built-in CPU, memory, and disk metrics

## Parameters

| Parameter | Range | Default | Description |
|-----------|-------|---------|-------------|
| Repository URL | - | bilrost | GitHub repository to clone |
| CPU Cores | 8-16 | 8 | CPU cores allocated |
| Memory | 16-32 GB | 16 GB | Memory allocated |
| Home Disk | 64-1024 GB | 64 GB | Persistent storage size |

## Applications

### Code Server
- **Access**: `http://localhost:13337`
- **Features**: Python, Jupyter extensions

### Arize Phoenix
- **Access**: `http://localhost:6006`
- **Features**: Tracing dashboard, OTLP endpoint

## Architecture

**Main Container:**
- Development environment with code-server
- User-defined resources (8-16 CPU, 16-32GB RAM)

**Phoenix Sidecar:**
- Tracing and monitoring (500m CPU, 512Mi RAM)
- Automatic health checks

**Storage:**
- Persistent home directory
- Ephemeral Phoenix data volume

## Environment Variables

Completion service is pre-configured to send traces to Arize Phoenix:
- `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:6006/v1/traces`
- `PF_TRACING_SKIP_EXPORTER_SETUP=true`
- `PF_TRACING_SKIP_LOCAL_SETUP=true`
- `PF_DISABLE_TRACING=false`
