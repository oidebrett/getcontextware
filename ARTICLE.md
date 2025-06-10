# 🛠️ Installing and Setting Up Komodo and Pangolin with Docker

This guide will walk you through installing [Komodo](https://github.com/moghtech/komodo) and [Pangolin](https://github.com/fosrl/pangolin) on a Linux server using Docker and Docker Compose. It assumes a VPS with a public IP and a domain name pointing to your server.

---

## 📋 Prerequisites

- A VPS or server running Ubuntu/Debian
- Domain name (e.g., `yourdomain.com`)
- Docker & Docker Compose installed
- Ports `80`, `443`, and `51820/udp` open
- `ufw` (Uncomplicated Firewall) configured
- Email address for Let's Encrypt certificates

---

## 🌐 Step 0: Create the Docker Network

```bash
docker network create pangolin
````

---

## 🧱 Step 1: Install Komodo

### 1.1 Download Compose Files

```bash
mkdir komodo
wget -P komodo https://raw.githubusercontent.com/moghtech/komodo/main/compose/ferretdb.compose.yaml
wget -P komodo https://raw.githubusercontent.com/moghtech/komodo/main/compose/compose.env
```

Edit `ferretdb.compose.yaml` to append the network config at the end.
```
networks:
  default:
    external: true
    name: pangolin
```
---

### 1.2 Configure `compose.env`

Edit the following variables:

```bash
KOMODO_DB_USERNAME=admin
KOMODO_DB_PASSWORD=$(openssl rand -base64 10)

KOMODO_PASSKEY=$(openssl rand -base64 32)
KOMODO_HOST=https://komodo.yourdomain.com

KOMODO_WEBHOOK_SECRET=$(openssl rand -base64 32)
KOMODO_JWT_SECRET=$(openssl rand -base64 32)

KOMODO_LOCAL_AUTH=true
```

---

### 1.3 Start Komodo

```bash
cd komodo
docker compose -p komodo -f ferretdb.compose.yaml --env-file compose.env up -d
```

Visit `http://your-server-ip:9120` and register a new user.

> 📸 *Screenshot suggestion: Komodo signup page*

---

## 🐧 Step 2: Set Up Pangolin Using Komodo

### 2.1 Create Stack: `pangolin-setup`

In Komodo:

* Create new stack: **`pangolin-setup`**
* Choose **UI Defined**
* Paste in the full `pangolin-setup` container configuration script (see full script below)

```
services:
  # Setup container that creates folder structure and config files
  setup:
    image: alpine:latest
    container_name: pangolin-setup
    volumes:
      - ./:/host-setup
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - DOMAIN=${DOMAIN:-}
      - EMAIL=${EMAIL:-}
      - ADMIN_USERNAME=${ADMIN_USERNAME:-}
      - ADMIN_PASSWORD=${ADMIN_PASSWORD:-}
      - ADMIN_SUBDOMAIN=${ADMIN_SUBDOMAIN:-pangolin}
      - GITHUB_USER=${GITHUB_USER:-oidebrett}
      - GITHUB_REPO=${GITHUB_REPO:-getcontextware}
      - GITHUB_BRANCH=${GITHUB_BRANCH:-main}
    command: |
      sh -c "
        echo '🚀 Starting Pangolin setup container...'

        # Install required tools
        apk add --no-cache curl docker-cli openssl

        # Validate required environment variables
        if [ -z \"$$DOMAIN\" ] || [ -z \"$$EMAIL\" ] || [ -z \"$$ADMIN_PASSWORD\" ]; then
          echo '❌ Error: Required environment variables not set!'
          echo 'Usage: DOMAIN=example.com EMAIL=admin@example.com ADMIN_USERNAME=admin@example.com ADMIN_PASSWORD=mypassword docker compose -f docker-compose-setup.yml up'
          echo 'Required variables:'
          echo '  DOMAIN - Your domain name (e.g., example.com)'
          echo '  EMAIL - Email for Lets Encrypt certificates'
          echo '  ADMIN_USERNAME - Admin username for Pangolin (email format)'
          echo '  ADMIN_PASSWORD - Admin password for Pangolin (min 8 chars)'
          echo 'Optional variables:'
          echo '  ADMIN_SUBDOMAIN - Subdomain for admin portal (default: pangolin)'
          exit 1
        fi

        # Check if config folder already exists
        if [ -d \"/host-setup/config\" ]; then
          echo '⚠️ Config folder already exists!'
          echo 'To avoid overwriting your configuration, setup will not proceed.'
          echo 'If you want to run setup again, please remove or rename the existing config folder.'
          exit 1
        fi

        # Validate domain format
        if ! echo \"$$DOMAIN\" | grep -E '^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\\.[a-zA-Z]{2,}$$' > /dev/null; then
          echo '❌ Error: Invalid domain format'
          exit 1
        fi

        # Validate email format
        if ! echo \"$$EMAIL\" | grep -E '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$$' > /dev/null; then
          echo '❌ Error: Invalid email format'
          exit 1
        fi

        # Validate username email format
        if ! echo \"$$ADMIN_USERNAME\" | grep -E '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$$' > /dev/null; then
          echo '❌ Error: Invalid admin username email format'
          exit 1
        fi

        # Validate password length
        if [ $${#ADMIN_PASSWORD} -lt 8 ]; then
          echo '❌ Error: Password must be at least 8 characters long'
          exit 1
        fi

        echo '✅ Environment variables validated'

        # Download container setup script from GitHub
        echo '📥 Downloading setup script from GitHub...'
        BASE_URL=\"https://raw.githubusercontent.com/$$GITHUB_USER/$$GITHUB_REPO/$$GITHUB_BRANCH\"

        if ! curl -fsSL \"$$BASE_URL/container-setup.sh\" -o /container-setup.sh; then
          echo '❌ Failed to download setup script from GitHub'
          echo 'Make sure the repository exists and is accessible:'
          echo \"$$BASE_URL/container-setup.sh\"
          exit 1
        fi

        chmod +x /container-setup.sh
        echo '✅ Setup script downloaded'

        # Run the setup script
        echo '🔧 Running setup script...'
        /container-setup.sh

        # Create docker-compose.yml for services
        echo '📝 Creating docker-compose.yml for services...'
        cat > /host-setup/docker-compose.yml << 'EOF'
        services:
          # Main Pangolin application
          pangolin:
            image: fosrl/pangolin:1.5.0
            container_name: pangolin
            restart: unless-stopped
            volumes:
              - ./config:/app/config
            healthcheck:
              test: ["CMD", "curl", "-f", "http://localhost:3001/api/v1/"]
              interval: "3s"
              timeout: "3s"
              retries: 15

          # Gerbil WireGuard management
          gerbil:
            image: fosrl/gerbil:1.0.0
            container_name: gerbil
            restart: unless-stopped
            depends_on:
              pangolin:
                condition: service_healthy
            command:
              - --reachableAt=http://gerbil:3003
              - --generateAndSaveKeyTo=/var/config/key
              - --remoteConfig=http://pangolin:3001/api/v1/gerbil/get-config
              - --reportBandwidthTo=http://pangolin:3001/api/v1/gerbil/receive-bandwidth
            volumes:
              - ./config/:/var/config
            cap_add:
              - NET_ADMIN
              - SYS_MODULE
            ports:
              - 51820:51820/udp
              - 443:443 # Port for traefik because of the network_mode
              - 80:80 # Port for traefik because of the network_mode

          # Traefik reverse proxy
          traefik:
            image: traefik:v3.4.0
            container_name: traefik
            restart: unless-stopped
            network_mode: service:gerbil # Ports appear on the gerbil service
            depends_on:
              pangolin:
                condition: service_healthy
            command:
              - --configFile=/etc/traefik/traefik_config.yml
            volumes:
              - ./config/traefik:/etc/traefik:ro # Volume to store the Traefik configuration
              - ./config/letsencrypt:/letsencrypt # Volume to store the Lets Encrypt certificates
              - ./config/traefik/rules:/rules
              - ./config/traefik/logs:/var/log/traefik

        networks:
          default:
            driver: bridge
            name: pangolin
      EOF
      
        echo '✅ Setup completed! The stack is ready to start.'
        echo '📊 Start your services with: docker compose up -d'
        echo '🌐 Access at: https://'"$$ADMIN_SUBDOMAIN"'.'"$$DOMAIN"
        echo '👤 Admin login: '"$$ADMIN_USERNAME"

        # Keep container running briefly to show completion message
        sleep 5

      "
    restart: "no"
```

* Add these environment variables:

```bash
DOMAIN=yourdomain.com
EMAIL=admin@yourdomain.com
ADMIN_USERNAME=admin@yourdomain.com
ADMIN_PASSWORD=securepassword
ADMIN_SUBDOMAIN=pangolin
```

Deploy and check `/etc/komodo/stacks/pangolin-setup` for output.

> 📸 *Screenshot suggestion: Komodo stack config page*

---

## 🚀 Step 3: Deploy Pangolin

1. Create new stack: `pangolin-stack`
2. Choose: **File on Server**
3. Path: `/etc/komodo/stacks/pangolin-setup`
4. File: `docker-compose.yml`

Click Deploy.

> 📸 *Screenshot suggestion: Komodo stack deployment view*

Verify services:

```bash
docker ps
```

Expected containers: `pangolin`, `traefik`, `gerbil`, `komodo-core-1`, `komodo-ferretdb-1`, `komodo-postgres-1`

---

## 🧹 Step 4: Clean Up

Delete the `pangolin-setup` stack from Komodo. It’s no longer needed.

---

## 🔐 Step 5: Secure Komodo with Pangolin

1. Add a **new resource** in Pangolin:

   * Name: `komodo.yourdomain.com`
   * Target: `komodo-core-1`
   * Port: `9120`
   * Site: Local
   * Protected: ✅ Yes

> 📸 *Screenshot suggestion: Pangolin resource setup*

Now access Komodo at:

```
https://komodo.yourdomain.com
```

## 🔐 Step 6: Secure Middleware Manger with Pangolin

1. Add a **new resource** in Pangolin:

   * Name: `middleware-manager.yourdomain.com`
   * Target: `middleware-manager`
   * Port: `3456`
   * Site: Local
   * Protected: ✅ Yes

> 📸 *Screenshot suggestion: Pangolin resource setup*

Now access Middleware Manager at:

```
https://middleware-manager.yourdomain.com
```

---

## 🔐 Step 7: Secure Traefik Dashboard with Pangolin

1. Add a **new resource** in Pangolin:

   * Name: `traefik.yourdomain.com`
   * Target: `loalhost`
   * Port: `8080`
   * Site: Local
   * Protected: ✅ Yes

> 📸 *Screenshot suggestion: Pangolin resource setup*

Now access Traefik Dashboard at:

```
https://traefik.yourdomain.com
```


## 🔥 Step 8: Lock Down Komodo Port

If open, close direct access:

```bash
sudo ufw delete allow 9120/tcp
sudo ufw deny 9120/tcp
sudo ufw enable
```

Edit `ferretdb.compose.yaml` to remove:

```yaml
ports:
  - "9120:9120"
```

Restart:

```bash
docker compose -p komodo -f ferretdb.compose.yaml --env-file compose.env down
docker compose -p komodo -f ferretdb.compose.yaml --env-file compose.env up -d --force-recreate
```

Test: `http://your-ip:9120` should now be inaccessible.

---

# Crowdsec

---

### 9. 🔐 Generate API Key for Crowdsec Bouncer

```bash
docker exec crowdsec cscli bouncers add traefik-bouncer
```
it will return something like

```
API key for 'traefik-bouncer':

   YOUR-LAPI-KEY-HERE

Please keep this key since you will not be able to retrieve it! You will need it later

```
Save the API key for use in the middleware.

---

### 10. ☁️ Set Up Cloudflare Turnstile

* Visit [https://dash.cloudflare.com/](https://dash.cloudflare.com/)
* Create a **Turnstile Widget**
* Copy the **site key** and **secret key**
![AddingTurnstyle|598x500](upload://q1h7CRHg83SajaisbcsRSUxQjRj.png)

📸 Screenshot Widget config page

---

### 11. 🧩 Add the Crowdsec Bouncer Plugin in the Middleware Manager
We now use the middleware manager to install the Crowdsec Bouncer Plugin to our traefik_config

![InstallCrowdsecBouncerWithMiddleware|690x441](upload://rDfaxXfU3EnA0cB9q2m46BlmOzn.png)


📸 Screenshot - Adding Plugin
---

### 12. 🧩 Add the Middleware in Middleware Manager

Navigate to **Middleware Manager > Plugins** and configure the CrowdSec plugin with:

```json
{
  "crowdsec-bouncer-traefik": {
    "enabled": true,
    "captchaProvider": "turnstile",
    "captchaSiteKey": "YOUR_TURNSTILE_KEY",
    "captchaSecretKey": "YOUR_TURNSTILE_SECRET",
    "captchaHTMLFilePath": "/etc/traefik/conf/captcha.html",
    "crowdsecLapiHost": "crowdsec:8080",
    "crowdsecAppsecHost": "crowdsec:7422",
    "crowdsecLapiKey": "YOUR_API_KEY",
    "crowdsecMode": "live",
    "clientTrustedIPs": [],
    "forwardedHeadersTrustedIPs": ["0.0.0.0/0"]
  }
}
```
![EditCrowdsecMiddleware|690x485](upload://pvnoxppcP3MFIoz5bKfdAaownf8.png)

📸 *Screenshot Middleware Manager CrowdSec form*

---

### 13. 🌐 Protect a Resource

Protect a test or live resource (e.g., `secure.yourdomain.com`) in Pangolin and attach the **CrowdSec middleware** using the Middleware Manager.

![AddingMiddleToResource|684x500](upload://3sWJl6Ih46H1YTeqKfsAvUjJDmu.png)

📸 *Screenshot: Attaching middleware to resource*

---

### 14. 🧪 Test

Manually trigger a CAPTCHA challenge:

```bash
docker exec crowdsec cscli decisions add --ip YOUR_IP --type captcha -d 1h
```
![decision-captcha|690x98](upload://fXClLCIPay1p4DYWVBV2PymRVNC.png)

Visit your protected site and validate the CAPTCHA appears.
![Captcha|690x451](upload://ilyXKvCRtJEVxhSL4Q3xBVmeChp.png)

---


---

## ✅ Summary

You now have a complete development and deployment environment using:

* **Komodo** for remote deployment, scripting, and stack control
* **Pangolin** for secure reverse proxy access
* **Middleware Manager** for advanced management
* Optional **CrowdSec** for behavioral protection

---

## 🙌 Thank You

Thanks for following this guide! With Komodo and Pangolin, you now have a powerful foundation for managing and securing your self-hosted applications.

Happy deploying! 🚀

More details here in this gist: https://gist.github.com/oidebrett/5eb260124513f71674b5534c45da67cc
```

---

