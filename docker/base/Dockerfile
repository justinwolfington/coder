# Base image
FROM mcr.microsoft.com/devcontainers/python:3.11

# Set up environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    EYES_API_URL=http://eyes-v1-eyes-new.eyes-v1.svc.cluster.local/api \
    ELMS_API_URL=http://elms-api.elms.svc.cluster.local \
    ELMS_BASE_URL=http://elms-api.elms.svc.cluster.local \
    PF_TRACING_SKIP_EXPORTER_SETUP=false \
    PF_TRACING_SKIP_LOCAL_SETUP=false \
    PF_DISABLE_TRACING=false \
    OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:23333/v1/traces

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Google Cloud SDK as root first
RUN curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz && \
    tar -xf google-cloud-cli-linux-x86_64.tar.gz && \
    ./google-cloud-sdk/install.sh --usage-reporting=false --rc-path=/etc/profile.d/gcloud.sh --path-update=true --command-completion=true --quiet && \
    rm -rf google-cloud-cli-linux-x86_64.tar.gz

# Switch to vscode user for package installations
USER vscode
WORKDIR /home/vscode

# Install UV and make it available in the path
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    echo 'export PATH="/home/vscode/.local/bin:$PATH"' >> /home/vscode/.bashrc && \
    echo 'export PATH="/home/vscode/.local/bin:$PATH"' >> /home/vscode/.zshrc && \
    . /home/vscode/.local/bin/env && \
    uv tool install keyring --with keyrings.google-artifactregistry-auth

# Switch back to root for any subsequent operations
USER root
ENV PATH="/home/vscode/.local/bin:${PATH}"
