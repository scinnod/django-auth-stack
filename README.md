# Edge-Auth Stack: nginx + Keycloak SSO

Production-ready authentication gateway combining nginx reverse proxy with Keycloak SSO for Django services.

## 🎯 Features

- **Keycloak SSO** - Industry-standard OIDC & SAML authentication
- **OAuth2 Proxy** - Seamless forward auth integration with nginx  
- **Config-as-Code** - Manage Keycloak via JSON realm exports (no clicking!)
- **Network Segmentation** - Defense-in-depth with isolated Docker networks
- **Dual TLS Mode** - Provided certificates or Let's Encrypt
- **SAML Support** - Full SAML 2.0 IdP capabilities for Shibboleth integration

## 📋 Table of Contents

1. [Architecture](#architecture)
2. [Quick Start](#quick-start)
3. [Initial Setup](#initial-setup)
4. [Keycloak Configuration](#keycloak-configuration)
5. [Domain Selection](#domain-selection)
6. [TLS Certificate Modes](#tls-certificate-modes)
7. [Network Architecture](#network-architecture)
8. [Django Integration](#django-integration)
9. [Production Readiness](#production-readiness)
10. [Troubleshooting](#troubleshooting)

---

## Architecture

```
Internet
   ↓
nginx (TLS termination, reverse proxy)
   ↓
   ├─→ Public paths (no auth) → Upstream Apps
   ↓
   ├─→ Protected paths → OAuth2 Proxy → Keycloak → Upstream Apps
   ↓
   └─→ auth.jade.local → Keycloak Admin Console
```

### Components

- **nginx**: Public-facing reverse proxy (ports 80/443)
- **Keycloak**: SSO server providing OIDC & SAML
- **OAuth2 Proxy**: Forward authentication middleware
- **PostgreSQL**: Keycloak database
- **Upstream Apps**: Your Django services (ITSM, Translation)

---

## Quick Start

### 1. Create External Networks

```bash
docker network create itsm_backend
docker network create deepl_backend
```

### 2. Configure Environment

Run the initialization script to generate secure passwords and configure domains:

```bash
./scripts/init-env.sh
```

This will:
- Generate secure Keycloak admin password
- Generate OAuth2-proxy secrets
- Prompt for domain configuration
- Create `.env` file with all required variables

Alternatively, manually copy and edit:
```bash
cp .env.example .env
# Edit .env with your values
```

### 3. Start Services

```bash
# Stop any existing services
sudo docker compose down -v

# Start Keycloak stack
sudo docker compose up -d

# Check status
sudo docker compose ps
```

### 4. Initial Keycloak Setup

1. Access Keycloak admin console: `https://auth.jade.local`
2. Log in with admin credentials from `.env`
3. Follow [Keycloak Configuration](#keycloak-configuration) section

---

## Initial Setup

### Prerequisites

- Docker & Docker Compose
- Domain names configured in `/etc/hosts` or DNS:
  ```
  127.0.0.1 auth.jade.local itsm.jade.local translation.jade.local
  ```

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

# Domains
DOMAIN_AUTH=auth.jade.local
DOMAIN_ITSM=itsm.jade.local
DOMAIN_DEEPL=translation.jade.local
KEYCLOAK_REALM=jade
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

1. Access Keycloak admin: `https://auth.jade.local`
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
   - Root URL: `https://auth.jade.local`
   - Valid redirect URIs:
     ```
     https://auth.jade.local/oauth2/callback
     https://itsm.jade.local/oauth2/callback
     https://translation.jade.local/oauth2/callback
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
# Add to /etc/hosts
127.0.0.1 auth.jade.local itsm.jade.local translation.jade.local
```

**Configure in `.env`:**
```bash
DOMAIN_AUTH=auth.jade.local
DOMAIN_ITSM=itsm.jade.local
DOMAIN_DEEPL=translation.jade.local
OAUTH2_PROXY_COOKIE_DOMAIN=.jade.local
```

### Option B: Public domains (Production)

**Requirements:**
- DNS records pointing to your server
- Valid TLS certificates (Let's Encrypt recommended)

**Configure in `.env`:**
```bash
DOMAIN_AUTH=auth.example.com
DOMAIN_ITSM=itsm.example.com
DOMAIN_DEEPL=deepl.example.com
OAUTH2_PROXY_COOKIE_DOMAIN=.example.com
LETSENCRYPT_EMAIL=admin@example.com
```

---

## TLS Certificate Modes

### Mode A: Provided Certificates (Default)

Place your certificates in `./certs/`:
```bash
./certs/
├── fullchain.pem  # Full certificate chain
└── privkey.pem    # Private key
```

### Mode B: Let's Encrypt

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

itsm_backend (external - shared with ITSM stack)
  ├─ nginx
  └─ itsm_nginx:8000

deepl_backend (external - shared with Translation stack)
  ├─ nginx
  └─ deepl_nginx:8000
```

### Why External Networks?

The `itsm_backend` and `deepl_backend` networks are **external** because they're shared with other Docker Compose stacks running your Django applications.

**Create them once:**
```bash
docker network create itsm_backend
docker network create deepl_backend
```

**Connect your Django containers:**
```yaml
# In your Django app's docker-compose.yml
services:
  itsm_nginx:
    networks:
      - itsm_backend

networks:
  itsm_backend:
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

This stack provides **two authentication patterns** as scaffold configurations:

### Pattern A: Django-Controlled Authentication (ITSM service)

Django decides what's public vs protected. `@login_required` triggers Keycloak SSO.

**Use when:** You want public pages (marketing, blog, docs) + protected areas (dashboard, admin)

**How it works:**
1. Public Django pages accessible without Keycloak login
2. `@login_required` redirects to `/sso-login/` endpoint
3. nginx validates `/sso-login/` via OAuth2-proxy → Keycloak
4. After login, Django receives `X-Remote-User` header, creates session
5. Subsequent requests use Django session only

**Configuration:** `nginx/conf.d/itsm.conf.template`

### Pattern B: Full nginx-Level Authentication (DeepL service)

nginx authenticates ALL requests (including static files). Everything protected.

**Use when:** No public access needed. Internal tools, admin dashboards, confidential services.

**How it works:**
1. Every request validated by OAuth2-proxy (fast cookie check)
2. Django receives authenticated headers for all requests
3. Simpler setup, maximum security

**Configuration:** `nginx/conf.d/deepl.conf.template`

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

📖 **[Django Integration Guide](keycloak/DJANGO_INTEGRATION.md)**

Includes:
- Complete settings.py configuration
- @login_required decorator usage
- **Django i18n_patterns support** (works seamlessly with `/de/admin/`, `/en/admin/`, etc.)
- Auto-creating users from Keycloak
- Logout handling
- Security considerations
- Troubleshooting common issues

---

## Production Readiness

This stack is **production-ready** with the following configurations:

### ✅ Security
- TLS 1.2/1.3 only, modern cipher suites (Mozilla Modern profile)
- HSTS, X-Frame-Options, X-Content-Type-Options headers
- Network segmentation (internal networks for sensitive services)
- `no-new-privileges` security option on all containers
- OAuth2-proxy validates authentication before nginx forwards requests

### ✅ nginx Configuration
- Hardened defaults for production edge proxy
- OCSP stapling for certificate validation
- Gzip compression enabled
- Proper proxy headers (X-Forwarded-*, X-Real-IP)
- WebSocket support
- Health check endpoint
- Rate limiting **disabled** (suitable for reverse proxy setups where multiple users share few IPs)

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

1. **Change domains** from `*.jade.local` to your production domains in `.env`
2. **Use real TLS certificates**:
   - Either provide certificates in `./certs/` (fullchain.pem, privkey.pem)
   - Or use Let's Encrypt override (see TLS Certificate Modes section)
3. **Update Keycloak realm configuration**:
   - Configure your OAuth2 client in Keycloak admin console
   - Export realm to `./keycloak/realms/` for version control
4. **Secure all passwords** in `.env` (auto-generated by init-env.sh script)
5. **Configure external networks**: Create `itsm_backend` and `deepl_backend` networks
6. **Review firewall rules**: Ensure only ports 80/443 are exposed
7. **Set up log rotation** for nginx logs volume
8. **Configure backup** for PostgreSQL volume

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
1. Verify `OAUTH2_PROXY_COOKIE_DOMAIN=.jade.local` in `.env`
2. Restart: `sudo docker compose restart oauth2-proxy nginx`

### Can't access services after migration

**Check nginx logs:**
```bash
sudo docker compose logs nginx
```

**Verify nginx templates regenerated:**
```bash
ls -l nginx/conf.d/*.conf
# Should see keycloak.conf, itsm.conf, deepl.conf
```

**Force regeneration:**
```bash
sudo rm nginx/conf.d/*.conf
sudo docker compose restart nginx
```

### Test OAuth2 Proxy directly

```bash
# Check OAuth2 Proxy health
curl -k https://auth.jade.local/oauth2/ping

# Test auth endpoint
curl -k -v https://itsm.jade.local/oauth2/auth
# Should return 401 (unauthorized) with redirect header
```

---

## Next Steps

1. ✅ Configure Keycloak realm and OIDC client
2. ✅ Create test users
3. ✅ Test authentication on protected paths
4. Configure SAML for Shibboleth integration
5. Set up production TLS certificates
6. Export realm configuration for version control
7. Configure additional authentication providers (LDAP, OAuth, etc.)

---

## References

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [OAuth2 Proxy Documentation](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Keycloak SAML Guide](https://www.keycloak.org/docs/latest/server_admin/#_saml)
- [nginx auth_request Module](http://nginx.org/en/docs/http/ngx_http_auth_request_module.html)

---

## License

This configuration is provided as-is for use in your projects.

---

**Need help?** Check the troubleshooting section or review the Keycloak logs.
