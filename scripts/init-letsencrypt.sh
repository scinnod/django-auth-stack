#!/bin/bash

# =============================================================================
# Let's Encrypt Initialization Script
# =============================================================================
# This script obtains initial TLS certificates from Let's Encrypt for all
# configured domains. Run this ONCE before starting the stack in LE mode.
#
# Prerequisites:
#   1. DNS records must point to this server (A/AAAA records)
#   2. Ports 80 and 443 must be accessible from the internet
#   3. Docker and docker compose must be installed
#
# Usage:
#   chmod +x scripts/init-letsencrypt.sh
#   ./scripts/init-letsencrypt.sh
# =============================================================================

set -e  # Exit on any error

# Load .env file if it exists
if [ -f .env ]; then
    # Export variables from .env (ignore comments and empty lines)
    set -a
    source <(grep -v '^#' .env | grep -v '^$' | sed 's/\r$//')
    set +a
fi

# Configuration - domains read from .env
DOMAINS=(
    "${DOMAIN_AUTH:-auth.example.org}"
    "${DOMAIN_ITSM:-itsm.example.org}"
    "${DOMAIN_DEEPL:-deepl.example.org}"
)
EMAIL="${LETSENCRYPT_EMAIL:-admin@example.org}"  # From .env or default
STAGING=0  # Set to 1 for testing (avoids rate limits)

COMPOSE_FILE="docker-compose.yml"
LE_COMPOSE_FILE="docker-compose.letsencrypt.yml"
CERTBOT_IMAGE="certbot/certbot:latest"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =============================================================================
# Preflight Checks
# =============================================================================

log_info "Starting Let's Encrypt initialization..."

# Check if running as root (may be needed for docker)
if [ "$EUID" -ne 0 ] && ! groups | grep -q docker; then
    log_warn "Not running as root and not in docker group. May need sudo."
fi

# Check if compose files exist
if [ ! -f "$COMPOSE_FILE" ]; then
    log_error "docker-compose.yml not found!"
    exit 1
fi

if [ ! -f "$LE_COMPOSE_FILE" ]; then
    log_error "docker-compose.letsencrypt.yml not found!"
    exit 1
fi

# Check if .env exists
if [ ! -f .env ]; then
    log_warn ".env file not found. Using defaults."
    log_warn "Copy .env.example to .env and configure before production use!"
fi

# =============================================================================
# Create Dummy Certificates (for initial nginx startup)
# =============================================================================

log_info "Creating dummy certificates for initial nginx startup..."

# Create volume if it doesn't exist
docker volume create edge-auth_certbot_certs > /dev/null 2>&1 || true
docker volume create edge-auth_certbot_webroot > /dev/null 2>&1 || true

# Generate dummy certificates for each domain
for domain in "${DOMAINS[@]}"; do
    log_info "Creating dummy certificate for $domain..."
    
    docker compose -f "$COMPOSE_FILE" -f "$LE_COMPOSE_FILE" run --rm --entrypoint "\
        openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
        -keyout '/etc/letsencrypt/live/$domain/privkey.pem' \
        -out '/etc/letsencrypt/live/$domain/fullchain.pem' \
        -subj '/CN=localhost'" certbot
    
    # Also create symlink at root level for shared cert config
    docker compose -f "$COMPOSE_FILE" -f "$LE_COMPOSE_FILE" run --rm --entrypoint "\
        sh -c 'ln -sf /etc/letsencrypt/live/$domain/fullchain.pem /etc/letsencrypt/fullchain.pem && \
        ln -sf /etc/letsencrypt/live/$domain/privkey.pem /etc/letsencrypt/privkey.pem'" certbot || true
done

# =============================================================================
# Start nginx
# =============================================================================

log_info "Starting nginx with dummy certificates..."
docker compose -f "$COMPOSE_FILE" -f "$LE_COMPOSE_FILE" up -d nginx

# Wait for nginx to be ready
log_info "Waiting for nginx to start..."
sleep 5

# Check if nginx is running
if ! docker compose -f "$COMPOSE_FILE" -f "$LE_COMPOSE_FILE" ps nginx | grep -q "Up"; then
    log_error "nginx failed to start. Check logs: docker compose logs nginx"
    exit 1
fi

# =============================================================================
# Obtain Real Certificates
# =============================================================================

log_info "Requesting Let's Encrypt certificates..."

# Set staging flag if testing
STAGING_ARG=""
if [ "$STAGING" -eq 1 ]; then
    log_warn "Using Let's Encrypt staging server (test certificates)"
    STAGING_ARG="--staging"
fi

# Request certificates for all domains
for domain in "${DOMAINS[@]}"; do
    log_info "Obtaining certificate for $domain..."
    
    docker compose -f "$COMPOSE_FILE" -f "$LE_COMPOSE_FILE" run --rm certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        $STAGING_ARG \
        -d "$domain"
    
    if [ $? -eq 0 ]; then
        log_info "Certificate obtained successfully for $domain"
    else
        log_error "Failed to obtain certificate for $domain"
        log_error "Check DNS configuration and firewall settings"
        exit 1
    fi
done

# =============================================================================
# Reload nginx with Real Certificates
# =============================================================================

log_info "Reloading nginx to use real certificates..."
docker compose -f "$COMPOSE_FILE" -f "$LE_COMPOSE_FILE" exec nginx nginx -s reload

if [ $? -eq 0 ]; then
    log_info "nginx reloaded successfully"
else
    log_error "Failed to reload nginx"
    exit 1
fi

# =============================================================================
# Completion
# =============================================================================

echo ""
log_info "=========================================="
log_info "Let's Encrypt initialization complete!"
log_info "=========================================="
echo ""
log_info "Next steps:"
log_info "  1. Verify certificates: docker compose exec nginx ls -la /etc/nginx/certs/live/"
log_info "  2. Test HTTPS access: curl -I https://${DOMAINS[0]}"
log_info "  3. Start full stack: docker compose -f $COMPOSE_FILE -f $LE_COMPOSE_FILE up -d"
echo ""
log_info "Certificates will auto-renew every 12 hours (if expiring in < 30 days)"
log_info "Monitor renewal: docker compose logs -f certbot"
echo ""

exit 0
