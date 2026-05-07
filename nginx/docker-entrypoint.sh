#!/bin/sh

# =============================================================================
# Nginx Entrypoint Script - Dynamic Service Configuration
# =============================================================================
# Copyright (C) 2024-2026 David Kleinhans, Jade University of Applied Sciences
# SPDX-License-Identifier: Apache-2.0
# =============================================================================
# This script runs before nginx starts and:
#   1. Processes static templates (keycloak.conf)
#   2. Dynamically generates service configs from SERVICE_* environment variables
#
# Service Configuration Format (in .env):
#   SERVICE_1_NAME=myapp
#   SERVICE_1_ENABLED=true
#   SERVICE_1_PATTERN=A          # A=Django-controlled, B=Full auth
#   SERVICE_1_DOMAIN=myapp.example.local
#   SERVICE_1_UPSTREAM=myapp_nginx:8000
#   SERVICE_1_NETWORK=myapp_backend
#
# Templates:
#   - keycloak.conf.template: Static Keycloak/auth domain config
#   - service-pattern-a.conf.template: Django-controlled auth pattern
#   - service-pattern-b.conf.template: Full nginx-level auth pattern
# =============================================================================

set -e

CONF_DIR="/etc/nginx/conf.d"
TEMPLATE_DIR="/etc/nginx/conf.d"

echo "[nginx-entrypoint] Starting dynamic configuration..."

# =============================================================================
# Step 1: Process static Keycloak template
# =============================================================================
echo "[nginx-entrypoint] Processing Keycloak template..."

# --- Build IP restriction rules for Keycloak admin console ---
# If KEYCLOAK_ADMIN_ALLOWED_IPS is set, generate allow/deny rules
# Format: Space-separated CIDR blocks (NOT comma-separated)
#   Example: "10.0.0.0/8 192.168.1.0/24 127.0.0.1"
KEYCLOAK_ADMIN_IP_RULES=""
if [ -n "${KEYCLOAK_ADMIN_ALLOWED_IPS:-}" ]; then
    echo "[nginx-entrypoint] Configuring Keycloak admin IP restriction..."
    # Build allow rules for each IP/CIDR
    for ip in $KEYCLOAK_ADMIN_ALLOWED_IPS; do
        KEYCLOAK_ADMIN_IP_RULES="${KEYCLOAK_ADMIN_IP_RULES}allow ${ip}; "
        echo "[nginx-entrypoint]   Allowing: $ip"
    done
    # Add deny all after allows
    KEYCLOAK_ADMIN_IP_RULES="${KEYCLOAK_ADMIN_IP_RULES}deny all;"
    echo "[nginx-entrypoint] Admin access restricted to specified IPs"
else
    # No restriction - allow all (comment placeholder for clarity)
    KEYCLOAK_ADMIN_IP_RULES="# IP restriction disabled - accessible from any IP"
    echo "[nginx-entrypoint] Keycloak admin accessible from any IP (no restriction)"
fi
export KEYCLOAK_ADMIN_IP_RULES

if [ -f "$TEMPLATE_DIR/keycloak.conf.template" ]; then
    envsubst '${DOMAIN_AUTH} ${KEYCLOAK_REALM} ${OAUTH2_PROXY_COOKIE_DOMAIN} ${OAUTH2_PROXY_CLIENT_ID} ${KEYCLOAK_ADMIN_IP_RULES}' \
        < "$TEMPLATE_DIR/keycloak.conf.template" \
        > "$CONF_DIR/keycloak.conf"
    echo "[nginx-entrypoint] Created: keycloak.conf"
else
    echo "[nginx-entrypoint] Warning: keycloak.conf.template not found"
fi

