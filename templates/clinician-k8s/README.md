---
display_name: Clinician Kubernetes Workspace
description: Provision specialized Kubernetes workspaces for clinical development
icon: /icon/k8s.svg
maintainer_github: abridgeai
verified: true
tags: [kubernetes, container, clinical, development]
---

## Table of Contents

- [Clinician Development on Kubernetes](#clinician-development-on-kubernetes)
  - [Features](#features)
  - [Architecture](#architecture)
  - [Container Details](#container-details)
  - [Workspace Creation Form](#workspace-creation-form)
  - [Repository Selection](#repository-selection)
  - [Resource Customization](#resource-customization)
  - [Usage](#usage)
  - [Available Tools](#available-tools)
  - [Customization \& Troubleshooting](#customization--troubleshooting)

# Clinician Development on Kubernetes

A Kubernetes workspace template optimized for clinical development with pre-configured access to Abridge services.

## Features

- **Git Integration**: Clone repositories with a simple dropdown selection.
- **Resource Configuration**: Customize CPU, memory, and storage.
- **Pre-configured Environment**: Access to essential Abridge services.
- **Code-Server**: VS Code in the browser.
- **Performance Monitoring**: CPU, memory, and disk usage metrics.
- **Development Tools**: Python with UV package manager, Google Cloud SDK.

## Architecture

- Kubernetes deployment with a single pod.
- Persistent volume for `/home/vscode`.
- Code-Server instance (VS Code in browser).
- Automatic Git repository cloning.

## Container Details

- Base image: `mcr.microsoft.com/devcontainers/python:3.11` as builder
- Package Management: UV (`ghcr.io/astral-sh/uv:0.7.3`) automatically installed.

## Workspace Creation Form

When creating a workspace, parameters appear in this order:

1. Repository Selection
2. Custom Repository URL (if "Custom Repository" selected)
3. CPU
4. Memory
5. Home disk size

## Repository Selection

1. **Completion Service**: Clones the `abridgeai/completion-service` repository.
2. **Custom Repository**: Clone any Git repository from the `abridgeai` GitHub organization.

Repositories are cloned to `/home/vscode/{repo-name}`.

## Resource Customization

- **CPU**: 4-16 cores (default: 4)
- **Memory**: 8-32GB RAM (default: 8GB)
- **Storage**: 16-1024GB (default: 16GB)

## Usage

1. Create a workspace using this template.
2. Select a repository and configure resources.
3. Start the workspace.
4. Connect via the web IDE or SSH.

## Available Tools

- **UV**: Fast Python package manager. Includes `keyring` with `keyrings.google-artifactregistry-auth`.
- **Google Cloud SDK**: Access with `gcloud`.
- **Python 3.11**: Default Python environment.

## Customization & Troubleshooting

- Add repositories to the dropdown via Terraform configuration.
- Customize the base image for additional tools.
- Check workspace logs for errors.
- Contact the Abridge DevOps team for further assistance.
