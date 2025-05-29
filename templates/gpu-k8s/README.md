# GPU k8s VMKiller Template

A production-ready Coder template for provisioning GPU-accelerated development workspaces in Kubernetes, optimized for machine learning, data science, and compute-intensive workloads with optional GitHub integration.

## Features

### Development Environment

- **🖥️ VS Code in Browser**: Full-featured code-server with web-based VS Code experience
- **🖱️ Cursor IDE**: Desktop IDE with AI assistance for advanced development
- **🔧 Optional GitHub Integration**: Automatic repository cloning and SSH key management
- **🚀 GPU Acceleration**: Support for NVIDIA GPUs with configurable types and counts
- **💾 Persistent Storage**: Home directory backed by Kubernetes PersistentVolumeClaim
- **📦 Custom Base Images**: Support for organization-specific GPU-enabled Docker images

### Resource Management

- **⚙️ Flexible Resource Allocation**: Configurable CPU, memory, and storage
- **🎮 GPU Selection**: Multiple GPU types (L4, H100) with multi-GPU support
- **📊 Real-time Monitoring**: Built-in metrics for resource utilization including GPU usage

### Production Ready

- **❤️ Health Checks**: Automated health monitoring for all services
- **🔒 Secure by Default**: Proper security contexts and access controls
- **📈 Auto-scaling**: Kubernetes-native scaling and resource management

## 📋 Prerequisites

### Kubernetes Cluster Requirements

- Kubernetes cluster with GPU node pools
- NVIDIA GPU device plugin installed
- StorageClass configured for persistent volumes
- Sufficient GPU and compute resources

### For GCP GKE Users

- GKE cluster with GPU-enabled node pools
- Node pools labeled with `cloud.google.com/gke-accelerator`
- Proper IAM permissions for container registry access

### Coder Setup

- Coder deployment with Kubernetes provider configured
- Access to the target Kubernetes namespace
- Container registry access for base images
- **Optional**: GitHub external authentication for Git integration features

## ⚙️ Configuration Parameters

### Repository and Integration

| Parameter | Description | Default | Type |
|-----------|-------------|---------|------|
| `repo_selection` | Repository to clone | completion-service | dropdown |
| `custom_repo` | Custom repository name | "" | string |
| `enable_github_integration` | Enable GitHub features | true | boolean |

### Compute Resources

| Parameter | Description | Default | Range |
|-----------|-------------|---------|-------|
| `cpu` | Number of CPU cores | 4 | 4-16 |
| `memory` | RAM allocation (GB) | 8 | 8-32 |
| `home_disk_size` | Persistent storage (GB) | 16 | 16-1024 |

### GPU Configuration

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| `gpu_accelerator` | GPU type selection | None | No GPU, NVIDIA L4, NVIDIA H100 (80GB) |
| `gpu_count` | Number of GPUs | 1 | 1-8 |

## 🔧 GitHub Integration

### When Enabled (default: true)

✅ **Automatic Repository Cloning**: Selected repositories are cloned to `/home/vscode/{repo-name}`
✅ **Git Configuration**: User name and email automatically configured from Coder profile
✅ **SSH Key Upload**: Public SSH keys automatically uploaded to GitHub account
✅ **Seamless Git Operations**: Push/pull without manual authentication

### When Disabled

❌ **No Repository Cloning**: Clean workspace without any repositories
❌ **No Git Configuration**: Manual Git setup required if needed
❌ **No SSH Keys**: Manual SSH key management required
✅ **Faster Startup**: Quicker workspace initialization

> **Note**: GitHub integration requires GitHub external authentication to be configured in your Coder deployment with `admin:public_key` scope.

## Quick Start

1. **Deploy the Template**

   ```bash
   # Add template to your Coder deployment
   coder templates create gpu-k8s ./templates/gpu-k8s
   ```

2. **Create a Workspace**
   - Navigate to Coder UI
   - Select "gpu-k8s" template
   - Configure repository (if GitHub integration enabled)
   - Configure resources and GPU requirements
   - Launch workspace

3. **Access Applications**
   - **VS Code**: Automatically opens in browser
   - **Cursor IDE**: Available in workspace applications

## 🔧 Customization Guide

### 1. Base Image Configuration

Update the base image repository and tag in `main.tf`:

```terraform
locals {
  base_image_repo = "your-registry.example.com/gpu-images"
  base_image_tag  = "latest"
  base_image      = "${local.base_image_repo}:${local.base_image_tag}"
}
```

### 2. Repository Configuration

Add repositories to the dropdown in `main.tf`:

