#!/bin/bash
set -euo pipefail

echo "Initializing environment for ${username}..."

# Harden OS: Update and upgrade
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# Install essential tools
apt-get install -y curl wget git vim htop unzip jq sudo build-essential

# User setup with sudo and docker
if ! id "${username}" &>/dev/null; then
    useradd -m -s /bin/bash "${username}"
    echo "${username} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${username}
    chmod 0440 /etc/sudoers.d/${username}
    usermod -aG sudo "${username}"
fi

chown -R "${username}:${username}" "/home/${username}"

# Install Docker (if not already)
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    usermod -aG docker "${username}"
fi

# Node.js LTS (if not present)
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt-get install -y nodejs
fi

# Go (if not present)
if ! command -v go &>/dev/null; then
    wget -q https://go.dev/dl/go1.21.5.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    rm go1.21.5.linux-amd64.tar.gz
fi

# GPU Drivers (if needed)
if [[ "${gpu_type}" != "none" ]]; then
  echo "🔧 GPU requested, ensuring drivers..."
  if ! command -v nvidia-smi &>/dev/null && [ -f /opt/deeplearning/install-driver.sh ]; then
      /opt/deeplearning/install-driver.sh --quiet --accept-license || echo 'Driver installation attempted'
  fi
  nvidia-smi || echo 'nvidia-smi not available yet.'
fi

# Mount local SSDs if available (for H100 instances)
if [[ "${gpu_type}" == "nvidia-h100-80gb" ]]; then
    echo "🔧 Setting up local NVMe storage..."
    mkdir -p /mnt/nvme
    # Find and mount NVMe devices
    for device in /dev/nvme*n1; do
        if [[ -e "$device" ]]; then
            mount_point="/mnt/nvme/$(basename "$device")"
            mkdir -p "$mount_point"
            mkfs.ext4 -F "$device" || echo "Failed to format $device"
            mount "$device" "$mount_point" || echo "Failed to mount $device"
            chown -R "${username}:${username}" "$mount_point"
        fi
    done
    echo "Local NVMe storage ready"
fi

# IDE tools (VS Code server)
su - "${username}" -c "
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone
    mkdir -p ~/.config/code-server
    cat > ~/.config/code-server/config.yaml <<EOL
bind-addr: 0.0.0.0:8080
auth: none
cert: false
EOL
"

# Setup user environment
su - "${username}" -c "
    export HOME=/home/${username}
    echo 'export PATH=\$PATH:/usr/local/go/bin:\$HOME/go/bin' >> ~/.bashrc
    echo 'export HOME=/home/${username}' >> ~/.bashrc
    mkdir -p ~/workspace ~/projects
    git config --global init.defaultBranch main
    git config --global user.name '${username}'
    git config --global user.email '${useremail}'
"

# Set up environment variables for the coder agent
echo "export HOME=/home/${username}" >> /etc/environment
echo "export USER=${username}" >> /etc/environment

echo "Workspace setup complete for ${username}!"
echo "Machine: ${gpu_type}"
echo "Image: ${dl_image}"
echo "User: ${username}"
echo "Email: ${useremail}"

# Cleanup (optional, for security)
apt-get clean
