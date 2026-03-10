#!/bin/bash
# =============================================================================
# Environment Configuration Script
# =============================================================================
# Copyright (C) 2024-2026 David Kleinhans, Jade University of Applied Sciences
# SPDX-License-Identifier: Apache-2.0
# =============================================================================
# This script configures the .env file for the Django Auth Stack.
# It handles both initial setup AND reconfiguration of existing environments.
#
# Features:
# - Initial setup: Generates new .env with secure random secrets
# - Reconfiguration: Loads existing values, preserves secrets by default
# - Generates clean .env file with consistent structure
# - Backs up existing configuration before overwriting
# - Smart service management (add, edit, enable/disable)
#
# Usage:
#   ./scripts/configure-env.sh         # Interactive configuration
#   ./scripts/configure-env.sh --help  # Show help
#
# The script generates a fresh .env file based on .env.example structure,
# populated with configured values. Old .env is backed up before replacement.
# =============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
ENV_EXAMPLE="$PROJECT_DIR/.env.example"
ENV_TEMP="$PROJECT_DIR/.env.tmp.$$"  # Temp file with PID for uniqueness

# Cleanup temp file on exit
cleanup() {
    rm -f "$ENV_TEMP"
}
trap cleanup EXIT

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
    # Generate a secure random password (32 characters, alphanumeric)
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Read a value from existing .env file
get_existing_value() {
    local key="$1"
    local default="$2"
    if [ -n "${EXISTING_ENV[$key]:-}" ]; then
        echo "${EXISTING_ENV[$key]}"
    else
        echo "$default"
    fi
}

# Prompt with existing value as default
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local result
    
    if [ -n "$default" ]; then
        read -p "$prompt [$default]: " result
        result="${result:-$default}"
    else
        read -p "$prompt: " result
    fi
    echo "$result"
}

# macOS vs Linux sed compatibility
if [[ "$OSTYPE" == "darwin"* ]]; then
    SED_INPLACE="sed -i ''"
else
    SED_INPLACE="sed -i"
fi

show_help() {
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Configure the .env file for Django Auth Stack."
    echo ""
    echo "Options:"
    echo "  --help    Show this help message"
    echo ""
    echo "If .env exists, the script will:"
    echo "  - Load existing values as defaults"
    echo "  - Preserve secrets unless explicitly regenerated"
    echo "  - Allow editing of services"
    echo "  - Create a backup before saving changes"
    echo ""
    echo "If .env does not exist, the script will:"
    echo "  - Generate new secure secrets"
    echo "  - Guide you through initial configuration"
    echo ""
    exit 0
}

# =============================================================================
# Parse Arguments
# =============================================================================

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
fi

# =============================================================================
# Main Script
# =============================================================================

echo ""
echo -e "${BOLD}=========================================="
echo "Django Auth Stack - Configuration"
echo -e "==========================================${NC}"
echo ""

# Check if .env.example exists
if [ ! -f "$ENV_EXAMPLE" ]; then
    log_error ".env.example not found! Cannot proceed."
    exit 1
fi

# =============================================================================
# Detect Existing Configuration
# =============================================================================

declare -A EXISTING_ENV
declare -a EXISTING_SERVICES
IS_RECONFIGURE=false

if [ -f "$ENV_FILE" ]; then
    IS_RECONFIGURE=true
    log_info "Existing configuration found: .env"
    log_info "Current settings will be used as defaults."
    echo ""
    
    # Parse existing .env file into associative array
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        # Remove leading/trailing whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        # Remove quotes from value if present
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"
        EXISTING_ENV["$key"]="$value"
    done < "$ENV_FILE"
    
    # Find existing services
    for i in $(seq 1 99); do
        name="${EXISTING_ENV[SERVICE_${i}_NAME]:-}"
        [ -z "$name" ] && break
        EXISTING_SERVICES+=("$i")
    done
    
    log_info "Found ${#EXISTING_SERVICES[@]} configured service(s)"
else
    log_info "No existing configuration found. Starting fresh setup."
fi

echo ""

