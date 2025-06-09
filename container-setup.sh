#!/bin/sh

# Container Setup Script for Pangolin + CrowdSec + Traefik
# This script runs inside the Alpine container and creates the host folder structure

set -e

echo "🔧 Starting container setup process..."

# Generate a secure random secret key
generate_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Create directory structure on host
echo "📁 Creating directory structure..."
mkdir -p /host-setup/config/traefik
mkdir -p /host-setup/config/letsencrypt

# Set proper permissions for Let's Encrypt directory
chmod 600 /host-setup/config/letsencrypt

echo "✅ Directory structure created"

# Generate secret key
SECRET_KEY=$(generate_secret)
echo "🔐 Generated secure secret key"

# Create config.yml
echo "📝 Creating config.yml..."
cat > /host-setup/config/config.yml << EOF
app:
    dashboard_url: "https://${DOMAIN}"
    log_level: "info"
    save_logs: false

domains:
    domain1:
        base_domain: "${DOMAIN}"
        cert_resolver: "letsencrypt"

server:
    external_port: 3000
    internal_port: 3001
    next_port: 3002
    internal_hostname: "pangolin"
    session_cookie_name: "p_session_token"
    resource_access_token_param: "p_token"
    resource_access_token_headers:
        id: "P-Access-Token-Id"
        token: "P-Access-Token"
    resource_session_request_param: "p_session_request"
    secret: ${SECRET_KEY}
    cors:
        origins: ["https://${DOMAIN}"]
        methods: ["GET", "POST", "PUT", "DELETE", "PATCH"]
        headers: ["X-CSRF-Token", "Content-Type"]
        credentials: false

traefik:
    cert_resolver: "letsencrypt"
    http_entrypoint: "web"
    https_entrypoint: "websecure"

gerbil:
    start_port: 51820
    base_endpoint: "${DOMAIN}"
    use_subdomain: false
    block_size: 24
    site_block_size: 30
    subnet_group: 100.89.137.0/20

rate_limits:
    global:
        window_minutes: 1
        max_requests: 500

users:
    server_admin:
        email: "admin@${DOMAIN}"
        password: "${ADMIN_PASSWORD}"

flags:
    require_email_verification: false
    disable_signup_without_invite: true
    disable_user_create_org: false
    allow_raw_resources: true
    allow_base_domain_resources: true
EOF

echo "✅ config.yml created"

# Create traefik_config.yml
echo "📝 Creating traefik_config.yml..."
cat > /host-setup/config/traefik/traefik_config.yml << EOF
api:
  insecure: true
  dashboard: true

providers:
  http:
    endpoint: "http://pangolin:3001/api/v1/traefik-config"
    pollInterval: "5s"
  file:
    filename: "/etc/traefik/dynamic_config.yml"

experimental:
  plugins:
    badger:
      moduleName: "github.com/fosrl/badger"
      version: "v1.2.0"

log:
  level: "INFO"
  format: "common"

certificatesResolvers:
  letsencrypt:
    acme:
      httpChallenge:
        entryPoint: web
      email: ${EMAIL}
      storage: "/letsencrypt/acme.json"
      caServer: "https://acme-v02.api.letsencrypt.org/directory"

entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
    transport:
      respondingTimeouts:
        readTimeout: "30m"
    http:
      tls:
        certResolver: "letsencrypt"

serversTransport:
  insecureSkipVerify: true
EOF

echo "✅ traefik_config.yml created"

# Create dynamic_config.yml
echo "📝 Creating dynamic_config.yml..."
cat > /host-setup/config/traefik/dynamic_config.yml << EOF
http:
  middlewares:
    redirect-to-https:
      redirectScheme:
        scheme: https

  routers:
    # HTTP to HTTPS redirect router
    main-app-router-redirect:
      rule: "Host(\`${DOMAIN}\`)"
      service: next-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    # Next.js router (handles everything except API and WebSocket paths)
    next-router:
      rule: "Host(\`${DOMAIN}\`) && !PathPrefix(\`/api/v1\`)"
      service: next-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

    # API router (handles /api/v1 paths)
    api-router:
      rule: "Host(\`${DOMAIN}\`) && PathPrefix(\`/api/v1\`)"
      service: api-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

    # WebSocket router
    ws-router:
      rule: "Host(\`${DOMAIN}\`)"
      service: api-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

  services:
    next-service:
      loadBalancer:
        servers:
          - url: "http://pangolin:3002" # Next.js server

    api-service:
      loadBalancer:
        servers:
          - url: "http://pangolin:3000" # API/WebSocket server
EOF

echo "✅ dynamic_config.yml created"

# Create a summary file for the user
cat > /host-setup/DEPLOYMENT_INFO.txt << EOF
🚀 Pangolin + CrowdSec + Traefik Stack Deployment

Deployment completed at: $(date)

📊 Configuration:
- Domain: ${DOMAIN}
- Email: ${EMAIL}
- Admin User: admin@${DOMAIN}

🌐 Access Information:
- Dashboard URL: https://${DOMAIN}
- Admin Login: admin@${DOMAIN}
- Admin Password: [Set during deployment]

📁 Directory Structure Created:
./config/
├── config.yml
├── letsencrypt/          # Let's Encrypt certificates
└── traefik/
    ├── traefik_config.yml
    └── dynamic_config.yml

🔧 Management Commands:
- View logs: docker compose logs -f
- Restart: docker compose restart
- Stop: docker compose down
- Update: docker compose pull && docker compose up -d

⚠️  Important Notes:
- Ensure ${DOMAIN} DNS points to this server's IP
- Let's Encrypt certificates may take a few minutes to issue
- All traffic is automatically redirected to HTTPS

🔐 Security:
- Secure random secret generated: ${SECRET_KEY}
- HTTPS enforced via Traefik
- Admin access configured

Generated by Pangolin Container Setup
EOF

echo "✅ All configuration files created successfully!"
echo "📋 Deployment info saved to DEPLOYMENT_INFO.txt"
