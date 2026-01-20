#!/bin/bash

# =============================================================================
# Self-Signed Certificate Generation Script
# =============================================================================
# Copyright (C) 2024-2026 David Kleinhans, Jade University of Applied Sciences
# SPDX-License-Identifier: Apache-2.0
# =============================================================================
# This script generates self-signed TLS certificates for development/testing.
# 
# WARNING: Self-signed certificates are NOT suitable for production!
# Use this only for:
#   - Development/testing environments
#   - Internal networks
#   - Temporary setup before obtaining real certificates
#
# For production, use:
#   - Let's Encrypt (free, automated) - see init-letsencrypt.sh
#   - Commercial CA certificates
#   - Organization-issued certificates
#
# Usage:
#   chmod +x scripts/init-selfsigned.sh
#   ./scripts/init-selfsigned.sh
# =============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CERT_DIR="certs"
CERT_DAYS=365
KEY_SIZE=2048
DHPARAM_SIZE=2048

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

# =============================================================================
# Main Script
# =============================================================================

echo ""
log_warn "=========================================="
log_warn "Self-Signed Certificate Generator"
log_warn "=========================================="
echo ""
log_warn "WARNING: Self-signed certificates are NOT suitable for production!"
log_warn "Browsers will show security warnings."
log_warn "Use Let's Encrypt for production deployments."
echo ""

read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Cancelled."
    exit 0
fi

# =============================================================================
# Gather Information
# =============================================================================

echo ""
log_step "Certificate Configuration"
echo ""

# Get domains (can use comma-separated list)
read -p "Enter domain(s) [*.example.org]: " domains
domains=${domains:-*.example.org}

# Get organization info
read -p "Country Code (2 letters) [US]: " country
country=${country:-US}

read -p "State/Province [California]: " state
state=${state:-California}

read -p "City [San Francisco]: " city
city=${city:-San Francisco}

read -p "Organization [Development]: " org
org=${org:-Development}

read -p "Organizational Unit [IT]: " ou
ou=${ou:-IT}

# Certificate validity
read -p "Certificate validity (days) [365]: " cert_days
cert_days=${cert_days:-$CERT_DAYS}

# =============================================================================
# Create Certificate Directory
# =============================================================================

log_step "Creating certificate directory..."

mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"

# Backup existing certificates if present
if [ -f "$CERT_DIR/fullchain.pem" ] || [ -f "$CERT_DIR/privkey.pem" ]; then
    backup_dir="$CERT_DIR/backup_$(date +%Y%m%d_%H%M%S)"
    log_warn "Existing certificates found. Backing up to $backup_dir"
    mkdir -p "$backup_dir"
    [ -f "$CERT_DIR/fullchain.pem" ] && mv "$CERT_DIR/fullchain.pem" "$backup_dir/"
    [ -f "$CERT_DIR/privkey.pem" ] && mv "$CERT_DIR/privkey.pem" "$backup_dir/"
fi

# =============================================================================
# Generate Private Key
# =============================================================================

log_step "Generating private key (${KEY_SIZE}-bit RSA)..."

openssl genrsa -out "$CERT_DIR/privkey.pem" $KEY_SIZE 2>/dev/null

chmod 600 "$CERT_DIR/privkey.pem"
log_info "Private key generated: $CERT_DIR/privkey.pem"

# =============================================================================
# Build Subject Alternative Names (SAN)
# =============================================================================

# Convert comma-separated domains to SAN format
IFS=',' read -ra DOMAIN_ARRAY <<< "$domains"
san_string=""
dns_count=1

for domain in "${DOMAIN_ARRAY[@]}"; do
    # Trim whitespace
    domain=$(echo "$domain" | xargs)
    
    if [ $dns_count -eq 1 ]; then
        san_string="DNS:$domain"
    else
        san_string="$san_string,DNS:$domain"
    fi
    
    ((dns_count++))
done

# Add localhost for local testing
san_string="$san_string,DNS:localhost,DNS:*.localhost,IP:127.0.0.1,IP:::1"

log_info "Subject Alternative Names: $san_string"

# =============================================================================
# Create OpenSSL Configuration
# =============================================================================

log_step "Creating certificate configuration..."

cat > "$CERT_DIR/openssl.cnf" <<EOF
[req]
default_bits = $KEY_SIZE
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[dn]
C = $country
ST = $state
L = $city
O = $org
OU = $ou
CN = ${DOMAIN_ARRAY[0]}

[req_ext]
subjectAltName = $san_string

[v3_ca]
subjectAltName = $san_string
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF

# =============================================================================
# Generate Certificate Signing Request and Self-Signed Certificate
# =============================================================================

log_step "Generating self-signed certificate (valid for $cert_days days)..."

openssl req -new -x509 \
    -key "$CERT_DIR/privkey.pem" \
    -out "$CERT_DIR/fullchain.pem" \
    -days "$cert_days" \
    -config "$CERT_DIR/openssl.cnf" \
    -extensions v3_ca 2>/dev/null

chmod 644 "$CERT_DIR/fullchain.pem"
log_info "Certificate generated: $CERT_DIR/fullchain.pem"

# Clean up config file
rm "$CERT_DIR/openssl.cnf"

# =============================================================================
# Generate DH Parameters (Optional but Recommended)
# =============================================================================

echo ""
read -p "Generate DH parameters for enhanced security? (recommended but slow) (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_step "Generating DH parameters (${DHPARAM_SIZE}-bit)..."
    log_warn "This may take several minutes..."
    
    openssl dhparam -out nginx/dhparam.pem $DHPARAM_SIZE 2>/dev/null
    
    chmod 644 nginx/dhparam.pem
    log_info "DH parameters generated: nginx/dhparam.pem"
else
    log_info "Skipping DH parameter generation"
    log_info "You can generate later with: openssl dhparam -out nginx/dhparam.pem 2048"
fi

# =============================================================================
# Display Certificate Information
# =============================================================================

echo ""
log_step "Certificate Details:"
echo ""

openssl x509 -in "$CERT_DIR/fullchain.pem" -noout -text | grep -A 2 "Subject:"
openssl x509 -in "$CERT_DIR/fullchain.pem" -noout -text | grep -A 1 "Validity"
openssl x509 -in "$CERT_DIR/fullchain.pem" -noout -text | grep -A 10 "Subject Alternative Name"

echo ""

# =============================================================================
# Completion
# =============================================================================

log_info "=========================================="
log_info "Certificate Generation Complete!"
log_info "=========================================="
echo ""
log_info "Generated files:"
log_info "  - $CERT_DIR/fullchain.pem (certificate)"
log_info "  - $CERT_DIR/privkey.pem (private key)"
[ -f "nginx/dhparam.pem" ] && log_info "  - nginx/dhparam.pem (DH parameters)"
echo ""
log_warn "IMPORTANT SECURITY NOTES:"
log_warn "  1. Self-signed certificates will show browser warnings"
log_warn "  2. NOT suitable for production use"
log_warn "  3. Users must manually accept the security exception"
log_warn "  4. For production, use Let's Encrypt or commercial CA"
echo ""
log_info "Next steps:"
log_info "  1. Update domains in nginx configs (nginx/conf.d/*.conf)"
log_info "  2. Start the stack: docker compose up -d"
log_info "  3. Accept browser security warnings when accessing HTTPS"
echo ""
log_info "For production, use Let's Encrypt:"
log_info "  ./scripts/init-letsencrypt.sh"
echo ""

exit 0
