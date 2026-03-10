#!/bin/bash

# =============================================================================
# Let's Encrypt Initialization Script
# =============================================================================
# Copyright (C) 2024-2026 David Kleinhans, Jade University of Applied Sciences
# SPDX-License-Identifier: Apache-2.0
# =============================================================================
# This script obtains initial TLS certificates from Let's Encrypt for all
# configured domains. Run this ONCE before starting the stack in LE mode.
#
# Prerequisites:
#   1. Set LETSENCRYPT_ENABLED=true in .env
#   2. DNS records must point to this server (A/AAAA records)
#   3. Ports 80 and 443 must be accessible from the internet
#   4. Docker and docker compose must be installed
#
# The script will automatically regenerate docker-compose.override.yml
# (via generate-compose-override.sh) if it doesn't yet include certbot.
#
# Usage:
#   chmod +x scripts/init-letsencrypt.sh
#   ./scripts/init-letsencrypt.sh
# =============================================================================

set -e  # Exit on any error

# =============================================================================
# Colors and Helper Functions (defined early — used throughout the script)
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Load .env file if it exists
if [ -f .env ]; then
    # Export variables from .env (ignore comments and empty lines)
    set -a
    source <(grep -v '^#' .env | grep -v '^$' | sed 's/\r$//')
    set +a
fi

# Configuration - domains read from .env
DOMAINS=("${DOMAIN_AUTH:-auth.example.org}")

# Dynamically add service domains from SERVICE_N_DOMAIN variables
for i in $(seq 1 99); do
    domain_var="SERVICE_${i}_DOMAIN"
    enabled_var="SERVICE_${i}_ENABLED"
    domain="${!domain_var}"
    enabled="${!enabled_var:-true}"
    
    # Stop if no more services
    [ -z "$domain" ] && break
    
    # Only add enabled services
    if [ "$enabled" = "true" ]; then
        DOMAINS+=("$domain")
    fi
done

EMAIL="${LETSENCRYPT_EMAIL:-admin@example.org}"  # From .env or default
STAGING=0  # Set to 1 for testing (avoids rate limits)

COMPOSE_FILE="docker-compose.yml"
LE_COMPOSE_FILE="docker-compose.letsencrypt.yml"
OVERRIDE_FILE="docker-compose.override.yml"
CERTBOT_IMAGE="certbot/certbot:latest"

# =============================================================================
# Ensure LETSENCRYPT_ENABLED=true and override is up-to-date
# =============================================================================
# The override file must include certbot. If it doesn't, we either auto-fix
# or tell the user exactly what to do.

LE_ENABLED="${LETSENCRYPT_ENABLED:-false}"

if [ "$LE_ENABLED" != "true" ]; then
    log_error "LETSENCRYPT_ENABLED is not set to 'true' in .env"
    log_error ""
    log_error "To enable Let's Encrypt, edit .env and set:"
    log_error "  LETSENCRYPT_ENABLED=true"
    log_error ""
    log_error "Then re-run this script."
    exit 1
fi

# Check if the override includes certbot config
OVERRIDE_NEEDS_REGEN=false
if [ ! -f "$OVERRIDE_FILE" ]; then
    OVERRIDE_NEEDS_REGEN=true
elif ! grep -q "certbot" "$OVERRIDE_FILE" 2>/dev/null; then
    OVERRIDE_NEEDS_REGEN=true
fi

if [ "$OVERRIDE_NEEDS_REGEN" = "true" ]; then
    log_warn "docker-compose.override.yml is missing or does not include certbot."
    log_info "Regenerating it now (running generate-compose-override.sh)..."
    echo ""
    if [ -x scripts/generate-compose-override.sh ]; then
        bash scripts/generate-compose-override.sh
    elif [ -f scripts/generate-compose-override.sh ]; then
        bash scripts/generate-compose-override.sh
    else
        log_error "scripts/generate-compose-override.sh not found!"
        log_error "Cannot generate the required override file."
        exit 1
    fi
    echo ""
    # Verify it worked
    if ! grep -q "certbot" "$OVERRIDE_FILE" 2>/dev/null; then
        log_error "Override regeneration failed — certbot still missing from $OVERRIDE_FILE"
        log_error "Check that LETSENCRYPT_ENABLED=true is in .env and try:"
        log_error "  ./scripts/generate-compose-override.sh"
        exit 1
    fi
    log_info "Override file regenerated successfully with certbot."
fi

