# Clinician K8s Template with Arize Phoenix

This Coder template provisions Kubernetes Deployments as workspaces with enhanced tracing and monitoring capabilities via Arize Phoenix.

## Features

- **Dynamic Resource Allocation**: Configure CPU (4-16 cores), memory (8-64 GB), and home disk size (16-1024 GB)
- **Git Repository Integration**: Automatically clone repositories with git-config and cursor IDE support
- **Code Server**: Web-based VS Code environment with Python and Jupyter extensions
- **Arize Phoenix Integration**: Optional sidecar container for tracing and monitoring
- **Persistent Storage**: Home directory persistence across workspace restarts
- **Advanced Monitoring**: Built-in metrics for CPU, memory, and disk usage

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

### Enable Arize Phoenix
- **Type**: Boolean
- **Default**: `true`
- **Description**: Enable Arize Phoenix sidecar for tracing and monitoring

## Arize Phoenix Integration

When enabled, this template includes:

- **Phoenix Web UI**: Accessible at `http://localhost:6006`
- **OTLP Traces**: Automatic trace collection endpoint at `http://localhost:6006/v1/traces`
- **Environment Variables**: Pre-configured for Arize Phoenix tracing
- **Health Checks**: Built-in liveness and readiness probes
- **Resource Limits**: Dedicated CPU and memory allocation for Phoenix

### Phoenix Environment Variables

The template automatically configures the following environment variables when Phoenix is enabled:

- `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`: Points to Phoenix trace endpoint
- `PF_TRACING_SKIP_EXPORTER_SETUP`: Skips default exporter setup
- `PF_TRACING_SKIP_LOCAL_SETUP`: Skips local tracing setup
- `PF_DISABLE_TRACING`: Ensures tracing is enabled

## Applications

### Code Server
- **URL**: `http://localhost:13337`
- **Features**: Python and Jupyter extensions pre-installed
- **Health Check**: Built-in health monitoring

### Arize Phoenix (Optional)
- **URL**: `http://localhost:6006`
- **Features**: Tracing and monitoring dashboard
- **Health Check**: HTTP health monitoring

## Architecture

The template creates:

1. **Main Container**: Development environment with code-server
2. **Phoenix Sidecar**: (Optional) Arize Phoenix for tracing
3. **Persistent Volume**: Home directory storage
4. **Kubernetes Deployment**: With pod anti-affinity rules
5. **Metadata Resources**: Workspace information display

## Resource Requirements

### Main Container
- **CPU**: User-defined (4-16 cores)
- **Memory**: User-defined (8-64 GB)
- **Storage**: User-defined (16-1024 GB)

### Phoenix Sidecar (when enabled)
- **CPU**: 500m requests, 1000m limits
- **Memory**: 512Mi requests, 1Gi limits
- **Storage**: Ephemeral volume for Phoenix data

## Security

- **Non-root**: Runs with user ID 1000
- **FS Group**: 1000 for file system permissions
- **Security Context**: Proper user and group isolation
