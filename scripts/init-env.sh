#!/bin/bash
# =============================================================================
# Environment Initialization Script
# =============================================================================
# Copyright (C) 2024-2026 David Kleinhans, Jade University of Applied Sciences
# SPDX-License-Identifier: Apache-2.0
# =============================================================================
# This script initializes the .env file with secure random values and
# configures upstream services dynamically.
#
# Features:
# - Generates secure random passwords and keys
# - Configures any number of upstream services (0 to N)
# - Supports two authentication patterns per service:
#   - Pattern A: Django-controlled (public pages + protected areas)
#   - Pattern B: Full nginx-level auth (everything protected)
# - Per-service enable/disable toggle
#
# Usage:
#   chmod +x scripts/init-env.sh
#   ./scripts/init-env.sh
# =============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

log_service() {
    echo -e "${CYAN}[SERVICE]${NC} $1"
}

generate_password() {
    # Generate a secure random password (32 characters, alphanumeric + special chars)
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

generate_secret_key() {
    # Generate a secure secret key (60 characters base64)
    openssl rand -base64 60 | tr -d "\n"
}

# =============================================================================
# Main Script
# =============================================================================

echo ""
log_info "=========================================="
log_info "Edge-Auth Stack - Environment Setup"
log_info "=========================================="
echo ""

# Check if .env already exists
if [ -f .env ]; then
    log_warn ".env file already exists!"
    echo ""
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Keeping existing .env file. Exiting."
        exit 0
    fi
    
    # Backup existing .env
    backup_file=".env.backup.$(date +%Y%m%d_%H%M%S)"
    log_step "Backing up existing .env to $backup_file"
    cp .env "$backup_file"
fi

# Check if .env.example exists
if [ ! -f .env.example ]; then
    log_error ".env.example not found!"
    exit 1
fi

# Copy .env.example to .env
log_step "Copying .env.example to .env..."
cp .env.example .env

# Generate secure random values
log_step "Generating secure random values..."

POSTGRES_PASSWORD=$(generate_password)
log_info "Generated POSTGRES_PASSWORD (32 chars)"

KEYCLOAK_ADMIN_PASSWORD=$(generate_password)
log_info "Generated KEYCLOAK_ADMIN_PASSWORD (32 chars)"

OAUTH2_COOKIE_SECRET=$(openssl rand -base64 32 | head -c 32)
log_info "Generated OAUTH2_PROXY_COOKIE_SECRET (32 chars)"

# Replace placeholders in .env file
log_step "Replacing placeholders in .env..."

# macOS vs Linux sed compatibility
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    SED_INPLACE="sed -i ''"
else
    # Linux
    SED_INPLACE="sed -i"
fi

# Replace POSTGRES_PASSWORD placeholder
if grep -q "POSTGRES_PASSWORD=CHANGE_ME_STRONG_PASSWORD_HERE" .env; then
    $SED_INPLACE "s|POSTGRES_PASSWORD=CHANGE_ME_STRONG_PASSWORD_HERE|POSTGRES_PASSWORD=${POSTGRES_PASSWORD}|g" .env
    log_info "Set POSTGRES_PASSWORD"
fi

# Replace KEYCLOAK_ADMIN_PASSWORD placeholder
if grep -q "KEYCLOAK_ADMIN_PASSWORD=CHANGE_ME_ADMIN_PASSWORD" .env; then
    $SED_INPLACE "s|KEYCLOAK_ADMIN_PASSWORD=CHANGE_ME_ADMIN_PASSWORD|KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD}|g" .env
    log_info "Set KEYCLOAK_ADMIN_PASSWORD"
fi

# Replace OAUTH2_PROXY_COOKIE_SECRET placeholder
if grep -q "OAUTH2_PROXY_COOKIE_SECRET=REPLACE_WITH_32_CHAR_RANDOM_STRING" .env; then
    $SED_INPLACE "s|OAUTH2_PROXY_COOKIE_SECRET=REPLACE_WITH_32_CHAR_RANDOM_STRING|OAUTH2_PROXY_COOKIE_SECRET=${OAUTH2_COOKIE_SECRET}|g" .env
    log_info "Set OAUTH2_PROXY_COOKIE_SECRET"
fi

# =============================================================================
# User Configuration Prompts
# =============================================================================

echo ""
log_step "Additional Configuration (optional - press Enter to skip):"
echo ""

# Email for Let's Encrypt
read -p "Email address for Let's Encrypt notifications [admin@example.org]: " letsencrypt_email
if [ -n "$letsencrypt_email" ]; then
    $SED_INPLACE "s|LETSENCRYPT_EMAIL=admin@example.org|LETSENCRYPT_EMAIL=${letsencrypt_email}|g" .env
    log_info "Set LETSENCRYPT_EMAIL to $letsencrypt_email"
fi

# Domain configuration
echo ""
log_info "Domain Configuration:"
log_warn "For development: use .local domains (e.g., .example.local)"
log_warn "For production: use actual domains (e.g., .example.com)"
echo ""
read -p "Auth domain [auth.example.local]: " domain_auth
domain_auth=${domain_auth:-auth.example.local}

$SED_INPLACE "s|DOMAIN_AUTH=auth.example.local|DOMAIN_AUTH=${domain_auth}|g" .env
log_info "Set DOMAIN_AUTH to ${domain_auth}"

# Extract base domain for cookie (e.g., auth.example.local -> .example.local)
cookie_domain=".${domain_auth#*.}"
echo ""
read -p "Cookie domain for SSO [${cookie_domain}]: " input_cookie_domain
cookie_domain=${input_cookie_domain:-$cookie_domain}
$SED_INPLACE "s|OAUTH2_PROXY_COOKIE_DOMAIN=.example.local|OAUTH2_PROXY_COOKIE_DOMAIN=${cookie_domain}|g" .env
log_info "Set OAUTH2_PROXY_COOKIE_DOMAIN to ${cookie_domain}"

# =============================================================================
# Service Configuration
# =============================================================================

echo ""
log_step "=========================================="
log_step "Upstream Service Configuration"
log_step "=========================================="
echo ""
log_info "Configure the services you want to protect with Keycloak authentication."
log_info "You can add any number of services (0 or more)."
echo ""
log_info "Authentication Patterns:"
log_info "  Pattern A: Django-controlled auth"
log_info "             - Django decides what's public vs protected"
log_info "             - Use @login_required for protected pages"
log_info "             - Good for apps with public + private areas"
echo ""
log_info "  Pattern B: Full nginx-level auth"
log_info "             - ALL requests require authentication"
log_info "             - Everything protected, no public access"
log_info "             - Good for internal tools, admin panels"
echo ""

# Remove placeholder service configs from .env
$SED_INPLACE '/^# Service 1 Example/d' .env
$SED_INPLACE '/^SERVICE_1_/d' .env
$SED_INPLACE '/^# Service 2 Example/d' .env
$SED_INPLACE '/^SERVICE_2_/d' .env

# Collect services
declare -a services
service_num=0

while true; do
    echo ""
    read -p "Add a service? (y/N): " -n 1 -r add_service
    echo
    
    if [[ ! $add_service =~ ^[Yy]$ ]]; then
        break
    fi
    
    service_num=$((service_num + 1))
    
    echo ""
    log_service "Configuring Service #${service_num}"
    echo ""
    
    # Service name (used for config filename and logging)
    read -p "  Service name (e.g., itsm, myapp, dashboard): " svc_name
    if [ -z "$svc_name" ]; then
        log_warn "Service name required, skipping this service"
        service_num=$((service_num - 1))
        continue
    fi
    # Sanitize name (lowercase, alphanumeric and underscores only)
    svc_name=$(echo "$svc_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]/_/g')
    
    # Domain
    default_domain="${svc_name}${cookie_domain}"
    read -p "  Domain [${default_domain}]: " svc_domain
    svc_domain=${svc_domain:-$default_domain}
    
    # Upstream (container:port)
    default_upstream="${svc_name}_nginx:8000"
    read -p "  Upstream container:port [${default_upstream}]: " svc_upstream
    svc_upstream=${svc_upstream:-$default_upstream}
    
    # Network
    default_network="${svc_name}_backend"
    read -p "  Docker network [${default_network}]: " svc_network
    svc_network=${svc_network:-$default_network}
    
    # Pattern
    echo ""
    echo "  Authentication pattern:"
    echo "    A = Django-controlled (recommended for Django apps)"
    echo "    B = Full nginx-level auth (for internal tools)"
    read -p "  Pattern (A/B) [A]: " svc_pattern
    svc_pattern=${svc_pattern:-A}
    svc_pattern=$(echo "$svc_pattern" | tr '[:lower:]' '[:upper:]')
    
    # Enabled
    read -p "  Enable this service? (Y/n): " -n 1 -r svc_enabled
    echo
    if [[ $svc_enabled =~ ^[Nn]$ ]]; then
        svc_enabled="false"
    else
        svc_enabled="true"
    fi
    
    # Add to .env file
    echo "" >> .env
    echo "# --- Service ${service_num}: ${svc_name} ---" >> .env
    echo "SERVICE_${service_num}_NAME=${svc_name}" >> .env
    echo "SERVICE_${service_num}_ENABLED=${svc_enabled}" >> .env
    echo "SERVICE_${service_num}_PATTERN=${svc_pattern}" >> .env
    echo "SERVICE_${service_num}_DOMAIN=${svc_domain}" >> .env
    echo "SERVICE_${service_num}_UPSTREAM=${svc_upstream}" >> .env
    echo "SERVICE_${service_num}_NETWORK=${svc_network}" >> .env
    
    log_info "Added service: ${svc_name} (Pattern ${svc_pattern}, enabled=${svc_enabled})"
done

if [ $service_num -eq 0 ]; then
    log_warn "No services configured. You can add them later by editing .env"
    log_info "See .env.example for the SERVICE_* variable format."
fi

# =============================================================================
# Completion
# =============================================================================

echo ""
log_info "=========================================="
log_info "Environment setup complete!"
log_info "=========================================="
echo ""
log_info "Created: .env"
log_info "Generated secure random values for:"
log_info "  - POSTGRES_PASSWORD"
log_info "  - KEYCLOAK_ADMIN_PASSWORD"
log_info "  - OAUTH2_PROXY_COOKIE_SECRET"
if [ $service_num -gt 0 ]; then
    log_info "Configured $service_num service(s)"
fi
echo ""
log_warn "IMPORTANT: Keep .env file secure - it contains sensitive credentials!"
echo ""
log_info "========================================"
log_info "Next Steps - REQUIRED:"
log_info "========================================"
echo ""
log_info "1. Review and verify .env file:"
log_info "     nano .env"
echo ""
if [ $service_num -gt 0 ]; then
    log_info "2. Create Docker networks for your services:"
    for i in $(seq 1 $service_num); do
        eval svc_network="\${SERVICE_${i}_NETWORK:-}"
        if [ -n "$svc_network" ]; then
            log_info "     docker network create ${svc_network}"
        fi
    done
else
    log_info "2. Create Docker networks for any services you add later:"
    log_info "     docker network create <service>_backend"
fi
echo ""
log_info "3. Start the stack and access Keycloak:"
log_info "     docker compose up -d"
log_info "     Access: https://${domain_auth:-auth.example.local}"
log_info "     Username: admin"
log_info "     Password: <check .env file for KEYCLOAK_ADMIN_PASSWORD>"
echo ""
log_warn "========================================"
log_warn "MANUAL CONFIGURATION REQUIRED:"
log_warn "========================================"
echo ""
log_warn "After Keycloak is running, you MUST:"
echo ""
log_warn "1. Login to Keycloak admin console"
log_warn "2. Create or import the realm (e.g., 'jade')"
log_warn "3. Create an OIDC client named 'oauth2-proxy' with:"
log_warn "     - Client ID: oauth2-proxy"
log_warn "     - Access Type: confidential"
log_warn "     - Valid Redirect URIs: https://*/oauth2/callback"
log_warn "4. Get the client secret from: Clients → oauth2-proxy → Credentials"
log_warn "5. Update .env file with the client secret:"
log_warn "     OAUTH2_PROXY_CLIENT_SECRET=<secret-from-keycloak>"
log_warn "6. Restart the stack:"
log_warn "     docker compose restart oauth2-proxy"
echo ""
log_info "For detailed instructions, see: README.md"
echo ""

exit 0
