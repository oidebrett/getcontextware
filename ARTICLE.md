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
* Paste in the full `pangolin-setup` container configuration script (see full script above)
* Add these environment variables:

```bash
DOMAIN=yourdomain.com
EMAIL=admin@yourdomain.com
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

---

## 🔥 Step 6: Lock Down Komodo Port

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

## 💡 Step 7: Bonus – Integrate CrowdSec (Optional)

If you’ve set up CrowdSec previously:

* Stop `pangolin-stack`
* Update `docker-compose.yml` in `pangolin-setup`
* Add the correct `ENROLL_KEY`
* Shell into the `crowdsec` container:

```bash
docker run --rm -it \
  --name crowdsec-shell \
  -v "$(pwd)/config/crowdsec:/etc/crowdsec" \
  crowdsecurity/crowdsec:latest
```

Then run:

```bash
cscli hub update
cscli capi register
cscli console enroll <instance-id>
```

If patterns are missing:

```bash
wget -P /opt https://github.com/crowdsecurity/crowdsec/archive/refs/tags/v1.6.9-rc2.zip
unzip /opt/v1.6.9-rc2.zip -d /opt
cp -r /opt/crowdsec-1.6.9-rc2/config/patterns/* /etc/crowdsec/patterns/
```

Restart:

```bash
docker compose up -d
```

---

## ✅ Summary

You now have a complete development and deployment environment using:

* **Komodo** for remote deployment, scripting, and stack control
* **Pangolin** for secure reverse proxy access
* Optional **CrowdSec** for behavioral protection

---

## 🙌 Thank You

Thanks for following this guide! With Komodo and Pangolin, you now have a powerful foundation for managing and securing your self-hosted applications.

Happy deploying! 🚀

More details here in this gist: https://gist.github.com/oidebrett/5eb260124513f71674b5534c45da67cc
```

---

