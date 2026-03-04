#!/bin/bash
# =============================================================================
# Pre-flight Check Script - Run BEFORE docker-compose up
# =============================================================================
# Copyright (C) 2024-2026 David Kleinhans, Jade University of Applied Sciences
# SPDX-License-Identifier: Apache-2.0
# =============================================================================
# This script validates that all required files exist and are properly
# configured before starting the Docker stack. Run this to avoid common
# startup issues like:
#   - Missing certificates (Docker creates root-owned empty directories)
#   - Missing DH parameters
#   - Missing .env file
#   - External networks not created
#
# Usage:
#   ./scripts/preflight-check.sh          # Check only
#   ./scripts/preflight-check.sh --fix    # Check and fix issues
#
# Exit codes:
#   0 - All checks passed
#   1 - Checks failed (see output for details)
# =============================================================================

# Don't exit on error - we want to collect all issues
# set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CERT_DIR="$PROJECT_DIR/certs"
NGINX_DIR="$PROJECT_DIR/nginx"

# Parse arguments
FIX_MODE=false
if [[ "$1" == "--fix" ]]; then
    FIX_MODE=true
fi

# Counters
ERRORS=0
WARNINGS=0
FIXED=0

# =============================================================================
# Helper Functions
# =============================================================================

log_ok() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
    ((WARNINGS++))
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    ((ERRORS++))
}

log_fix() {
    echo -e "${BLUE}[→]${NC} $1"
    ((FIXED++))
}

log_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

check_writable() {
    local path="$1"
    local parent_dir
    
    if [ -e "$path" ]; then
        # File/dir exists - check if writable
        if [ -w "$path" ]; then
            return 0
        else
            return 1
        fi
    else
        # Doesn't exist - check if parent is writable
        parent_dir="$(dirname "$path")"
        if [ -w "$parent_dir" ]; then
            return 0
        else
            return 1
        fi
    fi
}

# =============================================================================
# Checks
# =============================================================================

echo ""
echo "=========================================="
echo "Django Auth Stack - Pre-flight Checks"
echo "=========================================="
echo ""
echo "Project directory: $PROJECT_DIR"
echo "Fix mode: $FIX_MODE"
echo ""

# -----------------------------------------------------------------------------
# Check 1: .env file
# -----------------------------------------------------------------------------
echo "--- Environment ---"

if [ -f "$PROJECT_DIR/.env" ]; then
    log_ok ".env file exists"
    
    # Check for placeholder values
    if grep -q "CHANGE_ME\|REPLACE_WITH" "$PROJECT_DIR/.env" 2>/dev/null; then
        log_warn ".env contains placeholder values that need to be replaced"
        log_info "  Run: ./scripts/configure-env.sh to update configuration"
    fi
else
    log_error ".env file missing"
    if $FIX_MODE && [ -f "$PROJECT_DIR/.env.example" ]; then
        log_fix "Run: ./scripts/configure-env.sh"
    else
        log_info "  Run: ./scripts/configure-env.sh to create configuration"
    fi
fi

# -----------------------------------------------------------------------------
# Check 2: Certificate directory and files
# -----------------------------------------------------------------------------
echo ""
echo "--- TLS Certificates ---"

# Check if certs directory exists and is writable
if [ -d "$CERT_DIR" ]; then
    if [ -w "$CERT_DIR" ]; then
        log_ok "certs/ directory exists and is writable"
    else
        log_error "certs/ directory exists but is NOT writable (likely root-owned)"
        log_info "  This happens when Docker creates the mount point before files exist"
        if $FIX_MODE; then
            log_fix "Attempting to fix permissions..."
            if sudo chown -R "$(id -u):$(id -g)" "$CERT_DIR" 2>/dev/null; then
                log_ok "Fixed certs/ permissions"
                ((ERRORS--))
            else
                log_error "Could not fix permissions. Run: sudo chown -R \$(id -u):\$(id -g) $CERT_DIR"
            fi
        else
            log_info "  Run with --fix to attempt repair, or manually run:"
            log_info "  sudo chown -R \$(id -u):\$(id -g) $CERT_DIR"
        fi
    fi
