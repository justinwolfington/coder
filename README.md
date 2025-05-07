# Coder Development Environment

This repository contains the configuration and templates for setting up development environments using Coder.

These environments are accessible at:

- Development: coder.abridge.coffee
- Staging: coder.abridge.cafe
- Production: coder.abridge.services

## Directory Structure

``` bash
coder/
├── docker-compose.yaml  # Local development setup
├── charts/             # Helm chart for Coder deployment
└── templates/          # Workspace templates
    ├── base-k8s/       # CPU-based workspace templates
    ├── gpu-k8s/        # GPU-based workspace templates
    └── common/         # Shared template resources
```

## Quick Start

### Local Development

1. Start the local development environment:

   ``` bash
   docker-compose up -d
   ```

2. Access Coder at <http://localhost:7080>

### Kubernetes Deployment

1. Update the values in `charts/coder/values.yaml`
2. Deploy using Helm:

   ``` bash
   helm install coder ./charts/coder
   ```
