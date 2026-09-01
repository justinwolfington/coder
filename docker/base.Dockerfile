# Base image - Last checked: 2026-08-31
FROM mcr.microsoft.com/devcontainers/python:3.12@sha256:7ae01dce85c08cc6b6ca411d7d7051eb100d2274ee2702120c11236692b6204f

# Label to track last verification date (forces rebuild when updated)
LABEL last_verified="2026-08-31"

# Set up environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    DEBIAN_FRONTEND=noninteractive \
    PATH="/google-cloud-sdk/bin:${PATH}"

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

# Copy UV binary from official image and set up
COPY --from=ghcr.io/astral-sh/uv:0.12.7@sha256:95f2aa1fe59274951cfe9b0cbc7972e879ff1004bc8945d130a32eb0dbd85945 /uv /bin/uv

# Install build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git-lfs \
    gcc \
    build-essential \
    vim \
    curl \
    apt-utils \
    screen \
    tmux && \
    rm -rf /var/lib/apt/lists/*

# Install Google Cloud SDK
RUN curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz && \
    tar -xf google-cloud-cli-linux-x86_64.tar.gz && \
    ./google-cloud-sdk/install.sh --usage-reporting false --rc-path ~/.bashrc --path-update true --command-completion true --quiet

# Install keyring and create marker files for Google Artifact Registry authentication
RUN mkdir -p /usr/local/etc/uv && \
    uv tool install keyring --with keyrings.google-artifactregistry-auth && \
    uv tool list > /usr/local/etc/uv/tools_installed
