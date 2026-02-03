#!/bin/bash

# Exit on any error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== NVIDIA Driver, Docker, and NVIDIA Runtime Installation ===${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

# Update system
echo -e "${YELLOW}Updating system packages...${NC}"
apt update && apt upgrade -y

# Install prerequisites
echo -e "${YELLOW}Installing prerequisites...${NC}"
apt install -y build-essential dkms software-properties-common \
    apt-transport-https ca-certificates curl gnupg lsb-release \
    wget linux-headers-$(uname -r)

# ==========================================
# NVIDIA Driver Installation
# ==========================================
echo -e "${GREEN}=== Installing NVIDIA Driver 580.105.08 ===${NC}"

# Remove existing NVIDIA drivers (optional but recommended)
echo -e "${YELLOW}Removing old NVIDIA drivers...${NC}"
apt remove --purge -y 'nvidia-*' || true
apt autoremove -y

# Download NVIDIA Driver 580.105.08
DRIVER_VERSION="580.105.08"
DRIVER_URL="https://us.download.nvidia.com/XFree86/Linux-x86_64/${DRIVER_VERSION}/NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run"
DRIVER_FILE="NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run"

echo -e "${YELLOW}Downloading NVIDIA Driver ${DRIVER_VERSION}...${NC}"
cd /tmp
wget -O ${DRIVER_FILE} ${DRIVER_URL}

# Make installer executable
chmod +x ${DRIVER_FILE}

# Disable nouveau driver
echo -e "${YELLOW}Disabling nouveau driver...${NC}"
cat > /etc/modprobe.d/blacklist-nouveau.conf <<EOF
blacklist nouveau
options nouveau modeset=0
EOF

# Update initramfs
update-initramfs -u

# Install NVIDIA Driver
echo -e "${YELLOW}Installing NVIDIA Driver (this may take a few minutes)...${NC}"
./${DRIVER_FILE} --silent --dkms --no-questions

# Verify installation
if nvidia-smi; then
    echo -e "${GREEN}NVIDIA Driver installed successfully!${NC}"
else
    echo -e "${RED}NVIDIA Driver installation failed!${NC}"
    exit 1
fi

# ==========================================
# Docker Installation
# ==========================================
echo -e "${GREEN}=== Installing Docker ===${NC}"

# Remove old Docker versions
apt remove -y docker docker-engine docker.io containerd runc || true

# Add Docker's official GPG key
echo -e "${YELLOW}Adding Docker repository...${NC}"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Set up Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index
apt update

# Install Docker Engine
echo -e "${YELLOW}Installing Docker Engine...${NC}"
apt install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

# Start and enable Docker service
systemctl start docker
systemctl enable docker

# Verify Docker installation
if docker --version; then
    echo -e "${GREEN}Docker installed successfully!${NC}"
else
    echo -e "${RED}Docker installation failed!${NC}"
    exit 1
fi

# Test Docker
docker run --rm hello-world

# ==========================================
# NVIDIA Container Runtime Installation
# ==========================================
echo -e "${GREEN}=== Installing NVIDIA Container Runtime ===${NC}"

# Add NVIDIA Container Toolkit repository
echo -e "${YELLOW}Adding NVIDIA Container Toolkit repository...${NC}"
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
    gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Update package index
apt update

# Install NVIDIA Container Toolkit
echo -e "${YELLOW}Installing NVIDIA Container Toolkit...${NC}"
apt install -y nvidia-container-toolkit

# Configure Docker to use NVIDIA runtime
echo -e "${YELLOW}Configuring Docker for NVIDIA runtime...${NC}"
nvidia-ctk runtime configure --runtime=docker

# Restart Docker service
systemctl restart docker

# Verify NVIDIA runtime
echo -e "${YELLOW}Testing NVIDIA runtime with Docker...${NC}"
if docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi; then
    echo -e "${GREEN}NVIDIA Container Runtime installed successfully!${NC}"
else
    echo -e "${RED}NVIDIA Container Runtime test failed!${NC}"
    exit 1
fi

# ==========================================
# Post-installation steps
# ==========================================
echo -e "${GREEN}=== Post-installation Configuration ===${NC}"

# Add current user to docker group (if not root)
if [ -n "$SUDO_USER" ]; then
    echo -e "${YELLOW}Adding $SUDO_USER to docker group...${NC}"
    usermod -aG docker $SUDO_USER
    echo -e "${YELLOW}Note: Log out and back in for group changes to take effect${NC}"
fi

# Display versions
echo -e "${GREEN}=== Installation Summary ===${NC}"
echo -e "${GREEN}NVIDIA Driver Version:${NC}"
nvidia-smi --query-gpu=driver_version --format=csv,noheader
echo -e "${GREEN}Docker Version:${NC}"
docker --version
echo -e "${GREEN}NVIDIA Container Toolkit Version:${NC}"
nvidia-ctk --version

echo -e "${GREEN}=== Installation Complete! ===${NC}"
echo -e "${YELLOW}Note: A system reboot is recommended to ensure all changes take effect.${NC}"
echo -e "${YELLOW}After reboot, verify with: nvidia-smi && docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi${NC}"
