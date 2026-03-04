<!--
SPDX-FileCopyrightText: 2024-2026 David Kleinhans, Jade University of Applied Sciences
SPDX-License-Identifier: Apache-2.0
-->

# Security Policy

## Reporting Vulnerabilities

Please report security vulnerabilities privately by opening a security advisory on GitHub:
https://github.com/scinnod/django-auth-stack/security/advisories/new

Do not open public issues for security vulnerabilities.

## Supported Versions

Only the latest version receives security updates.

## Security Best Practices

- Never commit `.env` files (contains secrets)
- Use strong, unique passwords for all services
- Keep Keycloak and all containers updated
- Use TLS certificates in production
- Regularly rotate secrets and credentials
- Monitor container logs for suspicious activity

## Keycloak Admin Console Protection

The admin console is protected by multiple security layers:

### Default Protections (Always Active)

| Protection | Description |
|------------|-------------|
| Authentication | Keycloak admin username/password required |
| Rate Limiting | 5 req/s per IP (burst 10) on admin console only |
| Security Headers | X-Frame-Options: DENY, CSP: frame-ancestors 'none' |
| No-Cache Headers | Prevents caching of admin responses |
| HTTPS Only | HTTP automatically redirects to HTTPS |
| HSTS | Strict-Transport-Security with preload |

> **Note:** OIDC endpoints are not rate-limited at nginx level. Keycloak has built-in
> brute-force detection, and downstream services should implement their own rate limiting.

### Optional IP Restriction

For production environments, restrict admin access to specific networks.

**Format:** Space-separated list of IP addresses/CIDR blocks (NOT comma-separated)

```bash
# .env - Examples
KEYCLOAK_ADMIN_ALLOWED_IPS=203.0.113.0/24 10.8.0.0/24  # Office + VPN
KEYCLOAK_ADMIN_ALLOWED_IPS=127.0.0.1 ::1              # Localhost only (SSH tunnel)
KEYCLOAK_ADMIN_ALLOWED_IPS=                           # No restriction (empty = any IP)
```

See [README.md](README.md#keycloak-admin-console-security) for detailed configuration.

## Configuration Maintenance

Keeping your configuration up-to-date is important for security. Use the configuration script to safely update settings:

```bash
./scripts/configure-env.sh
```

The script:
- Preserves existing secrets by default (requires explicit `YES` confirmation to regenerate)
- Shows current values as defaults for easy review
- Creates a backup before saving changes
- Generates a clean `.env` file with consistent structure

**Recommended practices:**
- Review configuration periodically, especially after updates
- Use IP restriction for admin console on public servers
- Run `./scripts/preflight-check.sh` to verify security settings
