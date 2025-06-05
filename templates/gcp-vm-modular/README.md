---
display_name: GCP VM Modular
description: GPU-accelerated Google Cloud VM workspace for ML/AI workloads with modular configuration
icon: /emojis/1f4bb.png
maintainer_github: abridgeai
verified: true
tags: [gcp, gpu, machine-learning, development, vm, cursor]
---

# GCP VM Modular Template

GPU-accelerated Google Cloud VM workspace for ML/AI development with NVIDIA GPU support and deep learning environments.

## Features

- **GPU Support**: NVIDIA L4 and H100 configurations
- **Deep Learning Images**: Pre-configured ML environments (PyTorch, TensorFlow)
- **IDE Integration**: VS Code Server and Cursor IDE
- **Security**: Shielded VMs, OS Login, least-privilege service accounts
- **High Performance**: Local SSD for H100 instances
- **Modular Design**: Clean separation of concerns

## Configuration

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| GPU Configuration | GPU setup | No GPU | No GPU, NVIDIA L4 (1x), NVIDIA L4 (2x), NVIDIA H100 80GB (8x) |
| Deep Learning Image | ML platform image | PyTorch Latest GPU | PyTorch GPU/CPU, TensorFlow GPU/CPU, Common Framework GPU/CPU, Ubuntu 22.04 LTS |

## GPU Configurations

| Option | Machine Type | GPUs | Use Case |
|--------|-------------|------|----------|
| No GPU | e2-standard-4 | 0 | Development, CPU workloads |
| NVIDIA L4 (1x) | g2-standard-8 | 1x L4 | Light ML training/inference |
| NVIDIA L4 (2x) | g2-standard-24 | 2x L4 | Medium ML workloads |
| NVIDIA H100 80GB (8x) | a3-highgpu-8g | 8x H100 | Large-scale ML training |

## Deep Learning Images

- **PyTorch Latest GPU/CPU**: Pre-configured PyTorch environment
- **TensorFlow Latest GPU/CPU**: Pre-configured TensorFlow environment
- **Common Framework GPU/CPU**: Multi-framework environment
- **Ubuntu 22.04 LTS**: Clean Ubuntu base for custom setups

## Container Details

- **Base Image**: Google Deep Learning Platform images
- **User**: Workspace owner with sudo access
- **Home**: `/home/{username}`
- **GPU**: NVIDIA drivers and CUDA pre-installed (GPU images)

## Development Environment

**VS Code (Code-Server)**

- Full VS Code experience in browser
- Pre-installed extensions for ML development
- GPU development tools available

**Cursor IDE**

- Desktop IDE with AI assistance
- Direct connection from Cursor application
- Advanced GPU development features

## Security Features

- **Shielded VM**: Secure boot, vTPM, integrity monitoring
- **OS Login**: Centralized SSH key management
- **Service Account**: Minimal required permissions
- **Network Security**: Private subnets, controlled access

## Monitoring

Built-in metrics: CPU, memory, GPU utilization, GPU memory usage, disk usage

## Prerequisites

- Google Cloud Platform project with Compute Engine API enabled
- VPC network and subnet configured
- Sufficient GPU quotas for selected GPU types
- Service account with compute instance permissions

## Usage

1. **Create Workspace**
   - Select template and configure GPU and image parameters
   - Choose appropriate GPU type for your workload
   - Launch workspace

2. **Access Applications**
   - VS Code opens automatically in browser
   - Cursor IDE available in workspace applications

---

**Note**: Requires GCP project setup with appropriate quotas and network configuration.