# Build compose file flags.
# IMPORTANT: When using explicit -f flags, Docker Compose does NOT auto-load
# docker-compose.override.yml. We must include it explicitly.
COMPOSE_FLAGS="-f $COMPOSE_FILE -f $OVERRIDE_FILE"
log_info "Using compose flags: $COMPOSE_FLAGS"

# =============================================================================
# Preflight Checks
# =============================================================================

log_info "Starting Let's Encrypt initialization..."
log_info "Domains to certify: ${DOMAINS[*]}"
log_info "Contact email: $EMAIL"
if [ "$STAGING" -eq 1 ]; then
    log_warn "STAGING MODE: Will issue test certificates (not trusted by browsers)"
fi
echo ""

# Check if running as root (may be needed for docker)
if [ "$EUID" -ne 0 ] && ! groups | grep -q docker; then
    log_warn "Not running as root and not in docker group. May need sudo."
fi

# Check if compose files exist
if [ ! -f "$COMPOSE_FILE" ]; then
    log_error "docker-compose.yml not found!"
    exit 1
fi

# Check if .env exists
if [ ! -f .env ]; then
    log_warn ".env file not found. Using defaults."
    log_warn "Copy .env.example to .env and configure before production use!"
fi

# =============================================================================
# Clean Slate: Stop existing containers
# =============================================================================
# The nginx entrypoint regenerates config files from templates at startup.
# If old containers are running, they keep stale configs and won't pick up
# changes. A fresh start ensures the entrypoint runs with current templates.

log_info "Stopping any existing containers (clean slate)..."
docker compose $COMPOSE_FLAGS down 2>&1 || true
echo ""

# =============================================================================
# Create Dummy Certificates (for initial nginx startup)
# =============================================================================

log_info "Creating dummy certificates for initial nginx startup..."
log_info "(nginx needs valid cert files to start, even before real certs are obtained)"

# Note: Docker Compose automatically creates the certbot_certs and
# certbot_webroot named volumes (defined in docker-compose.letsencrypt.yml)
# when we first run the certbot service below. No manual volume creation needed.

# Generate dummy certificates for each domain
for domain in "${DOMAINS[@]}"; do
    log_info "Creating dummy certificate for $domain..."
    
    docker compose $COMPOSE_FLAGS run --rm --entrypoint "\
        sh -c 'mkdir -p /etc/letsencrypt/live/$domain && \
        openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
        -keyout /etc/letsencrypt/live/$domain/privkey.pem \
        -out /etc/letsencrypt/live/$domain/fullchain.pem \
        -subj /CN=localhost'" certbot
    
    # Also create symlink at root level for shared cert config
    docker compose $COMPOSE_FLAGS run --rm --entrypoint "\
        sh -c 'ln -sf /etc/letsencrypt/live/$domain/fullchain.pem /etc/letsencrypt/fullchain.pem && \
        ln -sf /etc/letsencrypt/live/$domain/privkey.pem /etc/letsencrypt/privkey.pem'" certbot || true
done

# =============================================================================
# Start nginx
# =============================================================================

log_info "Starting nginx with dummy certificates..."
docker compose $COMPOSE_FLAGS up -d nginx 2>&1

# Wait for nginx to be ready
log_info "Waiting for nginx to start (up to 30s)..."
for i in $(seq 1 6); do
    sleep 5
    # Docker Compose v2 uses "running" (lowercase), v1 uses "Up"
    if docker compose $COMPOSE_FLAGS ps nginx 2>/dev/null | grep -qiE "up|running"; then
        break
    fi
    if [ "$i" -eq 6 ]; then
        log_error "nginx failed to start!"
        log_error "--- docker compose ps ---"
        docker compose $COMPOSE_FLAGS ps -a 2>&1 | sed 's/^/  /'
        log_error "--- nginx container logs (last 40 lines) ---"
        docker compose $COMPOSE_FLAGS logs --tail=40 nginx 2>&1 | sed 's/^/  /'
        log_error "Common causes:"
        log_error "  - Missing certificate files in /etc/letsencrypt/ (symlink creation failed?)"
        log_error "  - Missing dhparam.pem (run: openssl dhparam -out ./certs/dhparam.pem 2048)"
        log_error "  - nginx config error (run: docker compose $COMPOSE_FLAGS run --rm nginx nginx -t)"
        exit 1
    fi
    log_info "  Still waiting... (${i}/6)"
done
log_info "nginx is running."

