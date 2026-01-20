#!/bin/sh

# =============================================================================
# Nginx Entrypoint Script - Environment Variable Substitution
# =============================================================================
# Copyright (C) 2024-2026 David Kleinhans, Jade University of Applied Sciences
# SPDX-License-Identifier: Apache-2.0
# =============================================================================
# This script runs before nginx starts and substitutes environment variables
# in configuration files, allowing dynamic configuration without editing files.
# =============================================================================

set -e

# List of template files and their destinations
# Templates use ${VARIABLE_NAME} syntax
TEMPLATE_FILES="
/etc/nginx/conf.d/keycloak.conf.template:/etc/nginx/conf.d/keycloak.conf
/etc/nginx/conf.d/itsm.conf.template:/etc/nginx/conf.d/itsm.conf
/etc/nginx/conf.d/deepl.conf.template:/etc/nginx/conf.d/deepl.conf
"

echo "[nginx-entrypoint] Substituting environment variables in nginx configs..."

# Process each template file
echo "$TEMPLATE_FILES" | while IFS=: read -r template output; do
    # Skip empty lines
    [ -z "$template" ] && continue
    
    if [ -f "$template" ]; then
        echo "[nginx-entrypoint] Processing: $template -> $output"
        
        # Substitute environment variables
        # Only substitute variables that are actually set
        envsubst '${DOMAIN_AUTH} ${DOMAIN_ITSM} ${DOMAIN_DEEPL} ${KEYCLOAK_REALM} ${OAUTH2_PROXY_COOKIE_DOMAIN} ${OAUTH2_PROXY_CLIENT_ID}' < "$template" > "$output"
        
        echo "[nginx-entrypoint] Created: $output"
    else
        echo "[nginx-entrypoint] Warning: Template not found: $template"
    fi
done

echo "[nginx-entrypoint] Environment variable substitution complete"

# Test nginx configuration
echo "[nginx-entrypoint] Testing nginx configuration..."
nginx -t

# Execute the main command (start nginx)
echo "[nginx-entrypoint] Starting nginx..."
exec "$@"
