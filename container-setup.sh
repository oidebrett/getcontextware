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
mkdir -p /host-setup/config/traefik/rules
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
    dashboard_url: "https://${ADMIN_SUBDOMAIN}.${DOMAIN}"
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
    directory: "/rules"
    watch: true

experimental:
  plugins:
    badger:
      moduleName: "github.com/fosrl/badger"
      version: "v1.2.0"

log:
    level: "INFO"
    format: "json"

accessLog:
    filePath: "/var/log/traefik/access.log"
    format: json

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
cat > /host-setup/config/traefik/rules/dynamic_config.yml << EOF
http:
  middlewares:
    redirect-to-https:
      redirectScheme:
        scheme: https

  routers:
    # HTTP to HTTPS redirect router
    main-app-router-redirect:
      rule: "Host(\`${ADMIN_SUBDOMAIN}.${DOMAIN}\`)"
      service: next-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    # Next.js router (handles everything except API and WebSocket paths)
    next-router:
      rule: "Host(\`${ADMIN_SUBDOMAIN}.${DOMAIN}\`) && !PathPrefix(\`/api/v1\`)"
      service: next-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

    # API router (handles /api/v1 paths)
    api-router:
      rule: "Host(\`${ADMIN_SUBDOMAIN}.${DOMAIN}\`) && PathPrefix(\`/api/v1\`)"
      service: api-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

    # WebSocket router
    ws-router:
      rule: "Host(\`${ADMIN_SUBDOMAIN}.${DOMAIN}\`)"
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

# Set this to true to enable CrowdSec config setup
ENABLE_CROWDSEC=true

if [ "$ENABLE_CROWDSEC" = true ]; then
    echo "🛡️  Setting up CrowdSec directories and config files..."

    mkdir -p /host-setup/config/crowdsec/notifications
    mkdir -p /host-setup/config/crowdsec/hub
    mkdir -p /host-setup/config/crowdsec/patterns
    mkdir -p /host-setup/config/crowdsec_logs
    mkdir -p /host-setup/config/traefik/conf
    mkdir -p /host-setup/config/traefik/logs

    cat > /host-setup/config/crowdsec/acquis.yaml << EOF
filenames:
 - /var/log/auth.log
 - /var/log/syslog
labels:
  type: syslog
