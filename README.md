# Contextware - Pangolin + CrowdSec + Traefik Stack

A sleek, containerized deployment of ContextWare - Pangolin with CrowdSec security and Traefik reverse proxy. Everything runs in Docker containers and automatically creates the required host folder structure.

## Features

- 🚀 **One-command deployment** - Deploy everything with a single Docker Compose command
- 🐳 **Fully containerized** - Setup process runs in containers, no local scripts needed
- 🔒 **Automatic HTTPS** - Let's Encrypt certificates managed by Traefik
- 🛡️ **Security** - CrowdSec integration for threat protection
- 📁 **Auto-configuration** - Container creates all required files and folder structure on host
- 🔐 **Secure secrets** - Auto-generates secure random keys
- 📥 **GitHub integration** - Downloads setup scripts directly from GitHub

## Quick Start

### Prerequisites

- Linux server with Docker and Docker Compose installed
- Domain name pointing to your server's IP address
- Ports 80, 443, and 51820 available

### One-Command Deployment

```bash
# Download the docker-compose.yml file
curl -sSL https://raw.githubusercontent.com/oidebrett/getcontextware/main/docker-compose.yml -o docker-compose.yml

# Deploy with your configuration
DOMAIN=example.com EMAIL=admin@example.com ADMIN_PASSWORD=mypassword docker compose up -d
```

### What happens during deployment:

1. **Setup Container** - Alpine container starts and validates environment variables
2. **Download** - Container fetches setup scripts from GitHub
3. **Folder Creation** - Container creates config folder structure on host
4. **Configuration** - Container generates all config files with your settings
5. **Stack Deployment** - Main services (Pangolin, Gerbil, Traefik) start automatically

## Alternative: Manual Download

If you prefer to review files before running:

```bash
# Clone or download the repository
git clone https://github.com/oidebrett/getcontextware.git
cd getcontextware

# Deploy with your configuration
DOMAIN=example.com EMAIL=admin@example.com ADMIN_PASSWORD=mypassword docker compose up -d
```

## Environment Variables

The deployment requires three environment variables:

- **DOMAIN** - Your domain name (e.g., `example.com`)
- **EMAIL** - Email address for Let's Encrypt certificates
- **ADMIN_PASSWORD** - Admin password for Pangolin (minimum 8 characters)

### Optional Variables

- **GITHUB_USER** - GitHub username (default: `oidebrett`)
- **GITHUB_REPO** - Repository name (default: `getcontextware`)
- **GITHUB_BRANCH** - Branch name (default: `main`)

## Stack Components

- **Setup Container** (alpine:latest) - Creates folder structure and config files
- **Pangolin** (fosrl/pangolin:1.5.0) - Main application
- **Gerbil** (fosrl/gerbil:1.0.0) - WireGuard VPN management
- **Traefik** (traefik:v3.4.0) - Reverse proxy with automatic HTTPS

## Directory Structure

After deployment, you'll have:

```
./
├── docker-compose.yml
├── DEPLOYMENT_INFO.txt      # Deployment summary and info
└── config/
    ├── config.yml
    ├── letsencrypt/          # Let's Encrypt certificates
    └── traefik/
        ├── traefik_config.yml
        └── dynamic_config.yml
```

## Management Commands

```bash
# View logs
docker compose logs -f

# Restart services
docker compose restart

# Stop services
docker compose down

# Start services
docker compose up -d

# Update images
docker compose pull
docker compose up -d
```

## Configuration

All configuration is automatically generated during setup. Key files:

- `config/config.yml` - Main Pangolin configuration
- `config/traefik/traefik_config.yml` - Traefik main config
- `config/traefik/dynamic_config.yml` - Traefik routing rules

## Accessing Your Installation

After successful deployment:

- **Dashboard**: `https://yourdomain.com`
- **Admin Login**: `admin@yourdomain.com`
- **Password**: The password you set during installation

## Troubleshooting

### Common Issues

1. **Domain not resolving**
   - Ensure your domain's DNS A record points to your server's IP
   - Wait for DNS propagation (can take up to 24 hours)

2. **Certificate issues**
   - Let's Encrypt certificates can take a few minutes to issue
   - Check logs: `docker compose logs traefik`

3. **Permission errors**
   - Ensure your user is in the docker group: `sudo usermod -aG docker $USER`
   - Log out and back in after adding to docker group

### Viewing Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f pangolin
docker compose logs -f traefik
docker compose logs -f gerbil
```

## Security Notes

- The setup generates secure random secrets automatically
- Admin password is set during installation
- All traffic is automatically redirected to HTTPS
- CrowdSec provides additional security monitoring

## Support

For issues and questions:
- Check the logs first: `docker compose logs -f`
- Ensure your domain DNS is properly configured
- Verify all ports (80, 443, 51820) are accessible

## License

This deployment stack is provided as-is. Please refer to individual component licenses:
- Pangolin: Check fosrl/pangolin repository
- Gerbil: Check fosrl/gerbil repository  
- Traefik: Apache 2.0 License
