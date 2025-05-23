# Coder GPU Kubernetes Template (`gpu-k8s`)

A production-ready Coder template for provisioning GPU-accelerated development workspaces in Kubernetes, optimized for machine learning, data science, and compute-intensive workloads.

## Features

### Development Environment

- **VS Code in Browser**: Full-featured code-server with web-based VS Code experience
- **Jupyter Integration**: Choose between Jupyter Lab or Jupyter Notebook
- **GPU Acceleration**: Support for NVIDIA GPUs with configurable types and counts
- **Persistent Storage**: Home directory backed by Kubernetes PersistentVolumeClaim
- **Custom Base Images**: Support for organization-specific GPU-enabled Docker images

### Resource Management

- **Flexible Resource Allocation**: Configurable CPU, memory, and storage
- **GPU Selection**: Multiple GPU types (L4, H100) with multi-GPU support
- **GCP Reservations**: Integration with Google Cloud Platform reserved instances
- **Real-time Monitoring**: Built-in metrics for resource utilization

### Production Ready

- **Health Checks**: Automated health monitoring for all services
- **Secure by Default**: Proper security contexts and access controls
- **Auto-scaling**: Kubernetes-native scaling and resource management

## 📋 Prerequisites

### Kubernetes Cluster Requirements

- Kubernetes cluster with GPU node pools
- NVIDIA GPU device plugin installed
- StorageClass configured for persistent volumes
- Sufficient GPU and compute resources

### For GCP GKE Users

- GKE cluster with GPU-enabled node pools
- Node pools labeled with `cloud.google.com/gke-accelerator`
- (Optional) Compute Engine reservations configured
- Proper IAM permissions for container registry access

### Coder Setup

- Coder deployment with Kubernetes provider configured
- Access to the target Kubernetes namespace
- Container registry access for base images

## ⚙️ Configuration Parameters

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
| `gcp_reservation_name` | GCP reservation name (optional) | "" | Any valid reservation name |

### Application Settings

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| `Notebook Type` | Jupyter variant | Jupyter Lab | Jupyter Lab, Jupyter Notebook |

## Quick Start

1. **Deploy the Template**

   ```bash
   # Add template to your Coder deployment
   coder templates create gpu-k8s ./templates/gpu-k8s
   ```

2. **Create a Workspace**
   - Navigate to Coder UI
   - Select "gpu-k8s" template
   - Configure resources and GPU requirements
   - Launch workspace

3. **Access Applications**
   - **VS Code**: Automatically opens in browser
   - **Jupyter**: Available via workspace applications menu

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

### 2. GPU Node Selection

Verify and customize GPU node selectors:

```terraform
local._base_gpu_selector = {
  "cloud.google.com/gke-accelerator" = data.coder_parameter.gpu_accelerator.value
}
```

**Important**: Ensure the label keys match your cluster's GPU node labels.

### 3. GPU Types and Resources

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

### 4. Startup Script Customization

Modify `local.init_script` to install additional tools:

```bash
# Add custom package installations
uv pip install --system tensorflow pytorch
# Install additional VS Code extensions
$CODE_SERVER_DIR/bin/code-server --install-extension ms-toolsai.pytorch
```

### 5. Namespace Configuration

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
- **Disk Usage**: Home directory storage monitoring
- **Load Average**: System load metrics


## 🌐 Applications

### VS Code (code-server)

- **URL**: `http://localhost:13337`
- **Features**: Full VS Code experience with extensions
- **Default Extensions**: Python, Jupyter support
- **Health Check**: Automated monitoring on `/healthz`

### Jupyter

- **URL**: `http://localhost:8888`
- **Types**: Lab or Notebook (configurable)
- **Features**: Token-free access, persistent notebooks
- **Health Check**: Monitoring on `/healthz/`

## 🔐 Security Considerations

- **Root Access**: Containers run as root for maximum flexibility
- **Privilege Escalation**: Enabled for system-level operations
- **Network Access**: Applications bound to localhost by default
- **Storage**: Persistent volumes with proper access controls

## Troubleshooting

### Common Issues

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

**Symptoms**: VS Code or Jupyter not accessible
**Solutions**:

1. Check application logs in Coder UI
2. Verify health check status
3. Ensure ports are not blocked
4. Check startup script execution logs

#### Storage Issues

**Symptoms**: Home directory not persistent or accessible
**Solutions**:

1. Verify PVC status: `kubectl get pvc`
2. Check StorageClass availability
3. Ensure sufficient storage quota
4. Review volume mount permissions

### GCP-Specific Issues

#### Reservation Not Used

**Symptoms**: Pods not scheduled on reserved instances
**Solutions**:

1. Verify reservation name matches exactly
2. Check node pool reservation affinity configuration
3. Ensure nodes are labeled with reservation name
4. Confirm reservation has available capacity



## Additional Resources

- [Coder Documentation](https://coder.com/docs)
- [Kubernetes GPU Documentation](https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/overview.html)
- [GCP GKE GPU Guide](https://cloud.google.com/kubernetes-engine/docs/how-to/gpus)
- [GCP Compute Reservations](https://cloud.google.com/compute/docs/instances/reservations-overview)

## 🤝 Contributing

To improve this template:

1. Test changes in a development environment
2. Update documentation for any new features
3. Ensure backward compatibility
4. Follow Terraform and Kubernetes best practices

---

**Note**: This template assumes your Kubernetes cluster has the necessary GPU device plugins and drivers installed. For production use, thoroughly test resource limits and security configurations.
