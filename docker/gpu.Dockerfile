# Base image - Last checked: 2026-05-05
FROM nvcr.io/nvidia/cuda:12.9.1-cudnn-devel-ubuntu22.04

# Label to track last verification date (forces rebuild when updated)
LABEL last_verified="2026-05-05"

# Set up environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    DEBIAN_FRONTEND=noninteractive \
    PATH="/root/.local/bin:/google-cloud-sdk/bin:${PATH}"

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

# Copy UV binary from official image and set up
COPY --from=ghcr.io/astral-sh/uv:0.11.7 /uv /bin/uv

# Install build dependencies and system packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git \
    gcc \
    build-essential \
    rsync \
    sudo \
    patch \
    vim \
    wget \
    curl \
    net-tools \
    apt-utils \
    screen \
    tmux \
    ranger \
    openssh-client && \
    rm -rf /var/lib/apt/lists/*

# Install Google Cloud SDK
RUN curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz && \
    tar -xf google-cloud-cli-linux-x86_64.tar.gz && \
    ./google-cloud-sdk/install.sh --usage-reporting false --rc-path ~/.bashrc --path-update true --command-completion true --quiet

# Install keyring and create marker files for Google Artifact Registry authentication
RUN mkdir -p /usr/local/etc/uv && \
    uv tool install keyring --with keyrings.google-artifactregistry-auth && \
    uv tool list > /usr/local/etc/uv/tools_installed
