# Docker Images

This directory contains Dockerfiles for various images used in the Coder development environment.

## Available Images

### Base Image (`base.Dockerfile`)

**Purpose**: CPU-based development environment with Python and essential tools
**Registry**: `us-central1-docker.pkg.dev/abridge-artifact-registry/coder/base:latest`

**Features**:
- Python 3.11 with UV package manager
- Google Cloud SDK
- Keyring for Google Artifact Registry authentication
- Development tools and utilities

**Use Case**: CPU-only workspaces for general development

### GPU Image (`gpu.Dockerfile`)

**Purpose**: GPU-accelerated development environment for ML/AI workloads
**Registry**: `us-central1-docker.pkg.dev/abridge-artifact-registry/coder/gpu:latest`

**Features**:
- NVIDIA CUDA 12.6.3 with cuDNN
- Python 3.11 with UV package manager
- Google Cloud SDK
- GPU development tools
- Essential system utilities

**Use Case**: GPU-accelerated workspaces for machine learning and AI development

### Phoenix Image (`phoenix.Dockerfile`)

**Purpose**: Custom Arize Phoenix observability and tracing platform based on official image
**Base Image**: `arizephoenix/phoenix:latest`
**Registry**: `us-central1-docker.pkg.dev/abridge-artifact-registry/coder/phoenix:latest`

**Features**:
- Official Arize Phoenix server with custom configuration
- All environment variables pre-configured for production deployment
- Built-in health checks and curl for monitoring
- OTLP trace collection endpoints configured
- Optimized for Kubernetes sidecar deployment

**Pre-configured Environment Variables**:
- `NODE_ENV=production`
- `PHOENIX_PORT=6006` (HTTP server port)
- `PHOENIX_GRPC_PORT=4317` (gRPC server port)
- `PHOENIX_WORKING_DIR=/tmp/phoenix` (Data storage directory)
- `PHOENIX_HOST=0.0.0.0` (Server bind address)
- `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:6006/v1/traces`
- `PF_TRACING_SKIP_EXPORTER_SETUP=true`
- `PF_TRACING_SKIP_LOCAL_SETUP=true`
- `PF_DISABLE_TRACING=false`

**Ports**:
- **6006**: Phoenix Web UI (HTTP)
- **4317**: OTLP traces (gRPC)

**Benefits**:
- **Simplified Deployment**: No need to configure environment variables in Kubernetes
- **Consistent Configuration**: Same settings across all deployments
- **Easy Updates**: Centralized configuration in Docker image
- **Health Monitoring**: Built-in health checks and monitoring tools

**Use Case**: Sidecar container for tracing and monitoring in development workspaces

## Build and Deployment

All images are built automatically via GitHub Actions when changes are detected in the `docker/` directory:

1. **Build**: Images are built and tagged with the commit SHA
2. **Push**: Images are pushed to Google Artifact Registry
3. **Promote**: On merge to main, images are tagged as `latest`

### Manual Build

To build images locally:

```bash
# Base image
docker build -f docker/base.Dockerfile -t coder/base:local .

# GPU image
docker build -f docker/gpu.Dockerfile -t coder/gpu:local .

# Phoenix image
docker build -f docker/phoenix.Dockerfile -t coder/phoenix:local .
```

### Registry Access

Images are stored in Google Artifact Registry:
- **Project**: `abridge-artifact-registry`
- **Registry**: `us-central1-docker.pkg.dev`
- **Repository**: `coder`

## Security

### Base and GPU Images
- Use official base images from Microsoft and NVIDIA
- Include security updates and patches
- UV package manager for secure Python package installation

### Phoenix Image
- Runs as non-root user (UID 1000)
- Minimal attack surface with slim Python base
- Health checks for container monitoring
- Secure default configuration

## Integration with Coder Templates

### CPU Template (`cpu-k8s`)
Uses the base image for lightweight development environments without additional monitoring.

### Clinician Template (`clinician-k8s`)
Uses both base image (main container) and Phoenix image (sidecar) for enhanced tracing and monitoring.

### GPU Template (`gpu-k8s`)
Uses the GPU image for machine learning and AI development workloads.

## Monitoring and Observability

The Phoenix image provides:
- **Web UI**: Visual interface for trace analysis
- **OTLP Endpoint**: Standard telemetry collection
- **Metrics**: Performance and usage monitoring
- **Health Checks**: Container status monitoring

Access Phoenix UI at `http://localhost:6006` when deployed as a sidecar.
