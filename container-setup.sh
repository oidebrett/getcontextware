#!/bin/sh

# Container Setup Script for Pangolin + CrowdSec + Traefik
# This script runs inside the Alpine container and creates the host folder structure

set -e

echo "🔧 Starting container setup process..."

# Generate a secure random secret key
generate_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Function to create directories for CrowdSec
create_crowdsec_directories() {
    echo "📁 Creating CrowdSec directories..."
    mkdir -p /host-setup/config/crowdsec/db
    mkdir -p /host-setup/config/crowdsec/acquis.d
    mkdir -p /host-setup/config/traefik/logs
    mkdir -p /host-setup/config/traefik/conf
    mkdir -p /host-setup/config/crowdsec_logs
}

# Function to create CrowdSec config files
create_crowdsec_config() {
    echo "📝 Creating CrowdSec configuration files..."
    
    # Create acquis.yaml
    cat > /host-setup/config/crowdsec/acquis.yaml << 'EOF'
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

    # Create profiles.yaml
    cat > /host-setup/config/crowdsec/profiles.yaml << 'EOF'
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
    
    wget -O /host-setup/config/traefik/conf/captcha.html https://gist.githubusercontent.com/hhftechnology/48569d9f899bb6b889f9de2407efd0d2/raw/captcha.html 
    
}

# Function to update dynamic config with CrowdSec middleware
update_dynamic_config_with_crowdsec() {
    echo "📝 Updating dynamic config with CrowdSec middleware..."
    
    cat > /host-setup/config/traefik/rules/dynamic_config.yml << EOF
http:
  middlewares:
    redirect-to-https:
      redirectScheme:
        scheme: https
    security-headers:
      headers:
        customResponseHeaders:
          Server: ""
          X-Powered-By: ""
          X-Forwarded-Proto: "https"
        contentTypeNosniff: true
        customFrameOptionsValue: "SAMEORIGIN"
        referrerPolicy: "strict-origin-when-cross-origin"
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsSeconds: 63072000
        stsPreload: true
    statiq:
      plugin:
        statiq:
          enableDirectoryListing: false
          indexFiles:
            - index.html
            - index.htm
          root: /var/www/html
          spaIndex: index.html
          spaMode: false

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
      middlewares:
        - security-headers
      tls:
        certResolver: letsencrypt

    # API router (handles /api/v1 paths)
    api-router:
      rule: "Host(\`${ADMIN_SUBDOMAIN}.${DOMAIN}\`) && PathPrefix(\`/api/v1\`)"
      service: api-service
      entryPoints:
        - websecure
      middlewares:
        - security-headers
      tls:
        certResolver: letsencrypt

    # WebSocket router
    ws-router:
      rule: "Host(\`${ADMIN_SUBDOMAIN}.${DOMAIN}\`)"
      service: api-service
      entryPoints:
        - websecure
      middlewares:
        - security-headers
      tls:
        certResolver: letsencrypt

    statiq-router-redirect:
      rule: "Host(\`www.${DOMAIN}\`)"
      service: statiq-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    statiq-router:
      entryPoints:
        - websecure
      middlewares:
        - statiq
      service: statiq-service
      priority: 100
      rule: "Host(\`www.${DOMAIN}\`)"

    middleware-manager-router-redirect:
      rule: "Host(\`middleware-manager.${DOMAIN}\`)"
      service: middleware-manager-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    middleware-manager-router:
      entryPoints:
        - websecure
      middlewares:
        - security-headers
      priority: 100
      rule: "Host(\`middleware-manager.${DOMAIN}\`)"
      service: middleware-manager-service
      tls:
        certResolver: "letsencrypt"

    komodo-router-redirect:
      rule: "Host(\`komodo.${DOMAIN}\`)"
      service: komodo-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    komodo-router:
      entryPoints:
        - websecure
      middlewares:
        - security-headers
      priority: 100
      rule: "Host(\`komodo.${DOMAIN}\`)"
      service: komodo-service
      tls:
        certResolver: "letsencrypt"

    traefik-dashboard-router-redirect:
      rule: "Host(\`traefik.${DOMAIN}\`)"
      service: traefik-dashboard-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    traefik-dashboard-router:
      entryPoints:
        - websecure
      middlewares:
        - security-headers
      priority: 100
      rule: "Host(\`traefik.${DOMAIN}\`)"
      service: traefik-dashboard-service
      tls:
        certResolver: "letsencrypt"

    # Add these lines for mcpauth
    # mcpauth http redirect router
    mcpauth-router-redirect:
      rule: "Host(\`oauth.${DOMAIN}\`)"
      service: mcpauth-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    # mcpauth router
    mcpauth:
      rule: "Host(\`oauth.${DOMAIN}\`)"
      service: mcpauth-service
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

    statiq-service:
      loadBalancer:
        servers:
          - url: "noop@internal"

    middleware-manager-service:
      loadBalancer:
        servers:
          - url: "http://middleware-manager:3456" 

    traefik-dashboard-service:
      loadBalancer:
        servers:
          - url: "http://localhost:8080" 

    komodo-service:
      loadBalancer:
        servers:
          - url: "http://komodo-core-1:9120" 

    mcpauth-service:
      loadBalancer:
        servers:
          - url: "http://mcpauth:11000"  # mcpauth auth server

    oauth-service:
      loadBalancer:
        servers:
          - url: "https://oauth.${DOMAIN}"

EOF
}