else
    log_warn "certs/ directory does not exist (will be created)"
    if $FIX_MODE; then
        mkdir -p "$CERT_DIR"
        log_fix "Created certs/ directory"
    fi
fi

# Check for certificate files
if [ -f "$CERT_DIR/fullchain.pem" ] && [ -f "$CERT_DIR/privkey.pem" ]; then
    log_ok "TLS certificates found (fullchain.pem, privkey.pem)"
    
    # Check certificate validity
    if command -v openssl &> /dev/null; then
        expiry=$(openssl x509 -enddate -noout -in "$CERT_DIR/fullchain.pem" 2>/dev/null | cut -d= -f2)
        if [ -n "$expiry" ]; then
            expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry" +%s 2>/dev/null)
            now_epoch=$(date +%s)
            days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
            
            if [ "$days_left" -lt 0 ]; then
                log_error "Certificate has EXPIRED!"
            elif [ "$days_left" -lt 30 ]; then
                log_warn "Certificate expires in $days_left days"
            else
                log_ok "Certificate valid for $days_left days"
            fi
        fi
    fi
else
    log_error "TLS certificates missing (fullchain.pem and/or privkey.pem)"
    log_info "  Generate self-signed: ./scripts/init-selfsigned.sh"
    log_info "  Or use Let's Encrypt: ./scripts/init-letsencrypt.sh"
    log_info "  Or place your own certificates in certs/"
fi

# -----------------------------------------------------------------------------
# Check 3: DH Parameters
# -----------------------------------------------------------------------------
echo ""
echo "--- DH Parameters ---"

# Check both locations (nginx/dhparam.pem is legacy, certs/dhparam.pem is new)
DHPARAM_FOUND=false
DHPARAM_PATH=""

if [ -f "$CERT_DIR/dhparam.pem" ]; then
    DHPARAM_FOUND=true
    DHPARAM_PATH="$CERT_DIR/dhparam.pem"
    log_ok "DH parameters found: certs/dhparam.pem"
elif [ -f "$NGINX_DIR/dhparam.pem" ]; then
    DHPARAM_FOUND=true
    DHPARAM_PATH="$NGINX_DIR/dhparam.pem"
    log_ok "DH parameters found: nginx/dhparam.pem (legacy location)"
fi

if ! $DHPARAM_FOUND; then
    log_error "DH parameters missing"
    if $FIX_MODE; then
        log_fix "Generating DH parameters (2048-bit)... this may take a minute"
        if openssl dhparam -out "$CERT_DIR/dhparam.pem" 2048 2>/dev/null; then
            chmod 644 "$CERT_DIR/dhparam.pem"
            log_ok "Generated certs/dhparam.pem"
            ((ERRORS--))
        else
            log_error "Failed to generate DH parameters"
        fi
    else
        log_info "  Generate with: openssl dhparam -out certs/dhparam.pem 2048"
        log_info "  Or run with --fix to auto-generate"
    fi
fi

# -----------------------------------------------------------------------------
# Check 4: nginx directory writable (for entrypoint template processing)
# -----------------------------------------------------------------------------
echo ""
echo "--- nginx Configuration ---"

if [ -d "$NGINX_DIR/conf.d" ]; then
    if [ -w "$NGINX_DIR/conf.d" ]; then
        log_ok "nginx/conf.d/ is writable"
    else
        log_error "nginx/conf.d/ is NOT writable (template processing will fail)"
        if $FIX_MODE; then
            if sudo chown -R "$(id -u):$(id -g)" "$NGINX_DIR/conf.d" 2>/dev/null; then
                log_fix "Fixed nginx/conf.d/ permissions"
                ((ERRORS--))
            fi
        fi
    fi
else
    log_error "nginx/conf.d/ directory missing"
