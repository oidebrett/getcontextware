# Update package lists
apt-get update

# Install prerequisites
apt-get install -y ca-certificates curl gnupg postgresql 

# Set up Docker repository
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package lists again with Docker repository
apt-get update

# Install Docker
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add the default user to the docker group
usermod -aG docker ubuntu

# Enable Docker service
systemctl enable docker.service
systemctl enable containerd.service
systemctl start docker.service

echo "Docker installation completed successfully at $(date)!"


## 🌐 Step 0: Create the Docker Network

```bash
docker network create pangolin
````

## 🧱 Step 1: Install Komodo

### 1.1 Download Compose Files

```bash
mkdir -p ~/Projects/komodo
wget -P ~/Projects/komodo https://raw.githubusercontent.com/moghtech/komodo/main/compose/ferretdb.compose.yaml
wget -P ~/Projects/komodo https://raw.githubusercontent.com/moghtech/komodo/main/compose/compose.env
```

# Edit `ferretdb.compose.yaml` to append the network config at the end.
cat <<EOF >> ~/Projects/komodo/ferretdb.compose.yaml

networks:
  default:
    external: true
    name: pangolin
EOF

### 1.2 Configure `compose.env`

# Edit the following variables:

ENV_FILE="$HOME/Projects/komodo/compose.env"

# Generate secure random values
DB_PASSWORD=$(openssl rand -base64 10)
PASSKEY=$(openssl rand -base64 32)
WEBHOOK_SECRET=$(openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 32)

# Set the host (customize as needed)
HOST="https://komodo.mcpgateway.online"

# Update or insert values in compose.env
sed -i "/^KOMODO_DB_PASSWORD=/c\KOMODO_DB_PASSWORD=$DB_PASSWORD" "$ENV_FILE"

sed -i "/^KOMODO_PASSKEY=/c\KOMODO_PASSKEY=$PASSKEY" "$ENV_FILE"
sed -i "/^KOMODO_HOST=/c\KOMODO_HOST=$HOST" "$ENV_FILE"

sed -i "/^KOMODO_WEBHOOK_SECRET=/c\KOMODO_WEBHOOK_SECRET=$WEBHOOK_SECRET" "$ENV_FILE"
sed -i "/^KOMODO_JWT_SECRET=/c\KOMODO_JWT_SECRET=$JWT_SECRET" "$ENV_FILE"


cd $HOME/Projects/komodo
docker compose -p komodo -f ferretdb.compose.yaml --env-file compose.env up -d
```