# Create directory structure on host
echo "📁 Creating directory structure..."
mkdir -p /host-setup/config/traefik
mkdir -p /host-setup/config/traefik/rules
mkdir -p /host-setup/config/letsencrypt
mkdir -p /host-setup/public_html

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
        email: "${ADMIN_USERNAME}"
        password: "${ADMIN_PASSWORD}"

flags:
    require_email_verification: false
    disable_signup_without_invite: true
    disable_user_create_org: false
    allow_raw_resources: true
    allow_base_domain_resources: true

postgres:
    connection_string: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:5432/postgres

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
    statiq:
      moduleName: github.com/hhftechnology/statiq
      version: v1.0.1

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

# Check if static page should be enabled
if [ -n "$STATIC_PAGE" ]; then
    echo "🛡️ Statuc page detected - setting up ..."
    
    # Create basic index.html
    cat > /host-setup/public_html/index.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
    <title>ContextWareAI Dashboard</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-900 text-white font-sans h-screen overflow-hidden">
    <div class="flex h-full">
        <!-- Sidebar -->
        <div id="sidebar" class="w-20 hover:w-80 bg-gray-800 shadow-xl flex flex-col transition-all duration-300 ease-in-out group z-10">
            <div class="p-3 border-b border-gray-700 overflow-hidden flex justify-center group-hover:justify-start">
                <div class="flex items-center">
                    <div class="w-8 h-8 bg-cyan-400 rounded-lg flex items-center justify-center flex-shrink-0">
                        <svg class="w-5 h-5 text-gray-900" fill="currentColor" viewBox="0 0 20 20">
                            <path d="M3 4a1 1 0 011-1h12a1 1 0 011 1v2a1 1 0 01-1 1H4a1 1 0 01-1-1V4zM3 10a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H4a1 1 0 01-1-1v-6zM14 9a1 1 0 00-1 1v6a1 1 0 001 1h2a1 1 0 001-1v-6a1 1 0 00-1-1h-2z"/>
                        </svg>
                    </div>
                    <div class="ml-3 opacity-0 group-hover:opacity-100 transition-opacity duration-300 whitespace-nowrap">
                        <h1 class="text-2xl font-bold text-cyan-400">ContextWareAI</h1>
                        <p class="text-sm text-gray-400 mt-1">Application Dashboard</p>
                    </div>
                </div>
            </div>
            
            <nav class="flex-1 p-2 space-y-2 overflow-hidden">
                <!-- Home -->
                <div class="sidebar-item bg-gray-700 rounded-lg p-3 cursor-pointer hover:bg-gray-600 transition-colors duration-200 border-l-4 border-cyan-400 flex items-center justify-center group-hover:justify-start min-h-[3rem]" onclick="showWelcome()">
                    <div class="w-8 h-8 flex items-center justify-center flex-shrink-0">
                        <svg class="w-6 h-6 text-cyan-400" fill="currentColor" viewBox="0 0 20 20">
                            <path d="M10.707 2.293a1 1 0 00-1.414 0l-7 7a1 1 0 001.414 1.414L4 10.414V17a1 1 0 001 1h2a1 1 0 001-1v-2a1 1 0 011-1h2a1 1 0 011 1v2a1 1 0 001 1h2a1 1 0 001-1v-6.586l.293.293a1 1 0 001.414-1.414l-7-7z"/>
                        </svg>
                    </div>
                    <div class="ml-3 opacity-0 group-hover:opacity-100 transition-opacity duration-300 whitespace-nowrap">
                        <div class="text-lg font-semibold text-white">Home</div>
                        <div class="text-sm text-gray-300">Welcome page</div>
                    </div>
                </div>

                <!-- Pangolin -->
                <div class="sidebar-item bg-gray-700 rounded-lg p-3 cursor-pointer hover:bg-gray-600 transition-colors duration-200 flex items-center justify-center group-hover:justify-start min-h-[3rem]" onclick="loadApp('https://${ADMIN_SUBDOMAIN}.${DOMAIN}', 'Pangolin', this)">
                    <div class="w-8 h-8 flex items-center justify-center flex-shrink-0">
                        <img src="https://cdn.jsdelivr.net/gh/selfhst/icons/webp/pangolin.webp" alt="Pangolin Icon" class="w-6 h-6 object-contain" onerror="this.style.display='none'; this.nextElementSibling.style.display='block';">
                        <div class="w-6 h-6 bg-cyan-400 rounded flex items-center justify-center text-xs font-bold text-gray-900" style="display:none;">P</div>
                    </div>
                    <div class="ml-3 opacity-0 group-hover:opacity-100 transition-opacity duration-300 whitespace-nowrap">
                        <div class="text-lg font-semibold text-cyan-400">Pangolin</div>
                        <div class="text-sm text-gray-300">Reverse proxy management</div>
                    </div>
                </div>

                <!-- Komodo -->
                <div class="sidebar-item bg-gray-700 rounded-lg p-3 cursor-pointer hover:bg-gray-600 transition-colors duration-200 flex items-center justify-center group-hover:justify-start min-h-[3rem]" onclick="loadApp('https://komodo.${DOMAIN}', 'Komodo', this)">
                    <div class="w-8 h-8 flex items-center justify-center flex-shrink-0">
                        <img src="https://cdn.jsdelivr.net/gh/selfhst/icons/webp/komodo.webp" alt="Komodo Icon" class="w-6 h-6 object-contain" onerror="this.style.display='none'; this.nextElementSibling.style.display='block';">
                        <div class="w-6 h-6 bg-cyan-400 rounded flex items-center justify-center text-xs font-bold text-gray-900" style="display:none;">K</div>
                    </div>
                    <div class="ml-3 opacity-0 group-hover:opacity-100 transition-opacity duration-300 whitespace-nowrap">
                        <div class="text-lg font-semibold text-cyan-400">Komodo</div>
                        <div class="text-sm text-gray-300">Build and deploy tool</div>
                    </div>
                </div>

                <!-- Middleware Manager -->
                <div class="sidebar-item bg-gray-700 rounded-lg p-3 cursor-pointer hover:bg-gray-600 transition-colors duration-200 flex items-center justify-center group-hover:justify-start min-h-[3rem]" onclick="loadApp('https://middleware-manager.${DOMAIN}', 'Middleware Manager', this)">
                    <div class="w-8 h-8 flex items-center justify-center flex-shrink-0">
                        <img src="https://cdn.jsdelivr.net/gh/selfhst/icons/webp/middleware-manager.webp" alt="Middleware Icon" class="w-6 h-6 object-contain" onerror="this.style.display='none'; this.nextElementSibling.style.display='block';">
                        <div class="w-6 h-6 bg-cyan-400 rounded flex items-center justify-center text-xs font-bold text-gray-900" style="display:none;">M</div>
                    </div>
                    <div class="ml-3 opacity-0 group-hover:opacity-100 transition-opacity duration-300 whitespace-nowrap">
                        <div class="text-lg font-semibold text-cyan-400">Middleware Manager</div>
                        <div class="text-sm text-gray-300">Traefik middleware manager</div>
                    </div>
                </div>

                <!-- Traefik -->
                <div class="sidebar-item bg-gray-700 rounded-lg p-3 cursor-pointer hover:bg-gray-600 transition-colors duration-200 flex items-center justify-center group-hover:justify-start min-h-[3rem]" onclick="loadApp('https://traefik.${DOMAIN}/dashboard/', 'Traefik Dashboard', this)">
                    <div class="w-8 h-8 flex items-center justify-center flex-shrink-0">
                        <img src="https://cdn.jsdelivr.net/gh/selfhst/icons/webp/traefik.webp" alt="Traefik Icon" class="w-6 h-6 object-contain" onerror="this.style.display='none'; this.nextElementSibling.style.display='block';">
                        <div class="w-6 h-6 bg-cyan-400 rounded flex items-center justify-center text-xs font-bold text-gray-900" style="display:none;">T</div>
                    </div>
                    <div class="ml-3 opacity-0 group-hover:opacity-100 transition-opacity duration-300 whitespace-nowrap">
                        <div class="text-lg font-semibold text-cyan-400">Traefik Dashboard</div>
                        <div class="text-sm text-gray-300">Application proxy</div>
                    </div>
                </div>
            </nav>
        </div>

        <!-- Main Content Area -->
        <div class="flex-1 flex flex-col">
            <!-- Header -->
            <div class="bg-gray-800 p-4 border-b border-gray-700 shadow-lg">
                <div class="flex items-center justify-between">
                    <h2 id="current-app-title" class="text-xl font-semibold text-cyan-400">Welcome</h2>
                    <div class="flex items-center space-x-4">
                        <div id="loading-indicator" class="hidden">
                            <div class="animate-spin rounded-full h-5 w-5 border-b-2 border-cyan-400"></div>
                        </div>
                        <button id="refresh-btn" class="hidden bg-gray-700 hover:bg-gray-600 px-3 py-1 rounded-lg text-sm transition-colors duration-200" onclick="refreshIframe()">
                            <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                                <path fill-rule="evenodd" d="M4 2a1 1 0 011 1v2.101a7.002 7.002 0 0111.601 2.566 1 1 0 11-1.885.666A5.002 5.002 0 005.999 7H9a1 1 0 010 2H4a1 1 0 01-1-1V3a1 1 0 011-1zm.008 9.057a1 1 0 011.276.61A5.002 5.002 0 0014.001 13H11a1 1 0 110-2h5a1 1 0 011 1v5a1 1 0 11-2 0v-2.101a7.002 7.002 0 01-11.601-2.566 1 1 0 01.61-1.276z" clip-rule="evenodd"/>
                            </svg>
                        </button>
                    </div>
                </div>
            </div>

            <!-- Content Area -->
            <div class="flex-1 relative">
                <!-- Welcome Screen -->
                <div id="welcome-screen" class="flex items-center justify-center h-full bg-gray-900">
                    <div class="text-center max-w-2xl px-8">
                        <h1 class="text-6xl font-bold mb-6 text-cyan-400 animate-pulse">Welcome to ContextWareAI</h1>
                        <p class="text-xl text-gray-400 mb-8">Click on the menu on the left to access your applications</p>
                        <div class="grid grid-cols-2 gap-4 text-sm text-gray-500">
                            <div class="bg-gray-800 p-4 rounded-lg">
                                <div class="font-semibold text-cyan-400 mb-2">Management Tools</div>
                                <div>Pangolin • Komodo</div>
                            </div>
                            <div class="bg-gray-800 p-4 rounded-lg">
                                <div class="font-semibold text-cyan-400 mb-2">Infrastructure</div>
                                <div>Middleware • Traefik</div>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- Iframe Container -->
                <iframe id="app-iframe" class="w-full h-full border-0 hidden" src="about:blank"></iframe>
            </div>
        </div>
    </div>

    <script>
        let currentActiveItem = document.querySelector('.sidebar-item');
        
        function showWelcome() {
            // Hide iframe and show welcome screen
            document.getElementById('app-iframe').classList.add('hidden');
            const welcomeScreen = document.getElementById('welcome-screen');
            welcomeScreen.innerHTML = \`
                <div class="text-center max-w-2xl px-8">
                    <h1 class="text-6xl font-bold mb-6 text-cyan-400 animate-pulse">Welcome to ContextWareAI</h1>
                    <p class="text-xl text-gray-400 mb-8">Click on the menu on the left to access your applications</p>
                    <div class="grid grid-cols-2 gap-4 text-sm text-gray-500">
                        <div class="bg-gray-800 p-4 rounded-lg">
                            <div class="font-semibold text-cyan-400 mb-2">Management Tools</div>
                            <div>Pangolin • Komodo</div>
                        </div>
                        <div class="bg-gray-800 p-4 rounded-lg">
                            <div class="font-semibold text-cyan-400 mb-2">Infrastructure</div>
                            <div>Middleware • Traefik</div>
                        </div>
                    </div>
                </div>
            \`;
            welcomeScreen.classList.remove('hidden');
            document.getElementById('current-app-title').textContent = 'Welcome';
            document.getElementById('refresh-btn').classList.add('hidden');
            
            // Update active item
            updateActiveItem(document.querySelector('.sidebar-item'));
        }
        
        function loadApp(url, title, element) {
            const iframe = document.getElementById('app-iframe');
            const welcomeScreen = document.getElementById('welcome-screen');
            const titleElement = document.getElementById('current-app-title');
            const loadingIndicator = document.getElementById('loading-indicator');
            const refreshBtn = document.getElementById('refresh-btn');
            
            // Show loading indicator
            loadingIndicator.classList.remove('hidden');
            titleElement.textContent = \`Loading ${title}...\`;
            
            // Hide welcome screen and show iframe
            welcomeScreen.classList.add('hidden');
            iframe.classList.remove('hidden');
            
            // Load the application
            iframe.src = url;
            
            // Update active sidebar item
            updateActiveItem(element);
            
            // Set up iframe blocking detection
            let iframeBlocked = false;
            let loadTimeout;
            
            // Timeout to detect if iframe is blocked (most blocking happens immediately)
            loadTimeout = setTimeout(() => {
                if (!iframeBlocked) {
                    // Likely blocked by X-Frame-Options or CSP
                    handleIframeBlocked(url, title);
                }
            }, 3000);
            
            // Handle iframe load success
            iframe.onload = function() {
                clearTimeout(loadTimeout);
                
                try {
                    // Try to access iframe content to detect if it's blocked
                    const iframeDoc = iframe.contentDocument || iframe.contentWindow.document;
                    
                    // If we can access it and it's not empty, it loaded successfully
                    if (iframeDoc && iframeDoc.body && iframeDoc.body.innerHTML.trim() !== '') {
                        loadingIndicator.classList.add('hidden');
                        titleElement.textContent = title;
                        refreshBtn.classList.remove('hidden');
                    } else {
                        // Empty or blocked content
                        handleIframeBlocked(url, title);
                    }
                } catch (e) {
                    // Cross-origin access denied - try to detect if it's actually blocked
                    // If we get here, the iframe loaded but we can't access content
                    // This could be normal cross-origin or actual blocking
                    setTimeout(() => {
                        // Check if iframe is displaying content by checking its location
                        try {
                            if (iframe.contentWindow.location.href === 'about:blank') {
                                handleIframeBlocked(url, title);
                            } else {
                                // Likely loaded successfully but cross-origin
                                loadingIndicator.classList.add('hidden');
                                titleElement.textContent = title;
                                refreshBtn.classList.remove('hidden');
                            }
                        } catch (e2) {
                            // Assume it loaded successfully if we can't check
                            loadingIndicator.classList.add('hidden');
                            titleElement.textContent = title;
                            refreshBtn.classList.remove('hidden');
                        }
                    }, 1000);
                }
            };
            
            // Handle iframe load errors
            iframe.onerror = function() {
                clearTimeout(loadTimeout);
                handleIframeBlocked(url, title);
            };
        }
        
        function handleIframeBlocked(url, title) {
            const iframe = document.getElementById('app-iframe');
            const welcomeScreen = document.getElementById('welcome-screen');
            const titleElement = document.getElementById('current-app-title');
            const loadingIndicator = document.getElementById('loading-indicator');
            const refreshBtn = document.getElementById('refresh-btn');
            
            // Hide loading indicator
            loadingIndicator.classList.add('hidden');
            refreshBtn.classList.add('hidden');
            
            // Show blocking message
            iframe.classList.add('hidden');
            welcomeScreen.innerHTML = \`
                <div class="text-center max-w-2xl px-8">
                    <div class="bg-yellow-900 border border-yellow-600 rounded-lg p-6 mb-6">
                        <div class="flex items-center justify-center mb-4">
                            <svg class="w-12 h-12 text-yellow-400" fill="currentColor" viewBox="0 0 20 20">
                                <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
                            </svg>
                        </div>
                        <h2 class="text-2xl font-bold text-yellow-400 mb-2">${title} Cannot Be Embedded</h2>
                        <p class="text-yellow-200 mb-4">This application blocks iframe embedding for security reasons.</p>
                        <div class="space-y-3">
                            <button onclick="window.open('${url}', '_blank', 'width=1200,height=800,scrollbars=yes,resizable=yes')" 
                                    class="bg-cyan-600 hover:bg-cyan-700 text-white px-6 py-3 rounded-lg font-semibold transition-colors duration-200 mr-3">
                                Open in New Window
                            </button>
                            <button onclick="window.open('${url}', '_blank')" 
                                    class="bg-gray-600 hover:bg-gray-700 text-white px-6 py-3 rounded-lg font-semibold transition-colors duration-200">
                                Open in New Tab
                            </button>
                        </div>
                        <p class="text-yellow-300 text-sm mt-4">The application will open in a separate window/tab where it can function normally.</p>
                    </div>
                    <button onclick="showWelcome()" class="text-cyan-400 hover:text-cyan-300 underline">
                        ← Back to Welcome
                    </button>
                </div>
            \`;
            welcomeScreen.classList.remove('hidden');
            titleElement.textContent = `${title} - Blocked`;
        }
        
        function updateActiveItem(element) {
            // Remove active state from all items
            document.querySelectorAll('.sidebar-item').forEach(item => {
                item.classList.remove('border-l-4', 'border-cyan-400', 'bg-gray-600');
                item.classList.add('bg-gray-700');
            });
            
            // Add active state to clicked item
            element.classList.remove('bg-gray-700');
            element.classList.add('border-l-4', 'border-cyan-400', 'bg-gray-600');
            currentActiveItem = element;
        }
        
        function refreshIframe() {
            const iframe = document.getElementById('app-iframe');
            const loadingIndicator = document.getElementById('loading-indicator');
            
            if (iframe.src !== 'about:blank') {
                loadingIndicator.classList.remove('hidden');
                iframe.src = iframe.src; // Reload the iframe
            }
        }
        
        // Initialize with welcome screen active
        showWelcome();
    </script>
</body>
</html>

EOF
fi


# Check if CrowdSec should be enabled
if [ -n "$CROWDSEC_ENROLLMENT_KEY" ]; then
    echo "🛡️ CrowdSec enrollment key detected - setting up CrowdSec..."
    ENABLE_CROWDSEC=true
    
    # Create CrowdSec directories
    create_crowdsec_directories
    
    # Create CrowdSec config files
    create_crowdsec_config
    
    # Update dynamic config with CrowdSec middleware
    update_dynamic_config_with_crowdsec
    
    echo "✅ CrowdSec configuration files created"
else
    echo "ℹ️ No CrowdSec enrollment key - creating basic dynamic config..."
    ENABLE_CROWDSEC=false
    
    # Create basic dynamic_config.yml without CrowdSec
    cat > /host-setup/config/traefik/rules/dynamic_config.yml << EOF
http:
  middlewares:
    redirect-to-https:
      redirectScheme:
        scheme: https
    statiq:
      plugin:
        statiq:
          enableDirectoryListing: false
          indexFiles:
            - index.html
            - index.htm
          root: /var/www/html
          spaIndex: index.html
          spaMode: false

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

    statiq-router-redirect:
      rule: "Host(\`www.${DOMAIN}\`)"
      service: statiq-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    statiq-router:
        entryPoints:
            - websecure
        middlewares:
            - statiq
        priority: 100
        rule: "Host(\`www.${DOMAIN}\`)"
        service: statiq-service
        tls:
            certResolver: "letsencrypt"

    middleware-manager-router-redirect:
      rule: "Host(\`middleware-manager.${DOMAIN}\`)"
      service: middleware-manager-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    middleware-manager-router:
        entryPoints:
            - websecure
        middlewares:
            - security-headers
        priority: 100
        rule: "Host(\`middleware-manager.${DOMAIN}\`)"
        service: middleware-manager-service
        tls:
            certResolver: "letsencrypt"

    komodo-router-redirect:
      rule: "Host(\`komodo.${DOMAIN}\`)"
      service: komodo-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    komodo-router:
        entryPoints:
            - websecure
        middlewares:
            - security-headers
        priority: 100
        rule: "Host(\`komodo.${DOMAIN}\`)"
        service: komodo-service
        tls:
            certResolver: "letsencrypt"

    traefik-dashboard-router-redirect:
      rule: "Host(\`traefik.${DOMAIN}\`)"
      service: traefik-dashboard-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    traefik-dashboard-router:
        entryPoints:
            - websecure
        middlewares:
            - security-headers
        priority: 100
        rule: "Host(\`traefik.${DOMAIN}\`)"
        service: traefik-dashboard-service
        tls:
            certResolver: "letsencrypt"


  services:
    next-service:
      loadBalancer:
        servers:
          - url: "http://pangolin:3002" # Next.js server

    api-service:
      loadBalancer:
        servers:
          - url: "http://pangolin:3000" # API/WebSocket server

    statiq-service:
        loadBalancer:
            servers:
                - url: "noop@internal"

    middleware-manager-service:
        loadBalancer:
            servers:
                - url: "http://middleware-manager:3456"

    komodo-service:
        loadBalancer:
            servers:
                - url: "http://komodo-core-1:9120"

    traefik-dashboard-service:
        loadBalancer:
            servers:
                - url: "http://localhost:8080"

EOF
fi

echo "✅ dynamic_config.yml created"

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
- Admin Login: ${ADMIN_USERNAME}
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

if [ -n \"$CROWDSEC_ENROLLMENT_KEY\" ]; then
cat >> /host-setup/DEPLOYMENT_INFO.txt << EOF
└── crowdsec/
    ├── acquis.yaml
    ├── config.yaml
    └── profiles.yaml
📁 Additional:
./crowdsec_logs/          # Log volume for CrowdSec

🛡️ CrowdSec Notes:
- AppSec and log parsing is configured
- Prometheus and API are enabled
- CAPTCHA and remediation profiles are active
- Remember to get the bouncer API key after containers start:
  docker exec crowdsec cscli bouncers add traefik-bouncer
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

# Final summary
echo ""
echo "🎉 Setup Complete!"
echo "================================"
if [ -n \"$CROWDSEC_ENROLLMENT_KEY\" ]; then
    echo "✅ CrowdSec configuration included"
    echo "⚠️  Remember to:"
    echo "   1. Start your containers: docker compose up -d"
    echo "   2. Get bouncer key: docker exec crowdsec cscli bouncers add traefik-bouncer"
    echo "   3. Update dynamic_config.yml with the bouncer key"
    echo "   4. Restart traefik: docker compose restart traefik"
else
    echo "ℹ️  Basic Traefik configuration (no CrowdSec)"
    echo "💡 To add CrowdSec later, set CROWDSEC_ENROLLMENT_KEY and re-run"
fi