# =============================================================================
# Secret Management
# =============================================================================

log_step "=========================================="
log_step "Secret Configuration"
log_step "=========================================="
echo ""

if $IS_RECONFIGURE; then
    # Existing config - ask about secret regeneration (two-step confirmation)
    log_info "Your current secrets will be preserved by default."
    echo ""
    read -p "Do you want to regenerate secrets? (y/N): " regen_ask
    
    if [[ "$regen_ask" =~ ^[Yy]$ ]]; then
        # Second step: serious warning and explicit confirmation
        echo ""
        log_warn "========================================"
        log_warn "WARNING: DESTRUCTIVE OPERATION"
        log_warn "========================================"
        log_warn "Regenerating secrets will:"
        log_warn "  - Change POSTGRES_PASSWORD (database access lost)"
        log_warn "  - Change KEYCLOAK_ADMIN_PASSWORD (admin login changed)"
        log_warn "  - Change OAUTH2_PROXY_COOKIE_SECRET (all sessions invalidated)"
        echo ""
        log_warn "You will need to RESET the Keycloak database to recover!"
        log_warn "This typically means deleting the postgres volume and starting fresh."
        echo ""
        read -p "Type YES in capitals to confirm regeneration: " regen_confirm
        
        if [ "$regen_confirm" == "YES" ]; then
            log_warn "Regenerating all secrets..."
            POSTGRES_PASSWORD=$(generate_password)
            KEYCLOAK_ADMIN_PASSWORD=$(generate_password)
            OAUTH2_COOKIE_SECRET=$(openssl rand -base64 32 | head -c 32)
            log_info "Generated new POSTGRES_PASSWORD"
            log_info "Generated new KEYCLOAK_ADMIN_PASSWORD"
            log_info "Generated new OAUTH2_PROXY_COOKIE_SECRET"
            echo ""
            log_warn "REMINDER: You must reset your Keycloak database!"
            log_warn "  docker compose down -v  # removes volumes"
            log_warn "  docker compose up -d    # fresh start"
        else
            log_info "Regeneration cancelled. Keeping existing secrets."
            POSTGRES_PASSWORD=$(get_existing_value "POSTGRES_PASSWORD" "")
            KEYCLOAK_ADMIN_PASSWORD=$(get_existing_value "KEYCLOAK_ADMIN_PASSWORD" "")
            OAUTH2_COOKIE_SECRET=$(get_existing_value "OAUTH2_PROXY_COOKIE_SECRET" "")
        fi
    else
        log_info "Keeping existing secrets."
        POSTGRES_PASSWORD=$(get_existing_value "POSTGRES_PASSWORD" "")
        KEYCLOAK_ADMIN_PASSWORD=$(get_existing_value "KEYCLOAK_ADMIN_PASSWORD" "")
        OAUTH2_COOKIE_SECRET=$(get_existing_value "OAUTH2_PROXY_COOKIE_SECRET" "")
    fi
    
    # Check for missing or placeholder secrets (always generate these)
    if [ -z "$POSTGRES_PASSWORD" ] || [[ "$POSTGRES_PASSWORD" == *"CHANGE_ME"* ]]; then
        POSTGRES_PASSWORD=$(generate_password)
        log_info "Generated missing POSTGRES_PASSWORD"
    fi
    if [ -z "$KEYCLOAK_ADMIN_PASSWORD" ] || [[ "$KEYCLOAK_ADMIN_PASSWORD" == *"CHANGE_ME"* ]]; then
        KEYCLOAK_ADMIN_PASSWORD=$(generate_password)
        log_info "Generated missing KEYCLOAK_ADMIN_PASSWORD"
    fi
    if [ -z "$OAUTH2_COOKIE_SECRET" ] || [[ "$OAUTH2_COOKIE_SECRET" == *"REPLACE_WITH"* ]]; then
        OAUTH2_COOKIE_SECRET=$(openssl rand -base64 32 | head -c 32)
        log_info "Generated missing OAUTH2_PROXY_COOKIE_SECRET"
    fi
