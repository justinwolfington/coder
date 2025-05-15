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
    OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:23333/v1/traces \
    PATH="/google-cloud-sdk/bin:${PATH}"

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

# Copy UV binary from official image and set up
COPY --from=ghcr.io/astral-sh/uv:0.7.3 /uv /bin/uv


# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends build-essential curl && rm -rf /var/lib/apt/lists/*

# Install Google Cloud SDK
RUN curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz && \
    tar -xf google-cloud-cli-linux-x86_64.tar.gz && \
    ./google-cloud-sdk/install.sh --usage-reporting false --rc-path ~/.bashrc --path-update true --command-completion true --quiet

# Install keyring and create marker files
RUN mkdir -p /usr/local/etc/uv && \
    uv tool install keyring --with keyrings.google-artifactregistry-auth && \
    uv tool list > /usr/local/etc/uv/tools_installed