fi

# Check entrypoint script is executable
if [ -x "$NGINX_DIR/docker-entrypoint.sh" ]; then
    log_ok "docker-entrypoint.sh is executable"
else
    log_warn "docker-entrypoint.sh is not executable"
    if $FIX_MODE; then
        chmod +x "$NGINX_DIR/docker-entrypoint.sh"
        log_fix "Made docker-entrypoint.sh executable"
        ((WARNINGS--))
    fi
fi

# Check if docker-compose.override.yml exists (for service networks)
echo ""
echo "--- Compose Override ---"

if [ -f "$PROJECT_DIR/docker-compose.override.yml" ]; then
    log_ok "docker-compose.override.yml exists"
else
    # Check if services are configured
    if [ -f "$PROJECT_DIR/.env" ]; then
        set -a
        source "$PROJECT_DIR/.env"
        set +a
        
        has_services=false
        for i in $(seq 1 5); do
            name_var="SERVICE_${i}_NAME"
            eval name="\${$name_var:-}"
            [ -n "$name" ] && has_services=true && break
        done
        
        if $has_services; then
            log_warn "docker-compose.override.yml missing but services are configured"
            if $FIX_MODE; then
                if [ -x "$PROJECT_DIR/scripts/generate-compose-override.sh" ]; then
                    log_fix "Generating docker-compose.override.yml..."
                    "$PROJECT_DIR/scripts/generate-compose-override.sh"
                    ((WARNINGS--))
                else
                    log_info "  Run: ./scripts/generate-compose-override.sh"
                fi
            else
                log_info "  Run: ./scripts/generate-compose-override.sh"
            fi
        else
            log_info "No services configured - docker-compose.override.yml not needed"
        fi
    else
        log_info "No .env file - cannot check service configuration"
    fi
fi

# -----------------------------------------------------------------------------
# Check 5: Docker daemon and networks
# -----------------------------------------------------------------------------
echo ""
echo "--- Docker ---"

# Check if docker command exists
if ! command -v docker &>/dev/null; then
    log_error "Docker is not installed"
    log_info "  Install Docker: https://docs.docker.com/get-docker/"
    DOCKER_AVAILABLE=false
else
    # Check if docker daemon is accessible
    if docker info &>/dev/null 2>&1; then
        log_ok "Docker daemon is running and accessible"
        DOCKER_AVAILABLE=true
    else
        # Docker command exists but daemon not accessible - likely needs sudo
        log_error "Docker daemon is not accessible (may require sudo)"
        log_info "  Docker is installed but requires elevated privileges"
        log_info ""
        log_info "  Option 1: Run this script with sudo to check Docker networks:"
        log_info "    sudo ./scripts/preflight-check.sh"
        log_info ""
        log_info "  Option 2: Add your user to the docker group (requires re-login):"
        log_info "    sudo usermod -aG docker \$USER"
        log_info "    newgrp docker  # or logout and login again"
        log_info ""
        log_info "  Option 3: Manually check networks with sudo:"
        log_info "    sudo docker network ls | grep <service>_backend"
        log_info "    sudo docker network create <service>_backend"
        log_info ""
        log_info "  Note: When running docker compose, you'll need to use:"
        log_info "    sudo docker compose up -d"
        
        DOCKER_AVAILABLE=false
    fi
fi

