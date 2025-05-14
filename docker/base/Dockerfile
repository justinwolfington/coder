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
    UV_VERSION=0.7.3 \
    PATH="/google-cloud-sdk/bin:${PATH}"

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Google Cloud SDK
RUN curl -fsSLO "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz" && \
    tar -xzf google-cloud-cli-linux-x86_64.tar.gz && \
    ./google-cloud-sdk/install.sh --quiet --command-completion=true --path-update=true && \
    rm -rf google-cloud-cli-linux-x86_64.tar.gz google-cloud-sdk/.install

# Copy UV binary from official image and set up
COPY --from=ghcr.io/astral-sh/uv:${UV_VERSION} /uv /bin/uv

# Install keyring and create marker files
RUN mkdir -p /usr/local/etc/uv && \
    echo "${UV_VERSION}" > /usr/local/etc/uv/version && \
    uv tool install keyring --with keyrings.google-artifactregistry-auth && \
    uv tool list > /usr/local/etc/uv/tools_installed
