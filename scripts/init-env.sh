#!/bin/bash
# =============================================================================
# Environment Initialization Script
# =============================================================================
# Copyright (C) 2024-2026 David Kleinhans, Jade University of Applied Sciences
# SPDX-License-Identifier: Apache-2.0
# =============================================================================
# TODO: Verify SPDX headers are present in all newly created scripts
# =============================================================================
# This script initializes the .env file with secure random values.
# - Copies .env.example to .env if it doesn't exist
# - Generates secure random passwords and keys
# - Replaces placeholder values automatically
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
read -p "ITSM domain [itsm.example.local]: " domain_itsm
read -p "DeepL/Translation domain [translation.example.local]: " domain_deepl

if [ -n "$domain_auth" ]; then
    $SED_INPLACE "s|DOMAIN_AUTH=auth.example.local|DOMAIN_AUTH=${domain_auth}|g" .env
    log_info "Set DOMAIN_AUTH to ${domain_auth}"
    
    # Extract base domain for cookie (e.g., auth.example.local -> .example.local)
    cookie_domain=".${domain_auth#*.}"
    echo ""
    read -p "Cookie domain for SSO [${cookie_domain}]: " input_cookie_domain
    cookie_domain=${input_cookie_domain:-$cookie_domain}
    $SED_INPLACE "s|OAUTH2_PROXY_COOKIE_DOMAIN=.example.local|OAUTH2_PROXY_COOKIE_DOMAIN=${cookie_domain}|g" .env
    log_info "Set OAUTH2_PROXY_COOKIE_DOMAIN to ${cookie_domain}"
fi

if [ -n "$domain_itsm" ]; then
    $SED_INPLACE "s|DOMAIN_ITSM=itsm.example.local|DOMAIN_ITSM=${domain_itsm}|g" .env
    log_info "Set DOMAIN_ITSM to ${domain_itsm}"
fi

if [ -n "$domain_deepl" ]; then
    $SED_INPLACE "s|DOMAIN_DEEPL=translation.example.local|DOMAIN_DEEPL=${domain_deepl}|g" .env
    log_info "Set DOMAIN_DEEPL to ${domain_deepl}"
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
log_info "2. Create Docker networks:"
log_info "     docker network create itsm_backend"
log_info "     docker network create deepl_backend"
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
