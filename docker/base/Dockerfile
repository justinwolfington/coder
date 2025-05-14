# Base image
FROM python:3.11-slim

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

FROM base AS builder

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0

# Copy UV binary from official image and set up
COPY --from=ghcr.io/astral-sh/uv:0.7.3 /uv /bin/uv


# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends build-essential curl && rm -rf /var/lib/apt/lists/*

# Install Google Cloud SDK
RUN curl -fsSLO "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz" && \
    tar -xzf google-cloud-cli-linux-x86_64.tar.gz && \
    ./google-cloud-sdk/install.sh --quiet --command-completion=true --path-update=true && \
    rm -rf google-cloud-cli-linux-x86_64.tar.gz google-cloud-sdk/.install

# Install keyring and create marker files
RUN mkdir -p /usr/local/etc/uv && \
    uv tool install keyring --with keyrings.google-artifactregistry-auth && \
    uv tool list > /usr/local/etc/uv/tools_installed