```terraform
locals {
  repo_map = {
    "completion-service" = "https://github.com/abridgeai/completion-service"
    "your-repo" = "https://github.com/abridgeai/your-repo"
  }
}

data "coder_parameter" "repo_selection" {
  option {
    name  = "Your Repository"
    value = "your-repo"
  }
}
```

### 3. GPU Node Selection

Verify and customize GPU node selectors:

```terraform
gpu_node_selector = data.coder_parameter.gpu_accelerator.value != "" ? {
  "cloud.google.com/gke-accelerator" = data.coder_parameter.gpu_accelerator.value
} : {}
```

**Important**: Ensure the label keys match your cluster's GPU node labels.

### 4. GPU Types and Resources

Update available GPU options to match your cluster:

```terraform
data "coder_parameter" "gpu_accelerator" {
  # Add or modify GPU options based on your available hardware
  option {
    name  = "Your GPU Type"
    value = "your-gpu-label-value"
  }
}
```

### 5. Startup Script Customization

Modify `local.init_script` to install additional tools:

```bash
# Add custom package installations
pip install tensorflow pytorch
# Install additional VS Code extensions
$CODE_SERVER_DIR/bin/code-server --install-extension ms-toolsai.pytorch
```

### 6. Namespace Configuration

Update the default namespace if needed:

```terraform
variable "namespace" {
  default = "your-namespace"
}
```

## Monitoring and Metrics

The template includes built-in monitoring for:

- **CPU Usage**: Both container and host-level monitoring
- **Memory Usage**: RAM utilization tracking
- **GPU Usage**: NVIDIA GPU utilization monitoring via nvidia-smi
- **Disk Usage**: Home directory storage monitoring
- **Load Average**: System load metrics

## 🌐 Applications

### VS Code (code-server)

- **URL**: `http://localhost:13337`
- **Display Name**: code-server
- **Features**: Full VS Code experience with extensions
- **Default Extensions**: Python, Jupyter support
- **Health Check**: Automated monitoring on `/healthz`
- **Opens**: Repository directory (when cloned) or home directory

### Cursor IDE

- **Integration**: Direct connection from Cursor desktop application
- **Features**: AI-powered development assistance
- **Connection**: Automatic setup via Coder integration
- **Usage**: Install Cursor locally and connect to workspace

## 🔐 Security Considerations

- **Root Access**: Containers run as root for maximum flexibility
- **Privilege Escalation**: Enabled for system-level operations
- **Network Access**: Applications bound to localhost by default
- **Storage**: Persistent volumes with proper access controls
- **SSH Keys**: Automatically managed when GitHub integration enabled

## Troubleshooting

### Common Issues

#### GitHub Integration Not Working

**Symptoms**: Repository not cloned, SSH keys not uploaded
**Solutions**:

1. Verify GitHub external auth is configured in Coder deployment
2. Check user has linked GitHub account in Coder settings
3. Ensure GitHub app has `admin:public_key` scope
4. Try unlinking and relinking GitHub account

#### GPU Not Available

**Symptoms**: GPU resources not allocated or visible
**Solutions**:

1. Verify GPU device plugin is installed: `kubectl get daemonset -n kube-system`
2. Check node labels: `kubectl describe nodes`
3. Ensure `nvidia.com/gpu` resource is available
4. Verify GPU accelerator parameter matches node labels

#### Pod Scheduling Failures

**Symptoms**: Workspace fails to start, pod pending
**Solutions**:

1. Check resource availability: `kubectl describe nodes`
2. Verify node selectors match available nodes
3. Check GPU resource requests vs. availability
4. Review pod events: `kubectl describe pod <pod-name>`

#### Application Access Issues

**Symptoms**: VS Code or Cursor not accessible
**Solutions**:

1. Check application logs in Coder UI
2. Verify health checks are passing
3. Check port forwarding and network policies
4. Review startup script execution logs

### Support

- **Template Issues**: Contact Abridge DevOps team
- **Coder Platform**: Review Coder documentation
- **GPU Hardware**: Check with cluster administrators
- **GitHub Integration**: Verify external auth configuration

## Additional Resources

- [Coder Documentation](https://coder.com/docs)
- [Kubernetes GPU Documentation](https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/overview.html)
- [GCP GKE GPU Guide](https://cloud.google.com/kubernetes-engine/docs/how-to/gpus)

## 🤝 Contributing

To improve this template:

1. Test changes in a development environment
2. Update documentation for any new features
3. Ensure backward compatibility
4. Follow Terraform and Kubernetes best practices

---

**Note**: This template assumes your Kubernetes cluster has the necessary GPU device plugins and drivers installed. For production use, thoroughly test resource limits and security configurations.
