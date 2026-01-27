<!--
SPDX-FileCopyrightText: 2024-2026 David Kleinhans, Jade University of Applied Sciences
SPDX-License-Identifier: Apache-2.0
-->

# Django Auth Stack: nginx + Keycloak SSO

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker)](https://docs.docker.com/compose/)
[![Keycloak](https://img.shields.io/badge/Keycloak-23.0-blue)](https://www.keycloak.org/)

Production-ready authentication gateway combining nginx reverse proxy with Keycloak SSO for any number of upstream services.

## 🎯 Features

- **Keycloak SSO** - Industry-standard OIDC & SAML authentication
- **OAuth2 Proxy** - Seamless forward auth integration with nginx  
- **Dynamic Service Configuration** - Configure any number of upstream services via `.env`
- **Two Authentication Patterns** - Django-controlled (Pattern A) or full protection (Pattern B)
- **Per-Service Enable/Disable** - Toggle services on/off without removing configuration
- **Config-as-Code** - Manage Keycloak via JSON realm exports (no clicking!)
- **Network Segmentation** - Defense-in-depth with isolated Docker networks
- **Dual TLS Mode** - Provided certificates or Let's Encrypt
- **SAML Support** - Full SAML 2.0 IdP capabilities for Shibboleth integration

## 📋 Table of Contents

1. [Architecture](#architecture)
2. [Quick Start](#quick-start)
3. [Service Configuration](#service-configuration)
4. [Initial Setup](#initial-setup)
5. [Keycloak Configuration](#keycloak-configuration)
6. [Domain Selection](#domain-selection)
7. [Keycloak Admin Console Security](#keycloak-admin-console-security)
8. [TLS Certificate Modes](#tls-certificate-modes)
9. [Network Architecture](#network-architecture)
10. [Django Integration](#django-integration)
11. [Production Readiness](#production-readiness)
12. [Troubleshooting](#troubleshooting)

---

## Architecture

```
Internet
   ↓
nginx (TLS termination, reverse proxy)
   ↓
   ├─→ Public paths (Pattern A) → Upstream Apps
   ↓
   ├─→ Protected paths → OAuth2 Proxy → Keycloak → Upstream Apps
   ↓
   └─→ auth.example.local → Keycloak Admin Console
```

### Components

- **nginx**: Public-facing reverse proxy (ports 80/443)
- **Keycloak**: SSO server providing OIDC & SAML
- **OAuth2 Proxy**: Forward authentication middleware
- **PostgreSQL**: Keycloak database
- **Upstream Services**: Any number of services (Django, Node.js, etc.)

---

## Quick Start

### 1. Configure Environment & Services

Run the initialization script to generate secure passwords and configure your services:

```bash
./scripts/init-env.sh
```

This will:
- Generate secure Keycloak admin password
- Generate OAuth2-proxy secrets
- Prompt for domain configuration
- **Interactively configure your upstream services** (name, domain, pattern, network)
- Create `.env` file with all required variables

Alternatively, manually copy and edit:
```bash
cp .env.example .env
# Edit .env with your values (see Service Configuration section)
```

### 2. Generate Docker Compose Override

After configuring services in `.env`, generate the network configuration:

```bash
./scripts/generate-compose-override.sh
```

This creates `docker-compose.override.yml` with the external networks for your services.

### 3. Create External Networks

Create Docker networks for each configured service:

```bash
# Example for services named "itsm" and "translation"
docker network create itsm_backend
docker network create translation_backend
```

### 4. Generate or Place TLS Certificates

> ⚠️ **IMPORTANT:** Certificates MUST exist before starting Docker services!
> If Docker starts first, it creates empty root-owned directories that complicate setup.

**Option A: Self-signed certificates (development)**
```bash
./scripts/init-selfsigned.sh
```
This generates both certificates AND DH parameters in `certs/`.

**Option B: Your own certificates (production)**
```bash
# Place your certificates in certs/
certs/
├── fullchain.pem   # Full certificate chain
├── privkey.pem     # Private key
└── dhparam.pem     # DH parameters (generate if missing)

# Generate DH parameters if you don't have them:
openssl dhparam -out certs/dhparam.pem 2048
```

**Option C: Let's Encrypt**
```bash
./scripts/init-letsencrypt.sh
```

### 5. Run Pre-flight Check

Validate everything is ready before starting:

```bash
# Check for issues
./scripts/preflight-check.sh

# Or auto-fix common issues
./scripts/preflight-check.sh --fix
```

### 6. Start Services

```bash
# Start Keycloak stack
# Note: docker-compose.override.yml is automatically loaded if it exists
docker compose up -d

# Check status
docker compose ps

# View logs
docker compose logs -f nginx
```

### 7. Initial Keycloak Setup

1. Access Keycloak admin console: `https://auth.example.local`
2. Log in with admin credentials from `.env`
3. Follow [Keycloak Configuration](#keycloak-configuration) section

---

## Service Configuration

This stack supports **any number of upstream services** (0 to N), each configured in `.env`.

### Configuration Variables

Each service is configured with numbered variables:

```bash
# --- Service 1: Example Django App ---
SERVICE_1_NAME=myapp                      # Unique name (lowercase, alphanumeric)
SERVICE_1_ENABLED=true                    # true/false - toggle without removing config
SERVICE_1_PATTERN=A                       # A or B (see patterns below)
SERVICE_1_DOMAIN=myapp.example.local      # Domain for this service
SERVICE_1_UPSTREAM=myapp_nginx:8000       # Container:port to proxy to
SERVICE_1_NETWORK=myapp_backend           # Docker network name

# --- Service 2: Another App ---
SERVICE_2_NAME=admin
SERVICE_2_ENABLED=true
SERVICE_2_PATTERN=B
SERVICE_2_DOMAIN=admin.example.local
SERVICE_2_UPSTREAM=admin_app:3000
SERVICE_2_NETWORK=admin_backend
```

### Authentication Patterns

**Pattern A: Django-Controlled Authentication**
- Django decides what's public vs protected
- Public pages accessible without login
- `@login_required` triggers Keycloak SSO via `/sso-login/`
- **Best for:** Django apps with public landing pages + protected areas

**Pattern B: Full nginx-Level Authentication**
- ALL requests require Keycloak login (including static files)
- nginx validates every request before forwarding
- **Best for:** Internal tools, admin dashboards, fully confidential services
- **Works with any upstream** (not just Django)

### Adding/Removing Services

1. Edit `.env` to add/modify/remove service configuration
2. Regenerate compose override: `./scripts/generate-compose-override.sh`
3. Create new networks if needed: `docker network create <service>_backend`
4. Restart nginx: `docker compose restart nginx`

### Disabling a Service

Set `SERVICE_N_ENABLED=false` to disable a service without removing its configuration:

```bash
SERVICE_2_ENABLED=false   # Temporarily disabled
```

Then restart nginx: `docker compose restart nginx`

---

## Initial Setup

### Prerequisites

- Docker & Docker Compose v2+
- Domain names configured (see below)
- TLS certificates (see [TLS Certificate Modes](#tls-certificate-modes))

> **Note on file mounts:** Docker will create mount points as root-owned directories
> if the source files don't exist. Always generate certificates BEFORE running
> `docker compose up` for the first time. If you encounter permission issues,
> run `./scripts/preflight-check.sh --fix` to repair them.

### Configuring Local Domains

For local development, add the domains to your hosts file:

**Linux / macOS:**
```bash
# Edit hosts file (requires sudo)
sudo nano /etc/hosts

# Add your configured domains:
127.0.0.1 auth.example.local myapp.example.local admin.example.local
```

**Windows:**
```powershell
# Open PowerShell as Administrator, then edit:
notepad C:\Windows\System32\drivers\etc\hosts

# Add your configured domains:
127.0.0.1 auth.example.local myapp.example.local admin.example.local
```

> **Note:** For production, use real domain names with proper DNS records instead of hosts file entries.

### Environment Variables

Critical variables in `.env`:

```bash
# Database
POSTGRES_PASSWORD=<strong-random-password>

# Keycloak Admin
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=<strong-random-password>

# OAuth2 Proxy Secrets
OAUTH2_PROXY_CLIENT_ID=oauth2-proxy
OAUTH2_PROXY_CLIENT_SECRET=<from-keycloak-after-setup>
OAUTH2_PROXY_COOKIE_SECRET=<32-char-random-string>

# Auth Domain
DOMAIN_AUTH=auth.example.local
OAUTH2_PROXY_COOKIE_DOMAIN=.example.local
KEYCLOAK_REALM=jade

# Services (see Service Configuration section)
SERVICE_1_NAME=myapp
SERVICE_1_ENABLED=true
SERVICE_1_PATTERN=A
SERVICE_1_DOMAIN=myapp.example.local
SERVICE_1_UPSTREAM=myapp_nginx:8000
SERVICE_1_NETWORK=myapp_backend
```

**Generate secrets:**
```bash
# Cookie secret (32 characters)
openssl rand -base64 32 | head -c 32

# Admin password
openssl rand -base64 20
```

---

## Keycloak Configuration

### Step 1: Create a Realm

1. Access Keycloak admin: `https://auth.example.local`
2. Click dropdown in top-left (says "Master") → **Create Realm**
3. Name: `jade` (must match `KEYCLOAK_REALM` in `.env`)
4. Click **Create**

### Step 2: Create an OIDC Client for OAuth2 Proxy

1. Go to **Clients** → **Create client**
2. **General Settings**:
   - Client type: `OpenID Connect`
   - Client ID: `oauth2-proxy` (must match `.env`)
   - Click **Next**

3. **Capability config**:
   - Client authentication: `ON`
   - Authorization: `OFF`
   - Authentication flow: Enable only `Standard flow`
   - Click **Next**

4. **Login settings**:
   - Root URL: `https://auth.example.local`
   - **Valid redirect URIs** (list each domain explicitly - wildcards may cause issues):
     ```
     https://auth.example.local/oauth2/callback
     https://app1.example.local/oauth2/callback
     https://app2.example.local/oauth2/callback
     ```
   - **Valid post logout redirect URIs** (required for proper logout):
     ```
     https://auth.example.local/*
     https://app1.example.local/*
     https://app2.example.local/*
     ```
   - Web origins: `+` (allows all valid redirect URIs)
   - Click **Save**

5. **Get Client Secret**:
   - Go to **Credentials** tab
   - Copy the **Client secret**
   - Update `.env` file:
     ```bash
     OAUTH2_PROXY_CLIENT_SECRET=<paste-secret-here>
     ```
   - Restart services:
     ```bash
     sudo docker compose restart oauth2-proxy nginx
     ```

> **Note on User Identification:** OAuth2-proxy passes two separate headers to upstream services:
> - `X-Remote-User`: The Keycloak username (e.g., `john.doe`) from the `preferred_username` claim
> - `X-Remote-Email`: The Keycloak email (e.g., `john.doe@example.com`) from the `email` claim
>
> See [Django Integration Guide](docs/django-integration.md) for details on using these headers.

### Step 3: Create Test Users

1. Go to **Users** → **Add user**
2. Username: `testuser`
3. Email: `test@example.com`
4. Click **Create**
5. Go to **Credentials** tab → **Set password**
6. Password: Choose a password
7. Temporary: `OFF`
8. Click **Save**

### Step 4: (Optional) Configure SAML for Shibboleth

1. Go to **Clients** → **Create client**
2. Client type: `SAML`
3. Client ID: Your Shibboleth SP entity ID
4. Configure according to your Shibboleth IdP requirements

Full SAML configuration guide: https://www.keycloak.org/docs/latest/server_admin/#_saml

---

## Domain Selection

### Option A: `.local` domains (Recommended for development)

**Advantages:**
- Works immediately with `/etc/hosts`
- No DNS configuration needed
- Browser accepts cookies for SSO

**Setup:**
```bash
# Add to /etc/hosts (include all your service domains)
127.0.0.1 auth.example.local myapp.example.local admin.example.local
```

**Configure in `.env`:**
```bash
DOMAIN_AUTH=auth.example.local
OAUTH2_PROXY_COOKIE_DOMAIN=.example.local

# Each service gets its own domain
SERVICE_1_DOMAIN=myapp.example.local
SERVICE_2_DOMAIN=admin.example.local
```

### Option B: Public domains (Production)

**Requirements:**
- DNS records pointing to your server
- Valid TLS certificates (Let's Encrypt recommended)

**Configure in `.env`:**
```bash
DOMAIN_AUTH=auth.example.com
OAUTH2_PROXY_COOKIE_DOMAIN=.example.com
LETSENCRYPT_EMAIL=admin@example.com

# Each service gets its own domain
SERVICE_1_DOMAIN=myapp.example.com
SERVICE_2_DOMAIN=admin.example.com
```

---

## Keycloak Admin Console Security

The Keycloak admin console (`/admin`) is a high-value target. This stack implements defense-in-depth:

### Default Protections (Always Active)

1. **Keycloak Authentication** - Admin console requires username/password
2. **Strict Rate Limiting** - 5 requests/second per IP (burst 10) prevents brute-force
3. **Enhanced Security Headers:**
   - `X-Frame-Options: DENY` - Prevents clickjacking
   - `Content-Security-Policy: frame-ancestors 'none'` - Additional clickjacking protection
   - `Cache-Control: no-store, no-cache` - Prevents caching of sensitive admin pages

> **Note:** OIDC endpoints (`/realms/`) are intentionally not rate-limited at the nginx level.
> Keycloak has built-in brute-force detection, and downstream OAuth2 clients should implement
> their own rate limiting appropriate to their use case.

### Optional: IP-Based Access Restriction

For production environments, you can restrict admin console access to specific IPs or networks:

```bash
# In .env - restrict to office network and VPN
KEYCLOAK_ADMIN_ALLOWED_IPS=203.0.113.0/24 10.8.0.0/24

# Restrict to localhost only (access via SSH tunnel)
KEYCLOAK_ADMIN_ALLOWED_IPS=127.0.0.1 ::1

# Allow specific admin workstations
KEYCLOAK_ADMIN_ALLOWED_IPS=192.168.1.100 192.168.1.101 10.0.0.50
```

When configured, requests from non-allowed IPs receive HTTP 403 Forbidden.

**When to use IP restriction:**
- Production servers accessible from the internet
- Compliance requirements mandate network-level access control
- Defense-in-depth for high-security environments

**When NOT to use:**
- Development environments (leave unset)
- Dynamic IP environments without VPN
- When you might lock yourself out

> **TIP:** If using IP restriction, always include a fallback access method (VPN, bastion host, or SSH tunnel with `127.0.0.1`).

---

## TLS Certificate Modes

### Required Files

All TLS modes require these files in `./certs/`:
```bash
./certs/
├── fullchain.pem  # Full certificate chain
├── privkey.pem    # Private key
└── dhparam.pem    # DH parameters for key exchange
```

**About DH Parameters:**
- DH parameters are random prime numbers for Diffie-Hellman key exchange
- They are NOT certificate-dependent (same file works with any certificate)
- Generate once: `openssl dhparam -out certs/dhparam.pem 2048`
- Or use `./scripts/preflight-check.sh --fix` to auto-generate

### Mode A: Self-Signed Certificates (Development)

```bash
./scripts/init-selfsigned.sh
```

This generates all required files automatically.

### Mode B: Provided Certificates (Production)

Place your certificates in `./certs/`:
```bash
# Copy your certificates
cp /path/to/your/fullchain.pem certs/
cp /path/to/your/privkey.pem certs/

# Generate DH parameters if you don't have them
openssl dhparam -out certs/dhparam.pem 2048
```

### Mode C: Let's Encrypt

1. Update `.env`:
   ```bash
   LETSENCRYPT_EMAIL=your-email@example.com
   ```

2. Run init script:
   ```bash
   ./scripts/init-letsencrypt.sh
   ```

3. Start with Let's Encrypt override:
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.letsencrypt.yml up -d
   ```

---

## Network Architecture

### Network Segmentation

```
proxy (public)
  └─ nginx:80,443

auth_backend (internal)
  ├─ nginx
  ├─ oauth2-proxy
  └─ keycloak

keycloak_db (internal)
  ├─ keycloak
  └─ postgres

<service>_backend (external - one per configured service)
  ├─ nginx
  └─ <service>_upstream:port
```

### Dynamic Service Networks

Service networks are added via `docker-compose.override.yml`, which is generated from your `.env` configuration:

```bash
# After configuring services in .env
./scripts/generate-compose-override.sh
```

This creates the override file that adds external networks for each enabled service.

### Why External Networks?

Service networks (e.g., `myapp_backend`) are **external** because they're shared with other Docker Compose stacks running your upstream applications.

**Create a network for each service:**
```bash
docker network create myapp_backend
docker network create admin_backend
```

**Connect your upstream containers:**
```yaml
# In your Django/Node.js app's docker-compose.yml
services:
  myapp_nginx:
    networks:
      - myapp_backend

networks:
  myapp_backend:
    external: true
```

---

## Config-as-Code with Keycloak

After initial setup via the web UI, export your realm configuration:

```bash
# Export realm to JSON
sudo docker exec edge_keycloak /opt/keycloak/bin/kc.sh export \
  --realm jade \
  --file /tmp/jade-realm.json

# Copy to local directory
sudo docker cp edge_keycloak:/tmp/jade-realm.json ./keycloak/realms/

# Edit jade-realm.json as needed (add users, clients, etc.)

# On next restart, Keycloak auto-imports from ./keycloak/realms/
sudo docker compose restart keycloak
```

This allows you to manage Keycloak in version control instead of clicking!

---

## Django Integration

This stack provides **two authentication patterns** via nginx templates:

### Pattern A: Django-Controlled Authentication

Django decides what's public vs protected. `@login_required` triggers Keycloak SSO.

**Use when:** You want public pages (marketing, blog, docs) + protected areas (dashboard, admin)

**How it works:**
1. Public Django pages accessible without Keycloak login
2. `@login_required` redirects to `/sso-login/` endpoint
3. nginx validates `/sso-login/` via OAuth2-proxy → Keycloak
4. After login, Django receives `X-Remote-User` header, creates session
5. Subsequent requests use Django session only

**Template:** `nginx/conf.d/service-pattern-a.conf.template`

### Pattern B: Full nginx-Level Authentication

nginx authenticates ALL requests (including static files). Everything protected.

**Use when:** No public access needed. Internal tools, admin dashboards, confidential services.

**How it works:**
1. Every request validated by OAuth2-proxy (fast cookie check)
2. Upstream receives authenticated headers for all requests
3. Simpler setup, maximum security
4. **Works with any upstream service** (Django, Node.js, etc.)

**Template:** `nginx/conf.d/service-pattern-b.conf.template`

### Django Setup

**Pattern A** requires:
```python
# settings.py
LOGIN_URL = '/sso-login/'
AUTHENTICATION_BACKENDS = ['django.contrib.auth.backends.RemoteUserBackend', ...]
MIDDLEWARE = [..., 'django.contrib.auth.middleware.RemoteUserMiddleware', ...]
REMOTE_USER_HEADER = 'HTTP_X_REMOTE_USER'

# views.py
def sso_login(request):
    return redirect(request.GET.get('next', '/'))

# urls.py
urlpatterns = [path('sso-login/', views.sso_login), ...]
```

**Pattern B** requires:
```python
# settings.py (simpler - no LOGIN_URL or sso_login view needed)
AUTHENTICATION_BACKENDS = ['django.contrib.auth.backends.RemoteUserBackend', ...]
MIDDLEWARE = [..., 'django.contrib.auth.middleware.RemoteUserMiddleware', ...]
REMOTE_USER_HEADER = 'HTTP_X_REMOTE_USER'
```

### Complete Integration Guide

For detailed configuration, troubleshooting, and examples:

📖 **[Django Integration Guide](docs/django-integration.md)**

Includes:
- Complete settings.py configuration
- @login_required decorator usage
- **Django i18n_patterns support** (works seamlessly with `/de/admin/`, `/en/admin/`, etc.)
- Auto-creating users from Keycloak
- Logout handling (full OIDC logout)
- Security considerations
- Troubleshooting common issues

📖 **[Logout Configuration Guide](docs/keycloak-logout.md)**

Details on OIDC RP-Initiated Logout implementation:
- How full SSO logout works (Django + Keycloak session termination)
- Nginx-based logout handling (oauth2-proxy v7.6.0 workaround)
- Required Keycloak client settings (Valid Post Logout Redirect URIs)
- Testing and troubleshooting

---

## Production Readiness

This stack is **production-ready** with the following configurations:

### ✅ Security
- TLS 1.2/1.3 only, modern cipher suites (Mozilla Modern profile)
- HSTS, X-Frame-Options, X-Content-Type-Options headers
- Network segmentation (internal networks for sensitive services)
- `no-new-privileges` security option on all containers
- OAuth2-proxy validates authentication before nginx forwards requests
- **Keycloak Admin Console Hardening:**
  - Strict rate limiting (5 req/s, burst 10) to prevent brute-force attacks
  - Enhanced security headers (CSP frame-ancestors 'none', no-cache, X-Frame-Options: DENY)
  - Optional IP-based access restriction via `KEYCLOAK_ADMIN_ALLOWED_IPS`

### ✅ nginx Configuration
- Hardened defaults for production edge proxy
- OCSP stapling for certificate validation
- Gzip compression enabled
- Proper proxy headers (X-Forwarded-*, X-Real-IP)
- WebSocket support
- Health check endpoint
- **Rate limiting for Keycloak admin console only** (5 req/s, protects against brute-force)
- OIDC endpoints are not rate-limited (Keycloak has built-in brute-force protection)

### ✅ Keycloak
- PostgreSQL database (recommended for production by Keycloak)
- `KC_PROXY=edge` mode (behind reverse proxy)
- Metrics and health endpoints enabled
- Config-as-code support via realm imports
- Transaction XA disabled (recommended for PostgreSQL)

### ✅ OAuth2-proxy Configuration

The OAuth2-proxy configuration includes several `--insecure-*` flags that are **safe for production** in this specific architecture:

- `--insecure-oidc-skip-issuer-verification=true`: Required because OAuth2-proxy talks to Keycloak via internal Docker network (`http://keycloak:8080`) while the public OIDC issuer is `https://auth.yourdomain.com`. This is **standard for reverse proxy setups**.
  
- `--ssl-insecure-skip-verify=true`: OAuth2-proxy → Keycloak communication is over internal Docker network using HTTP (not HTTPS). External TLS is handled by nginx. This is **secure** because the internal network is isolated.

- `--insecure-oidc-allow-unverified-email=true`: Allows users to login even if their email isn't verified in Keycloak. Change to `false` if you require email verification.

- `--skip-claims-from-profile-url=true`: Optimization to avoid extra OIDC userinfo endpoint call. User info comes from ID token instead. Safe for production.

These flags address the **internal vs external URL mismatch** inherent to reverse proxy setups and do not compromise security when properly configured with network isolation.

### ✅ Health Checks
- PostgreSQL: `pg_isready` check
- Keycloak: Simple TCP check (port 8080)
- nginx: HTTP health endpoint check
- OAuth2-proxy: No health check (minimal image, runs reliably without one)

### ✅ Let's Encrypt Support
Built-in support for automatic certificate renewal:
```bash
docker compose -f docker-compose.yml -f docker-compose.letsencrypt.yml up -d
```

### Production Checklist

Before deploying to production:

1. **Change domains** from `*.example.local` to your production domains in `.env`
2. **Use real TLS certificates**:
   - Either provide certificates in `./certs/` (fullchain.pem, privkey.pem)
   - Or use Let's Encrypt override (see TLS Certificate Modes section)
3. **Update Keycloak realm configuration**:
   - Configure your OAuth2 client in Keycloak admin console
   - Export realm to `./keycloak/realms/` for version control
4. **Secure all passwords** in `.env` (auto-generated by init-env.sh script)
5. **Configure service networks**: Create Docker networks for each service
6. **Generate compose override**: Run `./scripts/generate-compose-override.sh`
7. **Review firewall rules**: Ensure only ports 80/443 are exposed
8. **Set up log rotation** for nginx logs volume
9. **Configure backup** for PostgreSQL volume

---

## Troubleshooting

### Keycloak not starting

**Check logs:**
```bash
sudo docker compose logs keycloak
```

**Common issues:**
- Database connection failed → Check `POSTGRES_PASSWORD` in `.env`
- Port already in use → Stop conflicting services

### OAuth2 Proxy returns 500 error

**Check configuration:**
```bash
sudo docker compose logs oauth2-proxy
```

**Common issues:**
- Invalid client secret → Verify `OAUTH2_PROXY_CLIENT_SECRET` matches Keycloak
- OIDC issuer URL incorrect → Check `KEYCLOAK_REALM` in `.env`

### Authentication redirects to wrong domain

**Fix cookie domain:**
1. Verify `OAUTH2_PROXY_COOKIE_DOMAIN=.example.local` in `.env`
2. Restart: `sudo docker compose restart oauth2-proxy nginx`

### Service not accessible / nginx returns 502

**Check if service network is configured:**
```bash
# Verify docker-compose.override.yml exists
cat docker-compose.override.yml

# If missing, generate it
./scripts/generate-compose-override.sh

# Create missing networks
docker network create <service>_backend

# Restart nginx
docker compose restart nginx
```

### Can't access services after adding new service

**Check nginx logs:**
```bash
sudo docker compose logs nginx
```

**Verify nginx configs were generated:**
```bash
ls -l nginx/conf.d/*.conf
# Should see keycloak.conf and one .conf per enabled service
```

**Force regeneration:**
```bash
sudo rm nginx/conf.d/*.conf
sudo docker compose restart nginx
```

### Test OAuth2 Proxy directly

```bash
# Check OAuth2 Proxy health
curl -k https://auth.example.local/oauth2/ping

# Test auth endpoint (replace myapp with your service domain)
curl -k -v https://myapp.example.local/oauth2/auth
# Should return 401 (unauthorized) with redirect header
```

---

## Next Steps

1. ✅ Configure services in `.env`
2. ✅ Generate compose override with `./scripts/generate-compose-override.sh`
3. ✅ Configure Keycloak realm and OIDC client
4. ✅ Create test users
5. ✅ Test authentication on protected paths
6. Configure SAML for Shibboleth integration (if needed)
7. Set up production TLS certificates
8. Export realm configuration for version control
9. Configure additional authentication providers (LDAP, OAuth, etc.)

---

## References

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [OAuth2 Proxy Documentation](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Keycloak SAML Guide](https://www.keycloak.org/docs/latest/server_admin/#_saml)
- [nginx auth_request Module](http://nginx.org/en/docs/http/ngx_http_auth_request_module.html)

---

## License

Copyright (C) 2024-2026 David Kleinhans, Jade University of Applied Sciences

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

See the [LICENSE](LICENSE) and [NOTICE](NOTICE) files for details.

---

**Need help?** Check the troubleshooting section or review the Keycloak logs.
