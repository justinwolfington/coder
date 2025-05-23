FROM nvcr.io/nvidia/cuda:12.9.0-cudnn-devel-ubuntu22.04

# Set up environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/google-cloud-sdk/bin:${PATH}"

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

# Copy UV binary from official image and set up
COPY --from=ghcr.io/astral-sh/uv:0.7.3 /uv /bin/uv

# Install build dependencies and system packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    gcc \
    rsync \
    sudo \
    patch \
    vim \
    wget \
    apt-utils \
    screen \
    tmux \
    ranger && \
    rm -rf /var/lib/apt/lists/*

# Install Google Cloud SDK
RUN curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz && \
    tar -xf google-cloud-cli-linux-x86_64.tar.gz && \
    ./google-cloud-sdk/install.sh --usage-reporting false --rc-path ~/.bashrc --path-update true --command-completion true --quiet

# Install keyring and create marker files
RUN mkdir -p /usr/local/etc/uv && \
    uv tool install keyring --with keyrings.google-artifactregistry-auth && \
    uv tool list > /usr/local/etc/uv/tools_installed

# # Create vscode user with sudo privileges
# RUN groupadd -g 1000 vscode && \
#     useradd -u 1000 -g 1000 -s /bin/bash -m vscode && \
#     echo "vscode ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vscode && \
#     chmod 0440 /etc/sudoers.d/vscode

# Set default working directory
WORKDIR /home/vscode
