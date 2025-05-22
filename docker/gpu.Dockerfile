FROM nvidia/cuda:12.9.0-devel-ubuntu22.04

# Set non-interactive frontend and basic environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/google-cloud-sdk/bin:${PATH}" \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

USER root

# Clean up unused CUDA sources and install system packages
RUN rm -rf /etc/apt/sources.list.d/cuda* && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    git gcc build-essential \
    rsync sudo patch \
    vim wget curl \
    apt-utils screen tmux \
    byobu ranger openfortivpn && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy uv binary from upstream image
COPY --from=ghcr.io/astral-sh/uv:0.7.3 /uv /bin/uv

# Install Google Cloud SDK
RUN curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz && \
    tar -xf google-cloud-cli-linux-x86_64.tar.gz && \
    ./google-cloud-sdk/install.sh --usage-reporting false --rc-path ~/.bashrc --path-update true --command-completion true --quiet && \
    rm google-cloud-cli-linux-x86_64.tar.gz

# Install uv tools and set up tool marker
RUN mkdir -p /usr/local/etc/uv && \
    uv tool install keyring --with keyrings.google-artifactregistry-auth && \
    uv tool list > /usr/local/etc/uv/tools_installed

# Optional: Set a default working directory
WORKDIR /workspace
