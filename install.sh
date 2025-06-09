#!/bin/bash

# One-liner installer for Pangolin + CrowdSec + Traefik
# This script downloads the docker-compose.yml and provides deployment instructions

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Configuration - Update these URLs to match your GitHub repository
GITHUB_USER="oidebrett"
GITHUB_REPO="getcontextware"
GITHUB_BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}"

echo "🚀 Pangolin + CrowdSec + Traefik Containerized Installer"
echo

# Check if we're running as root (not recommended for Docker)
if [ "$EUID" -eq 0 ]; then
    print_error "Please don't run this script as root. Run as a regular user with Docker permissions."
    exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker first:"
    echo "  curl -fsSL https://get.docker.com | sh"
    echo "  sudo usermod -aG docker \$USER"
    echo "  # Log out and back in, then run this script again"
    exit 1
fi

# Check if Docker Compose is available
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    print_error "Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Check if user is in docker group
if ! groups | grep -q docker; then
    print_error "Current user is not in the docker group. Please add yourself to the docker group:"
    echo "  sudo usermod -aG docker \$USER"
    echo "  # Log out and back in, then run this script again"
    exit 1
fi

# Create installation directory
INSTALL_DIR="pangolin-stack"
if [ -d "$INSTALL_DIR" ]; then
    print_warning "Directory $INSTALL_DIR already exists."
    read -p "Do you want to continue and overwrite? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Installation cancelled."
        exit 0
    fi
fi

print_status "Creating installation directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Download docker-compose.yml
print_status "Downloading docker-compose.yml from GitHub..."
if ! curl -fsSL "${BASE_URL}/docker-compose.yml" -o docker-compose.yml; then
    print_error "Failed to download docker-compose.yml"
    print_error "Make sure the repository exists and is accessible:"
    echo "  ${BASE_URL}/docker-compose.yml"
    exit 1
fi

print_success "docker-compose.yml downloaded successfully"

# Provide deployment instructions
echo
print_success "🎉 Setup completed! Ready for deployment."
echo
print_status "📋 To deploy your Pangolin stack:"
echo
echo "1. Set your configuration:"
echo "   export DOMAIN=your-domain.com"
echo "   export EMAIL=your-email@example.com"
echo "   export ADMIN_PASSWORD=your-secure-password"
echo
echo "2. Deploy the stack:"
echo "   docker-compose up -d"
echo
echo "Or in one command:"
echo "   DOMAIN=your-domain.com EMAIL=your-email@example.com ADMIN_PASSWORD=your-password docker-compose up -d"
echo
print_warning "⚠️  Important:"
echo "   • Make sure your domain points to this server's IP"
echo "   • Password must be at least 8 characters"
echo "   • Ports 80, 443, and 51820 must be available"
echo
print_status "📊 After deployment:"
echo "   • View logs: docker-compose logs -f"
echo "   • Access dashboard: https://your-domain.com"
echo "   • Admin login: admin@your-domain.com"