else
    # Fresh setup - generate all secrets
    log_info "Generating secure random secrets..."
    POSTGRES_PASSWORD=$(generate_password)
    KEYCLOAK_ADMIN_PASSWORD=$(generate_password)
    OAUTH2_COOKIE_SECRET=$(openssl rand -base64 32 | head -c 32)
    log_info "Generated POSTGRES_PASSWORD (32 chars)"
    log_info "Generated KEYCLOAK_ADMIN_PASSWORD (32 chars)"
    log_info "Generated OAUTH2_PROXY_COOKIE_SECRET (32 chars)"
fi

# =============================================================================
# System-Side Configuration (from .env.example, no user interaction)
# =============================================================================
# These values must match the docker-compose.yml and system configuration.
# They are taken from .env.example and not user-configurable via this script.

KEYCLOAK_VERSION="23.0"
OAUTH2_PROXY_VERSION="v7.6.0"

# =============================================================================
# User-Specific Configuration (preserve existing, no interaction)
# =============================================================================
# These settings may have been customized by the user. Preserve them silently.

# Keycloak admin username
KEYCLOAK_ADMIN=$(get_existing_value "KEYCLOAK_ADMIN" "admin")

# Log level - preserve user customization
KEYCLOAK_LOG_LEVEL=$(get_existing_value "KEYCLOAK_LOG_LEVEL" "info")
if $IS_RECONFIGURE; then
    existing_log=$(get_existing_value "KEYCLOAK_LOG_LEVEL" "")
    if [ -n "$existing_log" ] && [ "$existing_log" != "info" ]; then
        log_info "Preserving custom KEYCLOAK_LOG_LEVEL: $existing_log"
    fi
fi

# OAuth2 Proxy Client ID
OAUTH2_PROXY_CLIENT_ID=$(get_existing_value "OAUTH2_PROXY_CLIENT_ID" "oauth2-proxy")

# Nginx settings - preserve user customization
CLIENT_MAX_BODY_SIZE=$(get_existing_value "CLIENT_MAX_BODY_SIZE" "50M")
PROXY_CONNECT_TIMEOUT=$(get_existing_value "PROXY_CONNECT_TIMEOUT" "60s")
PROXY_SEND_TIMEOUT=$(get_existing_value "PROXY_SEND_TIMEOUT" "60s")
PROXY_READ_TIMEOUT=$(get_existing_value "PROXY_READ_TIMEOUT" "60s")

if $IS_RECONFIGURE; then
    # Check for custom nginx settings and inform user
    custom_settings=""
    [ "$(get_existing_value "CLIENT_MAX_BODY_SIZE" "")" != "50M" ] && [ -n "$(get_existing_value "CLIENT_MAX_BODY_SIZE" "")" ] && custom_settings="$custom_settings CLIENT_MAX_BODY_SIZE"
    [ "$(get_existing_value "PROXY_CONNECT_TIMEOUT" "")" != "60s" ] && [ -n "$(get_existing_value "PROXY_CONNECT_TIMEOUT" "")" ] && custom_settings="$custom_settings PROXY_CONNECT_TIMEOUT"
    [ "$(get_existing_value "PROXY_SEND_TIMEOUT" "")" != "60s" ] && [ -n "$(get_existing_value "PROXY_SEND_TIMEOUT" "")" ] && custom_settings="$custom_settings PROXY_SEND_TIMEOUT"
    [ "$(get_existing_value "PROXY_READ_TIMEOUT" "")" != "60s" ] && [ -n "$(get_existing_value "PROXY_READ_TIMEOUT" "")" ] && custom_settings="$custom_settings PROXY_READ_TIMEOUT"
    if [ -n "$custom_settings" ]; then
        log_info "Preserving custom nginx settings:$custom_settings"
    fi
fi

# =============================================================================
# Keycloak Realm Configuration
# =============================================================================

echo ""
log_step "=========================================="
log_step "Keycloak Realm"
log_step "=========================================="
echo ""

