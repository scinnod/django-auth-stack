#!/bin/bash

# =============================================================================
# Environment Initialization Script
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

AUTHENTIK_SECRET_KEY=$(generate_secret_key)
log_info "Generated AUTHENTIK_SECRET_KEY (60 chars base64)"

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

# Replace AUTHENTIK_SECRET_KEY placeholder
if grep -q "AUTHENTIK_SECRET_KEY=CHANGE_ME_GENERATE_WITH_OPENSSL_RAND" .env; then
    $SED_INPLACE "s|AUTHENTIK_SECRET_KEY=CHANGE_ME_GENERATE_WITH_OPENSSL_RAND|AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}|g" .env
    log_info "Set AUTHENTIK_SECRET_KEY"
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
log_info "Domain Configuration (update these in .env manually if needed):"
read -p "ITSM domain [itsm.example.org]: " domain_itsm
read -p "DeepL domain [deepl.example.org]: " domain_deepl
read -p "Auth domain [auth.example.org]: " domain_auth

if [ -n "$domain_itsm" ]; then
    $SED_INPLACE "s|DOMAIN_ITSM=itsm.example.org|DOMAIN_ITSM=${domain_itsm}|g" .env
fi

if [ -n "$domain_deepl" ]; then
    $SED_INPLACE "s|DOMAIN_DEEPL=deepl.example.org|DOMAIN_DEEPL=${domain_deepl}|g" .env
fi

if [ -n "$domain_auth" ]; then
    $SED_INPLACE "s|DOMAIN_AUTH=auth.example.org|DOMAIN_AUTH=${domain_auth}|g" .env
fi

# SMTP configuration
echo ""
read -p "Configure SMTP/email settings now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "SMTP Host: " smtp_host
    read -p "SMTP Port [587]: " smtp_port
    smtp_port=${smtp_port:-587}
    read -p "SMTP Username: " smtp_user
    read -s -p "SMTP Password: " smtp_password
    echo
    read -p "SMTP From Address: " smtp_from
    read -p "Use TLS? (true/false) [true]: " smtp_tls
    smtp_tls=${smtp_tls:-true}
    
    if [ -n "$smtp_host" ]; then
        $SED_INPLACE "s|AUTHENTIK_EMAIL_HOST=|AUTHENTIK_EMAIL_HOST=${smtp_host}|g" .env
        $SED_INPLACE "s|AUTHENTIK_EMAIL_PORT=587|AUTHENTIK_EMAIL_PORT=${smtp_port}|g" .env
        $SED_INPLACE "s|AUTHENTIK_EMAIL_USERNAME=|AUTHENTIK_EMAIL_USERNAME=${smtp_user}|g" .env
        $SED_INPLACE "s|AUTHENTIK_EMAIL_PASSWORD=|AUTHENTIK_EMAIL_PASSWORD=${smtp_password}|g" .env
        $SED_INPLACE "s|AUTHENTIK_EMAIL_FROM=|AUTHENTIK_EMAIL_FROM=${smtp_from}|g" .env
        $SED_INPLACE "s|AUTHENTIK_EMAIL_USE_TLS=true|AUTHENTIK_EMAIL_USE_TLS=${smtp_tls}|g" .env
        log_info "SMTP configuration saved"
    fi
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
log_info "  - AUTHENTIK_SECRET_KEY"
echo ""
log_warn "IMPORTANT: Review .env file and update any remaining placeholders"
log_warn "Keep .env file secure - it contains sensitive credentials!"
echo ""
log_info "Next steps:"
log_info "  1. Review .env file: nano .env"
log_info "  2. Update domain names if needed (replace example.org)"
log_info "  3. Configure SMTP settings (if not done above)"
log_info "  4. Create external networks:"
log_info "       docker network create itsm_backend"
log_info "       docker network create deepl_backend"
log_info "  5. Choose TLS mode and start stack (see README.md)"
echo ""

exit 0