# =============================================================================
# ACME Challenge Self-Test
# =============================================================================
# Before asking Let's Encrypt to validate, verify that nginx actually serves
# files from the ACME challenge directory. This catches misconfigurations
# (missing location block, redirect loops, firewall issues) early.

log_info "Verifying ACME challenge path is working..."

# Create a test token in the certbot webroot via the certbot container
# (nginx has this volume mounted read-only, certbot has it read-write)
ACME_TEST_TOKEN="acme-test-$(date +%s)"
FIRST_DOMAIN="${DOMAINS[0]}"
docker compose $COMPOSE_FLAGS run --rm --entrypoint "\
    sh -c 'mkdir -p /var/www/certbot/.well-known/acme-challenge && \
    echo ok > /var/www/certbot/.well-known/acme-challenge/$ACME_TEST_TOKEN'" certbot

# Two-phase self-test from inside the nginx container:
#
# Phase 1: Verify the test file exists on disk (volume mount works)
# Phase 2: Verify nginx serves it over HTTP (config is correct)
#
# For the HTTP test we hit 127.0.0.1 without a Host header, which matches
# the default_server block in nginx.conf. That block has the ACME location.
# This verifies the default server path. The domain-specific servers use the
# same templates and same volume, so if the default works, they will too.
#
# Note: Alpine's busybox wget does NOT support --header, so we cannot set
# a custom Host header. Using the default_server is the reliable alternative.

log_info "  Phase 1: Checking file exists in nginx container..."
ACME_FILE_CHECK=$(docker compose $COMPOSE_FLAGS exec -T nginx \
    cat "/var/www/certbot/.well-known/acme-challenge/$ACME_TEST_TOKEN" 2>/dev/null || true)

if [ "$ACME_FILE_CHECK" != "ok" ]; then
    log_error "ACME self-test Phase 1 FAILED: test file not found in nginx container!"
    log_error "The certbot_webroot volume is not shared correctly between containers."
    log_error ""
    log_error "Debug:"
    docker compose $COMPOSE_FLAGS exec -T nginx \
        ls -la /var/www/certbot/.well-known/acme-challenge/ 2>&1 | sed 's/^/  [ls] /' || \
        log_error "  /var/www/certbot/.well-known/acme-challenge/ does not exist"
    docker compose $COMPOSE_FLAGS exec -T nginx \
        mount 2>&1 | grep certbot | sed 's/^/  [mount] /' || \
        log_error "  No certbot volume mounted"
    exit 1
fi
log_info "  Phase 1 passed: test file exists on disk in nginx container"

log_info "  Phase 2: Checking nginx serves it over HTTP..."
ACME_SELF_TEST=$(docker compose $COMPOSE_FLAGS exec -T nginx \
    wget -q -O - "http://127.0.0.1/.well-known/acme-challenge/$ACME_TEST_TOKEN" 2>/dev/null || true)

if [ "$ACME_SELF_TEST" = "ok" ]; then
    log_info "  Phase 2 passed: nginx serves ACME challenge files correctly"
    log_info "Internal ACME self-test passed!"
