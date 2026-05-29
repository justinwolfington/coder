# Base image - Last checked: 2026-05-29
FROM nvcr.io/nvidia/cuda:12.9.1-cudnn-devel-ubuntu22.04

# Label to track last verification date (forces rebuild when updated)
LABEL last_verified="2026-05-29"

# Set up environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    DEBIAN_FRONTEND=noninteractive \
    PATH="/root/.local/bin:/google-cloud-sdk/bin:${PATH}"

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

# Copy UV binary from official image and set up
COPY --from=ghcr.io/astral-sh/uv:0.11.17 /uv /bin/uv

# Copy Node.js from official image
COPY --from=node:24 /usr/local/bin/node /usr/local/bin/node
COPY --from=node:24 /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# Install build dependencies and system packages
# Removed openssh-client and rsync to prevent data leakage
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git \
    gcc \
    build-essential \
    sudo \
    patch \
    vim \
    wget \
    curl \
    net-tools \
    apt-utils \
    screen \
    tmux \
    ranger && \
    rm -rf /var/lib/apt/lists/*

# Install Google Cloud SDK
RUN curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz && \
    tar -xf google-cloud-cli-linux-x86_64.tar.gz && \
    ./google-cloud-sdk/install.sh --usage-reporting false --rc-path ~/.bashrc --path-update true --command-completion true --quiet

# Install keyring and create marker files for Google Artifact Registry authentication
RUN mkdir -p /usr/local/etc/uv && \
    uv tool install keyring --with keyrings.google-artifactregistry-auth && \
    uv tool list > /usr/local/etc/uv/tools_installed

# Install code-server and VS Code extensions
ENV CODE_SERVER_VERSION=4.122.0
RUN mkdir -p /opt/code-server && \
    curl -fsSL https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz | \
    tar -xz -C /opt/code-server --strip-components=1 && \
    ln -s /opt/code-server/bin/code-server /usr/local/bin/code-server

# Pre-install VS Code extensions
RUN mkdir -p /opt/code-server-extensions && \
    code-server --extensions-dir /opt/code-server-extensions \
        --install-extension ms-python.python && \
    code-server --extensions-dir /opt/code-server-extensions \
        --install-extension ms-toolsai.jupyter && \
    code-server --extensions-dir /opt/code-server-extensions \
        --install-extension ms-vscode.vscode-typescript-next

# Create writable directories for code-server runtime
RUN mkdir -p /tmp/code-server-data /tmp/code-server-config && \
    chmod 777 /tmp/code-server-data /tmp/code-server-config