default_realm=$(get_existing_value "KEYCLOAK_REALM" "jade")
log_info "The realm name is used for your applications' authentication."
KEYCLOAK_REALM=$(prompt_with_default "Keycloak realm name" "$default_realm")

# =============================================================================
# Keycloak Admin Security
# =============================================================================

echo ""
log_step "=========================================="
log_step "Keycloak Admin Console Security"
log_step "=========================================="
echo ""

default_admin_ips=$(get_existing_value "KEYCLOAK_ADMIN_ALLOWED_IPS" "")
log_info "Optionally restrict admin console access to specific IPs/networks."
log_warn "For PUBLIC servers, IP restriction is STRONGLY recommended!"
echo ""
log_info "Format: Space-separated IPs/CIDRs (NOT comma-separated)"
log_info "Examples: 203.0.113.0/24 10.8.0.0/24 127.0.0.1"
log_info "Leave empty for no restriction (any IP, still requires authentication)"
echo ""
KEYCLOAK_ADMIN_ALLOWED_IPS=$(prompt_with_default "Allowed IPs for admin (space-separated, Enter for no restriction)" "$default_admin_ips")

# =============================================================================
# OAuth2 Proxy Client Secret
# =============================================================================
# Only prompt if the secret is still a placeholder (needs to be obtained from Keycloak)

OAUTH2_PROXY_CLIENT_SECRET=$(get_existing_value "OAUTH2_PROXY_CLIENT_SECRET" "REPLACE_WITH_KEYCLOAK_CLIENT_SECRET")

if [[ "$OAUTH2_PROXY_CLIENT_SECRET" == *"REPLACE_WITH"* ]] || [ -z "$OAUTH2_PROXY_CLIENT_SECRET" ]; then
    echo ""
    log_step "=========================================="
    log_step "OAuth2 Proxy Client Secret"
    log_step "=========================================="
    echo ""
    log_info "The OAuth2 client secret must be obtained from Keycloak after setup."
    log_info "Get it from: Clients → oauth2-proxy → Credentials"
    echo ""
    OAUTH2_PROXY_CLIENT_SECRET=$(prompt_with_default "OAuth2 Proxy Client Secret (Enter to skip for now)" "$OAUTH2_PROXY_CLIENT_SECRET")
fi

# =============================================================================
# Domain Configuration
# =============================================================================

echo ""
log_step "=========================================="
log_step "Domain Configuration"
log_step "=========================================="
echo ""

log_info "For development: use .local domains (e.g., auth.example.local)"
log_info "For production: use actual domains (e.g., auth.example.com)"
echo ""

default_domain_auth=$(get_existing_value "DOMAIN_AUTH" "auth.example.local")
DOMAIN_AUTH=$(prompt_with_default "Auth domain (Keycloak)" "$default_domain_auth")

# Calculate default cookie domain from auth domain
calculated_cookie_domain=".${DOMAIN_AUTH#*.}"
default_cookie_domain=$(get_existing_value "OAUTH2_PROXY_COOKIE_DOMAIN" "$calculated_cookie_domain")
OAUTH2_PROXY_COOKIE_DOMAIN=$(prompt_with_default "Cookie domain for SSO" "$default_cookie_domain")

# =============================================================================
# Let's Encrypt Configuration
# =============================================================================

echo ""
log_step "=========================================="
log_step "TLS/Let's Encrypt Configuration"
log_step "=========================================="
echo ""

default_le_enabled=$(get_existing_value "LETSENCRYPT_ENABLED" "false")
log_info "Let's Encrypt provides free, automated TLS certificates."
log_info "Requires: public DNS pointing to this server, port 80 open."
log_info "For development/internal use, choose 'false' (self-signed certs)."
echo ""
LETSENCRYPT_ENABLED=$(prompt_with_default "Enable Let's Encrypt? (true/false)" "$default_le_enabled")

default_le_email=$(get_existing_value "LETSENCRYPT_EMAIL" "admin@example.com")
if [ "$LETSENCRYPT_ENABLED" = "true" ]; then
    LETSENCRYPT_EMAIL=$(prompt_with_default "Email for Let's Encrypt notifications" "$default_le_email")