else
    log_error "ACME self-test Phase 2 FAILED: file exists on disk but nginx won't serve it!"
    log_error "The location /.well-known/acme-challenge/ block is missing or misconfigured."
    log_error ""
    log_error "Debug: wget verbose output from inside nginx container:"
    docker compose $COMPOSE_FLAGS exec -T nginx \
        wget -S -O - "http://127.0.0.1/.well-known/acme-challenge/$ACME_TEST_TOKEN" 2>&1 | sed 's/^/  /' || true
    log_error ""
    log_error "--- nginx config check (looking for acme-challenge blocks) ---"
    docker compose $COMPOSE_FLAGS exec -T nginx \
        grep -rn "acme-challenge" /etc/nginx/conf.d/*.conf /etc/nginx/nginx.conf 2>&1 | sed 's/^/  /' || true
    log_error ""
    log_error "The default_server block in nginx.conf must have:"
    log_error "  location /.well-known/acme-challenge/ { root /var/www/certbot; }"
    exit 1
fi

# Now test from the first domain (externally reachable?)
echo ""
log_info "============================================================"
log_info "EXTERNAL VERIFICATION REQUIRED"
log_info "============================================================"
log_info "Before proceeding, verify that the ACME challenge path is"
log_info "reachable from the internet. Open this URL in a browser or"
log_info "run this command from a DIFFERENT machine:"
echo ""
log_info "  curl http://$FIRST_DOMAIN/.well-known/acme-challenge/$ACME_TEST_TOKEN"
echo ""
log_info "Expected response: ok"
log_info "If you get a redirect (301), connection refused, or timeout,"
log_info "then Let's Encrypt cannot validate your domain."
log_info "============================================================"
echo ""

# Give user a chance to test before proceeding
read -p "Press ENTER to continue with certificate request (or Ctrl+C to abort)... " </dev/tty

# Clean up test token
docker compose $COMPOSE_FLAGS run --rm --entrypoint "\
    rm -f /var/www/certbot/.well-known/acme-challenge/$ACME_TEST_TOKEN" certbot 2>/dev/null || true

# =============================================================================
# Obtain Real Certificates
# =============================================================================

log_info "Requesting Let's Encrypt certificates..."
log_info "Let's Encrypt will validate domain ownership via HTTP-01 challenge."
log_info "The ACME server must be able to reach this server on port 80."
echo ""

# Set staging flag if testing
STAGING_ARG=""
if [ "$STAGING" -eq 1 ]; then
    log_warn "Using Let's Encrypt staging server (test certificates)"
    STAGING_ARG="--staging"
fi

# Request certificates for all domains
for domain in "${DOMAINS[@]}"; do
    log_info "============================================================"
    log_info "Obtaining certificate for $domain..."
    log_info "============================================================"
    log_info "  ACME URL: http://$domain/.well-known/acme-challenge/"
    log_info "  Timeout: 180s per domain"
    echo ""
    
    # Run certbot with debug-level output so the user sees each ACME protocol
    # step: authorization creation, challenge file placement, validation poll.
    #
    # Key flags:
    #   PYTHONUNBUFFERED=1  = force Python to flush output immediately
    #   -T                  = no pseudo-TTY (required for scripts)
    #   -v -v               = debug-level logging (shows HTTP requests to ACME)
    #   --preferred-challenges http = explicitly use HTTP-01
    #
    # Timeout: 180s should be enough for one domain. If it takes longer,
    # something is wrong (DNS, firewall, nginx config).
    #
    # We temporarily disable set -e because we need to capture the exit code.
    # Without this, a non-zero certbot exit would terminate the script before
    # we can show a helpful error message.
    
    set +e
    timeout 180 docker compose $COMPOSE_FLAGS run --rm -T \
        -e PYTHONUNBUFFERED=1 \
        certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        --non-interactive \
        --preferred-challenges http \
        -v -v \
        $STAGING_ARG \
        -d "$domain"
    CERTBOT_EXIT=$?
    set -e
    echo ""
    
    if [ "$CERTBOT_EXIT" -eq 0 ]; then
        log_info "Certificate obtained successfully for $domain"
    elif [ "$CERTBOT_EXIT" -eq 124 ]; then
        log_error "Timed out after 180s waiting for certificate for $domain"
        log_error "The ACME HTTP-01 challenge did not complete. This usually means"
        log_error "Let's Encrypt cannot reach http://$domain/.well-known/acme-challenge/"
        log_error ""
        log_error "Troubleshooting:"
        log_error "  1. Check DNS:  dig +short $domain  (must return this server's public IP)"
        log_error "  2. Check port: curl -sI http://$domain/.well-known/acme-challenge/test"
        log_error "     (should return 404, NOT a 301 redirect)"
        log_error "  3. Check firewall: port 80 must be open from the internet"
        log_error "  4. Check nginx logs: docker compose $COMPOSE_FLAGS logs nginx"
        exit 1
    else
        log_error "Failed to obtain certificate for $domain (exit code: $CERTBOT_EXIT)"
        log_error "Common causes:"
        log_error "  - DNS A/AAAA record for $domain does not point to this server"
        log_error "  - Port 80 is blocked by firewall (Let's Encrypt HTTP-01 challenge needs it)"
        log_error "  - nginx is not serving /.well-known/acme-challenge/ (check nginx logs)"
        log_error "Debug: docker compose $COMPOSE_FLAGS logs nginx"
        exit 1
    fi
done

# =============================================================================
# Reload nginx with Real Certificates
# =============================================================================

log_info "Reloading nginx to use real certificates..."
docker compose $COMPOSE_FLAGS exec nginx nginx -s reload

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
log_info "  3. Start full stack: docker compose $COMPOSE_FLAGS up -d"
echo ""
log_info "Certificates will auto-renew every 12 hours (if expiring in < 30 days)"
log_info "Monitor renewal: docker compose logs -f certbot"
echo ""

exit 0