# =============================================================================
# Step 2: Clean up old generated service configs (not templates)
# =============================================================================
echo "[nginx-entrypoint] Cleaning up old service configs..."
for conf in "$CONF_DIR"/*.conf; do
    # Skip keycloak.conf (handled above)
    case "$(basename "$conf")" in
        keycloak.conf) continue ;;
    esac
    
    # Remove generated service configs (they'll be regenerated)
    if [ -f "$conf" ]; then
        rm -f "$conf"
        echo "[nginx-entrypoint] Removed: $(basename "$conf")"
    fi
done

# =============================================================================
# Step 3: Dynamically generate service configs from SERVICE_* env vars
# =============================================================================
echo "[nginx-entrypoint] Generating service configurations..."

# Find all SERVICE_N_NAME variables (N = 1, 2, 3, ...)
# We iterate from 1 to 99 to find defined services
service_count=0
for i in $(seq 1 99); do
    # Get service name (required)
    name_var="SERVICE_${i}_NAME"
    eval name="\${$name_var:-}"
    
    # Stop if no more services defined
    [ -z "$name" ] && break
    
    # Get other service properties
    enabled_var="SERVICE_${i}_ENABLED"
    pattern_var="SERVICE_${i}_PATTERN"
    domain_var="SERVICE_${i}_DOMAIN"
    upstream_var="SERVICE_${i}_UPSTREAM"
    network_var="SERVICE_${i}_NETWORK"
    
    eval enabled="\${$enabled_var:-true}"
    eval pattern="\${$pattern_var:-A}"
    eval domain="\${$domain_var:-}"
    eval upstream="\${$upstream_var:-}"
    eval network="\${$network_var:-}"
    
    # Resolve max body size: per-service override > global CLIENT_MAX_BODY_SIZE > 50m
    max_body_size_var="SERVICE_${i}_MAX_BODY_SIZE"
    eval max_body_size="\${$max_body_size_var:-}"
    if [ -z "$max_body_size" ]; then
        max_body_size="${CLIENT_MAX_BODY_SIZE:-50M}"
    fi

    # Access restriction vars (Pattern B only)
    allowed_email_domain_var="SERVICE_${i}_ALLOWED_EMAIL_DOMAIN"
    allowed_group_var="SERVICE_${i}_ALLOWED_GROUP"
    eval allowed_email_domain="\${$allowed_email_domain_var:-}"
    eval allowed_group="\${$allowed_group_var:-}"

    # Determine which oauth2-proxy instance to use:
    # If any access restriction is configured, each restricted service gets its
    # own dedicated proxy container (named oauth2-proxy-<name>) so it can enforce
    # per-service --email-domain and/or --allowed-group flags independently.
    # Unrestricted services share the default edge_oauth2_proxy instance.
    if [ -n "$allowed_email_domain" ] || [ -n "$allowed_group" ]; then
        service_oauth2_proxy="oauth2-proxy-${name}"
    else
        service_oauth2_proxy="edge_oauth2_proxy"
    fi

    # Skip disabled services
    if [ "$enabled" != "true" ]; then
        echo "[nginx-entrypoint] Skipping disabled service: $name"
        continue
    fi
    
    # Validate required fields
    if [ -z "$domain" ] || [ -z "$upstream" ]; then
        echo "[nginx-entrypoint] Warning: Service $name missing domain or upstream, skipping"
        continue
    fi
    
    # Select template based on pattern
    case "$pattern" in
        A|a)
            template="$TEMPLATE_DIR/service-pattern-a.conf.template"
            pattern_desc="Django-controlled auth"
            ;;
        B|b)
            template="$TEMPLATE_DIR/service-pattern-b.conf.template"
            pattern_desc="Full nginx-level auth"
            ;;
        *)
            echo "[nginx-entrypoint] Warning: Unknown pattern '$pattern' for $name, defaulting to A"
            template="$TEMPLATE_DIR/service-pattern-a.conf.template"
            pattern_desc="Django-controlled auth (default)"
            ;;
    esac
    
    if [ ! -f "$template" ]; then
        echo "[nginx-entrypoint] Error: Template not found: $template"
        continue
    fi
    
    output_file="$CONF_DIR/${name}.conf"
    
    echo "[nginx-entrypoint] Generating: $name.conf (Pattern: $pattern_desc)"
    echo "[nginx-entrypoint]   Domain: $domain"
    echo "[nginx-entrypoint]   Upstream: $upstream"
    echo "[nginx-entrypoint]   Network: ${network:-not specified}"
    echo "[nginx-entrypoint]   Max body size: $max_body_size"
    echo "[nginx-entrypoint]   OAuth2 proxy: $service_oauth2_proxy"
    
    # First: Substitute service-specific placeholders (using sed)
    # Then: Substitute global environment variables (using envsubst)
    sed -e "s|__SERVICE_NAME__|${name}|g" \
        -e "s|__SERVICE_DOMAIN__|${domain}|g" \
        -e "s|__SERVICE_UPSTREAM__|${upstream}|g" \
        -e "s|__SERVICE_NETWORK__|${network}|g" \
        -e "s|__SERVICE_MAX_BODY_SIZE__|${max_body_size}|g" \
        -e "s|__SERVICE_OAUTH2_PROXY__|${service_oauth2_proxy}|g" \
        "$template" | \
    envsubst '${DOMAIN_AUTH} ${KEYCLOAK_REALM} ${OAUTH2_PROXY_COOKIE_DOMAIN} ${OAUTH2_PROXY_CLIENT_ID}' \
        > "$output_file"
    
    echo "[nginx-entrypoint] Created: ${name}.conf"
    service_count=$((service_count + 1))
done

if [ $service_count -eq 0 ]; then
    echo "[nginx-entrypoint] Warning: No services configured!"
    echo "[nginx-entrypoint] Define services in .env using SERVICE_1_NAME, SERVICE_1_DOMAIN, etc."
else
    echo "[nginx-entrypoint] Generated $service_count service configuration(s)"
fi

# =============================================================================
# Step 4: List generated configs
# =============================================================================
echo "[nginx-entrypoint] Active configurations:"
for conf in "$CONF_DIR"/*.conf; do
    if [ -f "$conf" ]; then
        echo "[nginx-entrypoint]   - $(basename "$conf")"
    fi
done

# =============================================================================
# Step 5: Test nginx configuration
# =============================================================================
echo "[nginx-entrypoint] Testing nginx configuration..."
nginx -t

# =============================================================================
# Step 6: Start nginx
# =============================================================================
echo "[nginx-entrypoint] Starting nginx..."
exec "$@"
