#!/bin/bash

# Example deployment script for Pangolin + CrowdSec + Traefik
# This shows how to deploy the stack with your configuration

set -e

echo "🚀 Pangolin Stack Deployment Example"
echo

# Example configuration - REPLACE THESE WITH YOUR ACTUAL VALUES
DOMAIN="example.com"
EMAIL="admin@example.com"
ADMIN_USERNAME="admin@example.com"
ADMIN_PASSWORD="MySecurePassword123"

echo "📋 Configuration:"
echo "   Domain: $DOMAIN"
echo "   Email: $EMAIL"
echo "   Admin Username: $ADMIN_USERNAME"
echo "   Admin Password: [HIDDEN]"
echo

# Validate that docker-compose-setup.yml exists
if [ ! -f "docker-compose-setup.yml" ]; then
    echo "❌ docker-compose-setup.yml not found!"
    echo "   Download it first:"
    echo "   curl -sSL https://raw.githubusercontent.com/yourusername/pangolin-crowdsec-stack/main/docker-compose-setup.yml -o docker-compose-setup.yml"
    exit 1
fi

echo "🔧 Running setup first..."

# Run setup with environment variables
DOMAIN="$DOMAIN" EMAIL="$EMAIL" ADMIN_SUBDOMAIN="pangolin" ADMIN_USERNAME="$ADMIN_USERNAME" ADMIN_PASSWORD="$ADMIN_PASSWORD" docker compose -f docker-compose-setup.yml up

echo "🚀 Starting services..."

# Start services
docker compose up -d

echo
echo "✅ Deployment started!"
echo
echo "📊 Monitor the deployment:"
echo "   docker compose logs -f"
echo
echo "🌐 Once ready, access your dashboard at:"
echo "   https://$DOMAIN"
echo
echo "👤 Admin login:"
echo "   Username: $ADMIN_USERNAME"
echo "   Password: $ADMIN_PASSWORD"
echo
echo "⚠️  Note: Let's Encrypt certificates may take a few minutes to issue"