---
poll_without_inotify: false
filenames:
  - /var/log/traefik/*.log
labels:
  type: traefik
---
listen_addr: 0.0.0.0:7422 
appsec_config: crowdsecurity/appsec-default
name: myAppSecComponent
source: appsec
labels:
  type: appsec
EOF

    cat > /host-setup/config/crowdsec/config.yaml << EOF
common:
  daemonize: false
  log_media: stdout
  log_level: info
  log_dir: /var/log/
config_paths:
  config_dir: /etc/crowdsec/
  data_dir: /var/lib/crowdsec/data/
  simulation_path: /etc/crowdsec/simulation.yaml
  hub_dir: /etc/crowdsec/hub/
  index_path: /etc/crowdsec/hub/.index.json
  notification_dir: /etc/crowdsec/notifications/
  plugin_dir: /usr/local/lib/crowdsec/plugins/
crowdsec_service:
  acquisition_path: /etc/crowdsec/acquis.yaml
  acquisition_dir: /etc/crowdsec/acquis.d
  parser_routines: 1
plugin_config:
  user: nobody
  group: nobody
cscli:
  output: human
db_config:
  log_level: info
  type: sqlite
  db_path: /var/lib/crowdsec/data/crowdsec.db
  flush:
    max_items: 5000
    max_age: 7d
  use_wal: false
api:
  client:
    insecure_skip_verify: false
    credentials_path: /etc/crowdsec/local_api_credentials.yaml
  server:
    log_level: info
    listen_uri: 0.0.0.0:8080
    profiles_path: /etc/crowdsec/profiles.yaml
    trusted_ips:
      - 127.0.0.1
      - ::1
    online_client:
      credentials_path: /etc/crowdsec/online_api_credentials.yaml
    enable: true
prometheus:
  enabled: true
  level: full
  listen_addr: 0.0.0.0
  listen_port: 6060
EOF

    cat > /host-setup/config/crowdsec/profiles.yaml << EOF
name: captcha_remediation
filters:
  - Alert.Remediation == true && Alert.GetScope() == "Ip" && Alert.GetScenario() contains "http"
decisions:
  - type: captcha
    duration: 4h
on_success: break

---
name: default_ip_remediation
filters:
 - Alert.Remediation == true && Alert.GetScope() == "Ip"
decisions:
 - type: ban
   duration: 4h
on_success: break

---
name: default_range_remediation
filters:
 - Alert.Remediation == true && Alert.GetScope() == "Range"
decisions:
 - type: ban
   duration: 4h
on_success: break
EOF

    cat > /host-setup/config/crowdsec/user.yaml << EOF
common:
  daemonize: false
  log_media: stdout
  log_level: info
  log_dir: /var/log/
config_paths:
  config_dir: /etc/crowdsec/
  data_dir: /var/lib/crowdsec/data
crowdsec_service:
  parser_routines: 1
cscli:
  output: human
db_config:
  type: sqlite
  db_path: /var/lib/crowdsec/data/crowdsec.db
  user: crowdsec
  password: crowdsec
  db_name: crowdsec
  host: "127.0.0.1"
  port: 3306
api:
  client:
    insecure_skip_verify: false
    credentials_path: /etc/crowdsec/local_api_credentials.yaml
  server:
    listen_uri: 127.0.0.1:8080
    profiles_path: /etc/crowdsec/profiles.yaml
    online_client:
      credentials_path: /etc/crowdsec/online_api_credentials.yaml
prometheus:
  enabled: true
  level: full
EOF

    cat > /host-setup/config/crowdsec/simulation.yaml << EOF
simulation: false
# exclusions:
#  - crowdsecurity/ssh-bf
EOF

    cat > /host-setup/config/crowdsec/local_api_credentials.yaml << EOF
url: http://0.0.0.0:8080
login: localhost
password: UNIQUE_PASSWORD_WILL_BE_INSERTED_HERE
EOF

    touch /host-setup/config/crowdsec/online_api_credentials.yaml

    echo "✅ CrowdSec configuration files created"
fi

# Create a summary file for the user
cat > /host-setup/DEPLOYMENT_INFO.txt << EOF
🚀 Pangolin + CrowdSec + Traefik Stack Deployment

Deployment completed at: $(date)

📊 Configuration:
- Domain: ${DOMAIN}
- Admin Subdomain: ${ADMIN_SUBDOMAIN}
- Email: ${EMAIL}
- Admin User: admin@${DOMAIN}

🌐 Access Information:
- Dashboard URL: https://${ADMIN_SUBDOMAIN}.${DOMAIN}
- Admin Login: admin@${DOMAIN}
- Admin Password: [Set during deployment]

📁 Directory Structure Created:
./config/
├── config.yml
├── letsencrypt/          # Let's Encrypt certificates
└── traefik/
    ├── rules/
    │   └── dynamic_config.yml
    ├── traefik_config.yml
    ├── conf/             # CAPTCHA template support
    └── logs/             # Traefik logs

EOF

if [ "$ENABLE_CROWDSEC" = true ]; then
cat >> /host-setup/DEPLOYMENT_INFO.txt << EOF
└── crowdsec/
    ├── acquis.yaml
    ├── config.yaml
    ├── profiles.yaml
    ├── user.yaml
    ├── simulation.yaml
    ├── local_api_credentials.yaml
    └── online_api_credentials.yaml
📁 Additional:
./crowdsec_logs/          # Log volume for CrowdSec

🛡️ CrowdSec Notes:
- AppSec and log parsing is configured
- Prometheus and API are enabled
- CAPTCHA and remediation profiles are active
EOF
fi

cat >> /host-setup/DEPLOYMENT_INFO.txt << EOF

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