else
    LETSENCRYPT_EMAIL="$default_le_email"
fi

# =============================================================================
# Service Configuration
# =============================================================================

echo ""
log_step "=========================================="
log_step "Upstream Service Configuration"
log_step "=========================================="
echo ""

log_info "Configure services to protect with Keycloak authentication."
echo ""
log_info "Authentication Patterns:"
log_info "  Pattern A: Django-controlled auth (public + protected pages)"
log_info "  Pattern B: Full nginx-level auth (everything protected)"
echo ""

# Array to store final service configurations
declare -a SERVICES_CONFIG

# Process existing services first (if reconfiguring)
if $IS_RECONFIGURE && [ ${#EXISTING_SERVICES[@]} -gt 0 ]; then
    log_info "--- Existing Services ---"
    echo ""
    
    for idx in "${EXISTING_SERVICES[@]}"; do
        svc_name="${EXISTING_ENV[SERVICE_${idx}_NAME]}"
        svc_enabled="${EXISTING_ENV[SERVICE_${idx}_ENABLED]:-true}"
        svc_pattern="${EXISTING_ENV[SERVICE_${idx}_PATTERN]:-A}"
        svc_domain="${EXISTING_ENV[SERVICE_${idx}_DOMAIN]:-}"
        svc_upstream="${EXISTING_ENV[SERVICE_${idx}_UPSTREAM]:-}"
        svc_network="${EXISTING_ENV[SERVICE_${idx}_NETWORK]:-}"
        
        echo ""
        log_service "Service: ${svc_name}"
        echo "  Domain:   $svc_domain"
        echo "  Upstream: $svc_upstream"
        echo "  Pattern:  $svc_pattern"
        echo "  Enabled:  $svc_enabled"
        echo ""
        
        # Show appropriate toggle option based on current state
        if [ "$svc_enabled" == "true" ]; then
            read -p "  Action: [K]eep / [E]dit / [D]isable / [R]emove? [K]: " action
        else
            read -p "  Action: [K]eep / [E]dit / [N]nable / [R]emove? [K]: " action
        fi
        action="${action:-K}"
        action=$(echo "$action" | tr '[:lower:]' '[:upper:]')
        
        case "$action" in
            K)
                # Keep as-is
                SERVICES_CONFIG+=("$svc_name|$svc_enabled|$svc_pattern|$svc_domain|$svc_upstream|$svc_network")
                log_info "  Keeping service: $svc_name"
                ;;
            E)
                # Edit service
                echo ""
                log_info "  Editing service: $svc_name"
                
                new_domain=$(prompt_with_default "    Domain" "$svc_domain")
                new_upstream=$(prompt_with_default "    Upstream" "$svc_upstream")
                new_network=$(prompt_with_default "    Network" "$svc_network")
                
                echo "    Pattern: A=Django-controlled, B=Full auth"
                new_pattern=$(prompt_with_default "    Pattern (A/B)" "$svc_pattern")
                new_pattern=$(echo "$new_pattern" | tr '[:lower:]' '[:upper:]')
                
                read -p "    Enable service? (Y/n): " new_enabled
                if [[ "$new_enabled" =~ ^[Nn]$ ]]; then
                    new_enabled="false"
                else
                    new_enabled="true"
                fi
                
                SERVICES_CONFIG+=("$svc_name|$new_enabled|$new_pattern|$new_domain|$new_upstream|$new_network")
                log_info "  Updated service: $svc_name"
                ;;
            D)
                # Disable (keep config but set enabled=false)
                SERVICES_CONFIG+=("$svc_name|false|$svc_pattern|$svc_domain|$svc_upstream|$svc_network")
                log_info "  Disabled service: $svc_name"
                ;;
            N)
                # Enable (keep config but set enabled=true)
                SERVICES_CONFIG+=("$svc_name|true|$svc_pattern|$svc_domain|$svc_upstream|$svc_network")
                log_info "  Enabled service: $svc_name"
                ;;
            R)
                # Remove - don't add to SERVICES_CONFIG
                log_warn "  Removed service: $svc_name"
                ;;
            *)
                # Default: keep
                SERVICES_CONFIG+=("$svc_name|$svc_enabled|$svc_pattern|$svc_domain|$svc_upstream|$svc_network")
                log_info "  Keeping service: $svc_name"
                ;;
        esac
    done