# -----------------------------------------------------------------------------
# Check 6: External Docker networks (only if Docker is accessible)
# -----------------------------------------------------------------------------
if [ "$DOCKER_AVAILABLE" = true ]; then
    echo ""
    echo "--- Docker Networks ---"
    
    # Source .env to get SERVICE_* variables
    if [ -f "$PROJECT_DIR/.env" ]; then
        set -a
        source "$PROJECT_DIR/.env"
        set +a
    fi
    
    check_network() {
        local network=$1
        if docker network inspect "$network" &>/dev/null; then
            log_ok "Network '$network' exists"
            return 0
        else
            log_error "Network '$network' does not exist"
            if $FIX_MODE; then
                if docker network create "$network" &>/dev/null; then
                    log_fix "Created network '$network'"
                    ((ERRORS--))
                else
                    log_error "Failed to create network '$network'"
                fi
            else
                log_info "  Create with: docker network create $network"
                if [ "$(id -u)" -ne 0 ] && ! docker info &>/dev/null 2>&1; then
                    log_info "  (or with sudo: sudo docker network create $network)"
                fi
            fi
            return 1
        fi
    }
    
    # Check networks for all enabled services
    networks_checked=0
    for i in $(seq 1 99); do
        name_var="SERVICE_${i}_NAME"
        enabled_var="SERVICE_${i}_ENABLED"
        network_var="SERVICE_${i}_NETWORK"
        
        eval name="\${$name_var:-}"
        eval enabled="\${$enabled_var:-true}"
        eval network="\${$network_var:-}"
        
        # Stop if no more services defined
        [ -z "$name" ] && break
        
        # Skip disabled services
        [ "$enabled" != "true" ] && continue
        
        # Check network if defined
        if [ -n "$network" ]; then
            check_network "$network"
            networks_checked=$((networks_checked + 1))
        fi
    done
    
    if [ $networks_checked -eq 0 ]; then
        log_warn "No services configured in .env"
        log_info "  Run: ./scripts/configure-env.sh to add services"
    fi
else
    echo ""
    echo "--- Docker Networks ---"
    log_warn "Skipping network checks (Docker not accessible)"
    log_info "  Once Docker is accessible, verify networks exist:"
    log_info "    docker network ls | grep <service>_backend"
fi

# -----------------------------------------------------------------------------
# Check 7: Keycloak Admin Security (Production Recommendation)
# -----------------------------------------------------------------------------
echo ""
echo "--- Security ---"

# Source .env if not already done
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

# Check if admin IP restriction is configured
# Note: Empty value is valid (means no restriction)
if [ -n "${KEYCLOAK_ADMIN_ALLOWED_IPS:-}" ]; then
    log_ok "Admin console IP restriction configured"
    log_info "  Allowed: $KEYCLOAK_ADMIN_ALLOWED_IPS"
else
    # KEYCLOAK_ADMIN_ALLOWED_IPS is empty or not set
    # Empty value is valid - means no IP restriction (but still requires auth)
    # Check if this looks like a production domain (not .local)
    if [ -n "${DOMAIN_AUTH:-}" ]; then
        if [[ "$DOMAIN_AUTH" != *.local && "$DOMAIN_AUTH" != *localhost* ]]; then
            log_warn "KEYCLOAK_ADMIN_ALLOWED_IPS is empty or not set (public domain detected)"
            log_info "  For production servers, it's recommended to restrict admin access to trusted IPs."
            log_info "  Run: ./scripts/configure-env.sh to configure IP restrictions"
            log_info "  Or manually set KEYCLOAK_ADMIN_ALLOWED_IPS in .env (space-separated IPs/CIDRs)"
        else
            log_ok "Admin console accessible from any IP (development domain, no IP restriction)"
        fi
    else
        log_ok "Admin console accessible from any IP (no IP restriction configured)"
    fi
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
    echo ""
    echo "You can now start the stack:"
    echo "  docker compose up -d"
    exit 0
else
    echo -e "${RED}$ERRORS error(s)${NC}, ${YELLOW}$WARNINGS warning(s)${NC}"
    
    if $FIX_MODE; then
        echo -e "${BLUE}$FIXED issue(s) fixed${NC}"
    fi
    
    if [ $ERRORS -gt 0 ]; then
        echo ""
        echo "Please fix the errors above before starting the stack."
        if ! $FIX_MODE; then
            echo "Run with --fix to auto-fix some issues:"
            echo "  ./scripts/preflight-check.sh --fix"
        fi
        exit 1
    fi
fi