fi

# Add new services
echo ""
log_info "--- Add New Services ---"

while true; do
    echo ""
    read -p "Add a new service? (y/N): " add_service
    
    if [[ ! "$add_service" =~ ^[Yy]$ ]]; then
        break
    fi
    
    echo ""
    log_service "Configuring new service..."
    echo ""
    
    # Service name
    read -p "  Service name (e.g., itsm, myapp): " new_name
    if [ -z "$new_name" ]; then
        log_warn "  Service name required, skipping."
        continue
    fi
    # Sanitize name
    new_name=$(echo "$new_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]/_/g')
    
    # Check for duplicate
    duplicate=false
    for existing in "${SERVICES_CONFIG[@]}"; do
        existing_name=$(echo "$existing" | cut -d'|' -f1)
        if [ "$existing_name" == "$new_name" ]; then
            log_warn "  Service '$new_name' already exists!"
            duplicate=true
            break
        fi
    done
    $duplicate && continue
    
    # Domain
    default_new_domain="${new_name}${OAUTH2_PROXY_COOKIE_DOMAIN}"
    new_domain=$(prompt_with_default "  Domain" "$default_new_domain")
    
    # Upstream
    default_new_upstream="${new_name}_nginx:8000"
    new_upstream=$(prompt_with_default "  Upstream (container:port)" "$default_new_upstream")
    
    # Network
    default_new_network="${new_name}_backend"
    new_network=$(prompt_with_default "  Docker network" "$default_new_network")
    
    # Pattern
    echo ""
    echo "  Authentication pattern:"
    echo "    A = Django-controlled (recommended for Django apps)"
    echo "    B = Full nginx-level auth (for internal tools)"
    new_pattern=$(prompt_with_default "  Pattern (A/B)" "A")
    new_pattern=$(echo "$new_pattern" | tr '[:lower:]' '[:upper:]')
    
    # Enabled
    read -p "  Enable this service? (Y/n): " new_enabled
    if [[ "$new_enabled" =~ ^[Nn]$ ]]; then
        new_enabled="false"
    else
        new_enabled="true"
    fi
    
    SERVICES_CONFIG+=("$new_name|$new_enabled|$new_pattern|$new_domain|$new_upstream|$new_network")
    log_info "  Added service: $new_name"
done

# =============================================================================
# Generate New .env File
# =============================================================================

echo ""
log_step "=========================================="
log_step "Generating Configuration File"
log_step "=========================================="
echo ""

# Start with .env.example as template
cp "$ENV_EXAMPLE" "$ENV_TEMP"

# Function to set a value in the temp env file
set_env_value() {
    local key="$1"
    local value="$2"
    
    # Quote values that contain spaces so that bash 'source' works correctly.
    # Without quotes, bash treats 'KEY=a b' as a temp-env-var assignment + command
    # 'b', which fails silently and leaves KEY unset.
    # Docker Compose strips surrounding quotes from .env values, so quoting is
    # safe for both shell sourcing and Docker Compose consumption.
    local stored_value
    if [[ "$value" == *' '* ]]; then
        stored_value="\"${value}\""
    else
        stored_value="$value"
    fi
    
    # Escape special characters for sed (only in the stored/quoted form)
    local escaped_value=$(echo "$stored_value" | sed 's/[&/\]/\\&/g')
    
    # Try to replace existing key
    if grep -q "^${key}=" "$ENV_TEMP" 2>/dev/null; then
        $SED_INPLACE "s|^${key}=.*|${key}=${escaped_value}|g" "$ENV_TEMP"
    elif grep -q "^# ${key}=" "$ENV_TEMP" 2>/dev/null; then
        # Uncomment and set
        $SED_INPLACE "s|^# ${key}=.*|${key}=${escaped_value}|g" "$ENV_TEMP"
    else
        # Append if not found
        echo "${key}=${stored_value}" >> "$ENV_TEMP"
    fi
}

log_info "Setting configuration values..."

# Database
set_env_value "POSTGRES_PASSWORD" "$POSTGRES_PASSWORD"

# Keycloak
set_env_value "KEYCLOAK_VERSION" "$KEYCLOAK_VERSION"
set_env_value "KEYCLOAK_ADMIN" "$KEYCLOAK_ADMIN"
set_env_value "KEYCLOAK_ADMIN_PASSWORD" "$KEYCLOAK_ADMIN_PASSWORD"
set_env_value "KEYCLOAK_REALM" "$KEYCLOAK_REALM"
set_env_value "KEYCLOAK_LOG_LEVEL" "$KEYCLOAK_LOG_LEVEL"

# Admin security (always write, even if empty - empty means no restriction)
set_env_value "KEYCLOAK_ADMIN_ALLOWED_IPS" "$KEYCLOAK_ADMIN_ALLOWED_IPS"

# OAuth2 Proxy
set_env_value "OAUTH2_PROXY_CLIENT_ID" "$OAUTH2_PROXY_CLIENT_ID"
set_env_value "OAUTH2_PROXY_CLIENT_SECRET" "$OAUTH2_PROXY_CLIENT_SECRET"
set_env_value "OAUTH2_PROXY_COOKIE_SECRET" "$OAUTH2_COOKIE_SECRET"
set_env_value "OAUTH2_PROXY_COOKIE_DOMAIN" "$OAUTH2_PROXY_COOKIE_DOMAIN"
set_env_value "OAUTH2_PROXY_VERSION" "$OAUTH2_PROXY_VERSION"

# Domain
set_env_value "DOMAIN_AUTH" "$DOMAIN_AUTH"

# TLS
set_env_value "LETSENCRYPT_ENABLED" "$LETSENCRYPT_ENABLED"
set_env_value "LETSENCRYPT_EMAIL" "$LETSENCRYPT_EMAIL"

# Nginx
set_env_value "CLIENT_MAX_BODY_SIZE" "$CLIENT_MAX_BODY_SIZE"
set_env_value "PROXY_CONNECT_TIMEOUT" "$PROXY_CONNECT_TIMEOUT"
set_env_value "PROXY_SEND_TIMEOUT" "$PROXY_SEND_TIMEOUT"
set_env_value "PROXY_READ_TIMEOUT" "$PROXY_READ_TIMEOUT"

# Remove example service placeholders
$SED_INPLACE '/^# --- Example Service/d' "$ENV_TEMP"
$SED_INPLACE '/^# SERVICE_1_/d' "$ENV_TEMP"
$SED_INPLACE '/^# SERVICE_2_/d' "$ENV_TEMP"
$SED_INPLACE '/^# SERVICE_3_/d' "$ENV_TEMP"

# Add configured services
if [ ${#SERVICES_CONFIG[@]} -gt 0 ]; then
    echo "" >> "$ENV_TEMP"
    echo "# =============================================================================" >> "$ENV_TEMP"
    echo "# CONFIGURED SERVICES" >> "$ENV_TEMP"
    echo "# =============================================================================" >> "$ENV_TEMP"
    
    svc_num=0
    for svc_config in "${SERVICES_CONFIG[@]}"; do
        svc_num=$((svc_num + 1))
        
        IFS='|' read -r name enabled pattern domain upstream network <<< "$svc_config"
        
        echo "" >> "$ENV_TEMP"
        echo "# --- Service ${svc_num}: ${name} ---" >> "$ENV_TEMP"
        echo "SERVICE_${svc_num}_NAME=${name}" >> "$ENV_TEMP"
        echo "SERVICE_${svc_num}_ENABLED=${enabled}" >> "$ENV_TEMP"
        echo "SERVICE_${svc_num}_PATTERN=${pattern}" >> "$ENV_TEMP"
        echo "SERVICE_${svc_num}_DOMAIN=${domain}" >> "$ENV_TEMP"
        echo "SERVICE_${svc_num}_UPSTREAM=${upstream}" >> "$ENV_TEMP"
        echo "SERVICE_${svc_num}_NETWORK=${network}" >> "$ENV_TEMP"
    done
fi

log_info "Configuration file generated."

# =============================================================================
# Finalize: Backup and Replace
# =============================================================================

echo ""
log_step "=========================================="
log_step "Saving Configuration"
log_step "=========================================="
echo ""

if [ -f "$ENV_FILE" ]; then
    backup_file="$PROJECT_DIR/.env.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$ENV_FILE" "$backup_file"
    log_info "Backed up existing .env to: $(basename "$backup_file")"
fi

mv "$ENV_TEMP" "$ENV_FILE"
log_info "Saved new configuration to: .env"

# =============================================================================
# Completion
# =============================================================================

echo ""
log_info "=========================================="
log_info "Configuration Complete!"
log_info "=========================================="
echo ""
log_info "Created: .env"
if [ ${#SERVICES_CONFIG[@]} -gt 0 ]; then
    log_info "Configured ${#SERVICES_CONFIG[@]} service(s)"
fi
echo ""
log_warn "IMPORTANT: Keep .env file secure - it contains sensitive credentials!"
echo ""
log_info "========================================"
log_info "Next Steps:"
log_info "========================================"
echo ""
log_info "1. Run pre-flight check to verify configuration:"
log_info "     ./scripts/preflight-check.sh"
echo ""
# -------------------------------------------------------------------------
# Auto-generate docker-compose.override.yml
# -------------------------------------------------------------------------
if [ ${#SERVICES_CONFIG[@]} -gt 0 ] || [ "$LETSENCRYPT_ENABLED" = "true" ]; then
    log_info "Generating docker-compose.override.yml..."
    echo ""
    OVERRIDE_SCRIPT="$SCRIPT_DIR/generate-compose-override.sh"
    if [ -f "$OVERRIDE_SCRIPT" ]; then
        bash "$OVERRIDE_SCRIPT"
    else
        log_warn "generate-compose-override.sh not found — run it manually:"
        log_warn "  ./scripts/generate-compose-override.sh"
    fi
    echo ""
fi

if [ ${#SERVICES_CONFIG[@]} -gt 0 ]; then
    log_info "2. Create Docker networks for your services (if not already created):"
    svc_num=0
    for svc_config in "${SERVICES_CONFIG[@]}"; do
        svc_num=$((svc_num + 1))
        network=$(echo "$svc_config" | cut -d'|' -f6)
        log_info "     docker network create ${network}"
    done
    echo ""
    if [ "$LETSENCRYPT_ENABLED" = "true" ]; then
        log_info "3. Obtain initial Let's Encrypt certificates:"
        log_info "     ./scripts/init-letsencrypt.sh"
        echo ""
        log_info "4. Start the stack:"
    else
        log_info "3. Start the stack:"
    fi
else
    log_info "2. Start the stack:"
fi
log_info "     docker compose up -d"
echo ""
log_info "Access Keycloak admin console:"
log_info "     https://${DOMAIN_AUTH}"
log_info "     Username: ${KEYCLOAK_ADMIN}"
log_info "     Password: <see .env file>"
echo ""

if [[ "$OAUTH2_PROXY_CLIENT_SECRET" == *"REPLACE_WITH"* ]]; then
    log_warn "========================================"
    log_warn "MANUAL STEP REQUIRED:"
    log_warn "========================================"
    echo ""
    log_warn "After Keycloak is running, you MUST:"
    log_warn "1. Create an OIDC client named '$OAUTH2_PROXY_CLIENT_ID'"
    log_warn "2. Get the client secret from: Clients → Credentials"
    log_warn "3. Run this script again to update OAUTH2_PROXY_CLIENT_SECRET"
    log_warn "   Or edit .env directly and restart oauth2-proxy"
    echo ""
fi

log_info "For detailed instructions, see: README.md"
echo ""

exit 0
