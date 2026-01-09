# Edge-Auth Stack: nginx + Authentik SSO

Production-ready reverse proxy and authentication gateway combining nginx with Authentik SSO, featuring network segmentation, TLS termination, and forward-auth integration.

## 📋 Overview

This stack provides:
- **nginx** - Alpine-based reverse proxy (public entrypoint, ports 80/443)
- **Authentik** - Modern SSO/authentication platform (server + worker)
- **PostgreSQL** - Authentik database (Alpine-based)
- **Redis** - Authentik cache/message broker (Alpine-based)

### Virtual Hosts

| Domain | Access Policy | Upstream |
|--------|---------------|----------|
| `auth.example.org` | Public (login portal) | `authentik-server:9000` |
| `itsm.example.org` | Mixed (public + auth on `/admin/`, `/restricted/`, `/api/private/`) | `itsm_nginx:8000` |
| `deepl.example.org` | Fully authenticated | `deepl_nginx:8000` |

### Network Architecture (Defense in Depth)

```
Internet
    |
    v
[nginx] (ports 80/443)
    |
    +---> proxy (auto-created) ------> Public-facing
    |
    +---> auth_backend (internal) ---> authentik-server
    |
    +---> itsm_backend (external) ---> itsm_nginx:8000
    |
    +---> deepl_backend (external) --> deepl_nginx:8000
    
[authentik-server/worker]
    |
    +---> authentik_db (internal) ----> postgres, redis
```

## 🚀 Quick Start

### 1. Create External Networks

The backend networks are shared with upstream application containers and must be created manually:

```bash
docker network create itsm_backend
docker network create deepl_backend
```

Note: The `proxy` network is automatically created by Docker Compose.

### 2. Configure Environment

Use the initialization script to create `.env` with secure random values:

```bash
chmod +x scripts/init-env.sh
./scripts/init-env.sh
```

This script will:
- Copy `.env.example` to `.env`
- Generate secure random passwords for `POSTGRES_PASSWORD` and `AUTHENTIK_SECRET_KEY`
- Optionally prompt for domain names and SMTP configuration

Alternatively, configure manually:
```bash
cp .env.example .env
nano .env
# Generate: AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60)
```

### 3. Choose TLS Mode

#### Option A: Provided Certificates (Default)

**A1. Using Self-Signed Certificates** (development/testing only)

```bash
# Generate self-signed certificates automatically
chmod +x scripts/init-selfsigned.sh
./scripts/init-selfsigned.sh

# Start stack
docker compose up -d
```

**WARNING:** Self-signed certificates show browser warnings. Not for production!

**A2. Using Real Certificates** (production)

```bash
# Create certificate directory and place your certificates
mkdir -p certs
# Copy your certificates:
# certs/fullchain.pem - Full certificate chain
# certs/privkey.pem - Private key

# Generate DH parameters (recommended)
openssl dhparam -out nginx/dhparam.pem 2048

# Start stack
docker compose up -d
```

#### Option B: Let's Encrypt (Automated)

1. Ensure your domains are configured in `.env`:
```bash
# The init-letsencrypt.sh script automatically reads these:
DOMAIN_AUTH=auth.yourdomain.com
DOMAIN_ITSM=itsm.yourdomain.com
DOMAIN_DEEPL=deepl.yourdomain.com
LETSENCRYPT_EMAIL=admin@yourdomain.com
```

2. Ensure DNS records point to your server

3. Run initialization script:
```bash
chmod +x scripts/init-letsencrypt.sh
./scripts/init-letsencrypt.sh
```

4. Start full stack with Let's Encrypt:
```bash
docker compose -f docker-compose.yml -f docker-compose.letsencrypt.yml up -d
```

## 🔧 Configuration

### Update Domains

Domains are configured via environment variables in `.env`:

```bash
# Edit .env file
DOMAIN_AUTH=auth.yourdomain.com
DOMAIN_ITSM=itsm.yourdomain.com
DOMAIN_DEEPL=deepl.yourdomain.com

# Authentik needs to know its own URL
AUTHENTIK_HOST=https://auth.yourdomain.com
AUTHENTIK_HOST_BROWSER=https://auth.yourdomain.com
AUTHENTIK_COOKIE_DOMAIN=.yourdomain.com
```

These variables are automatically substituted into nginx configs at container startup. No need to edit nginx config files directly!

**Important Configuration Notes:**
- `AUTHENTIK_HOST` must match `DOMAIN_AUTH` for the outpost to work correctly
- `AUTHENTIK_COOKIE_DOMAIN` must use a leading dot (`.yourdomain.com`) for cross-subdomain SSO
- The `init-letsencrypt.sh` script automatically reads domains from `.env` - no need to edit the script

#### Domain Selection for Local Testing

**⚠️ Cookie Compatibility Issue**: When testing locally, domain choice affects cross-subdomain SSO:

- **`.local` domains (Recommended)**: Browser-friendly for cookie sharing
  - Example: `auth.jade.local`, `itsm.jade.local`, `translation.jade.local`
  - Cookie domain: `.jade.local`
  - ✅ Works reliably for cross-subdomain authentication
  
- **`.test` domains**: May cause cookie rejection in some browsers
  - Browsers may reject cookies with `.test` cookie domain due to security policies
  - Symptoms: Login works but session doesn't persist across subdomains
  - ❌ Not recommended for SSO testing

**For Local Testing**:
1. Use `.local` domains in your `.env`:
   ```bash
   DOMAIN_AUTH=auth.jade.local
   AUTHENTIK_COOKIE_DOMAIN=.jade.local
   ```

2. Add to hosts file:
   ```bash
   # Linux/Mac: /etc/hosts
   # Windows: C:\Windows\System32\drivers\etc\hosts
   # WSL2: Use Windows hosts file (C:\Windows\System32\drivers\etc\hosts on Windows side)
   
   127.0.0.1 auth.jade.local itsm.jade.local translation.jade.local
   ```

3. Regenerate certificates with new domains:
   ```bash
   ./scripts/init-selfsigned.sh
   # Enter: auth.jade.local,itsm.jade.local,translation.jade.local
   ```

4. Restart stack:
   ```bash
   docker compose down && docker compose up -d
   ```

## ⚙️ Authentik Initial Setup

**Official Documentation**: [Authentik Installation Guide](https://docs.goauthentik.io/docs/installation/)

### Why Authentik?

✅ **Excellent SAML Support**: Both SAML Service Provider and Identity Provider  
✅ **IT-Friendly**: Web-based admin UI, no config files  
✅ **Django Integration**: Perfect for Django apps with forward-auth headers  
✅ **Active Development**: Modern, well-maintained, Docker-native  
✅ **Flexible**: Supports LDAP, OAuth, SAML, and more

**Alternative Solutions** (if Authentik doesn't fit your needs):
- **Keycloak**: More mature, excellent SAML, but heavier (Java-based, higher resource usage)
- **Authelia**: Lighter weight, simpler, but less feature-rich (limited SAML)
- **oauth2-proxy**: Very simple forwarding proxy (requires external IdP, no SAML SP mode)

### Step 1: Create Admin Account

Once the stack is running, create your admin account:

1. **Navigate to the initial setup URL**:
   ```
   https://auth.localhost/if/flow/initial-setup/
   ```
   *(Replace `auth.localhost` with your actual `DOMAIN_AUTH` value)*

2. **Fill in the setup form**:
   - **Email**: Your administrator email
   - **Username**: Choose admin username (e.g., `admin`)
   - **Password**: Strong password (save this!)

3. **Click "Continue"** to complete setup

4. **Login to Authentik**:
   - URL: `https://auth.localhost/`
   - Use the credentials you just created

**Note**: The initial setup flow works correctly once cookie domains are properly configured (see Domain Configuration section above).

### Step 2: Configure Forward-Auth Providers

**Reference**: [Authentik Proxy Provider Documentation](https://docs.goauthentik.io/docs/providers/proxy/forward_auth)

After logging in to Authentik admin interface, configure authentication for your applications:

#### For ITSM Application

1. **Create Provider**:
   - Admin Panel → Applications → Providers → Create
   - **Type**: Proxy Provider
   - **Name**: ITSM Proxy
   - **Authorization flow**: default-provider-authorization-implicit-consent
   - **Mode**: Forward auth (single application)
   - **External host**: `https://itsm.localhost` *(use your DOMAIN_ITSM)*
   - Click **Finish**

2. **Create Application**:
   - Admin Panel → Applications → Applications → Create
   - **Name**: ITSM
   - **Slug**: itsm
   - **Provider**: Select "ITSM Proxy"
   - **Launch URL**: `https://itsm.localhost`
   - Click **Create**

#### For Translation/DeepL Application

Repeat the same process:

1. **Create Provider**:
   - **Name**: Translation Proxy
   - **External host**: `https://translation.localhost` *(use your DOMAIN_DEEPL)*
   
2. **Create Application**:
   - **Name**: Translation
   - **Slug**: translation
   - **Provider**: Translation Proxy
   - **Launch URL**: `https://translation.localhost`

#### Create Outpost (Connects nginx to Authentik)

1. Admin Panel → Outposts → Outposts → Create
2. **Name**: nginx-forward-auth
3. **Type**: Proxy
4. **Integration**: Local Docker connection (default)
5. **Applications**: Select both "ITSM" and "Translation"
6. Click **Create**

**Verify**: Outpost should show "Healthy" status after creation.

### Step 3: Test Authentication

#### Test ITSM (Mixed Auth)

1. **Public path** (no auth required):
   - Navigate to: `https://itsm.localhost/`
   - Should access directly without login

2. **Protected path** (auth required):
   - Navigate to: `https://itsm.localhost/admin/`
   - Should redirect to Authentik login
   - Login with your admin credentials
   - Should redirect back to `/admin/`

#### Test Translation (Full Auth)

1. Navigate to: `https://translation.localhost/`
2. Should redirect to Authentik login
3. Login if not already authenticated
4. Should access the application with SSO session

**Cross-subdomain SSO**: After logging in on one domain, other subdomains should automatically authenticate without prompting for credentials again (thanks to shared cookie domain).

### Step 4: Configure SAML Federation (Optional)

**Reference**: [Authentik SAML Source Documentation](https://docs.goauthentik.io/docs/sources/saml/)

To integrate with an external Shibboleth IdP:

#### In Authentik

1. Admin Panel → Federation & Social login → Sources → Create
2. **Type**: SAML Source
3. **Name**: Shibboleth IdP
4. **Slug**: shibboleth
5. **Service Provider Binding**: Post
6. **SSO URL**: Your Shibboleth IdP's SSO endpoint
7. **SLO URL**: Your Shibboleth IdP's logout endpoint (optional)
8. **Issuer**: Your Shibboleth IdP's entity ID
9. **IdP Metadata**: Paste XML or provide metadata URL
10. Click **Create**

#### In Shibboleth

Provide your Shibboleth administrator with Authentik's SP metadata:

**Metadata URL**: `https://auth.localhost/api/v3/sources/saml/shibboleth/metadata/`

They need to:
1. Register Authentik as a Service Provider
2. Configure attribute release (eduPersonPrincipalName, email, displayName)
3. Add Authentik's entity ID to allowed SPs

#### Test SAML Login

1. Go to `https://auth.localhost`
2. Click "Sign in with Shibboleth IdP"
3. Should redirect to your Shibboleth login page
4. After authentication, redirected back to Authentik

### Additional Configuration

For more advanced setup:
- **User directories**: Configure LDAP, SCIM, or other user sources
- **Groups and permissions**: Set up access control policies
- **Custom flows**: Customize login, consent, and enrollment processes
- **Email**: Configure SMTP for password resets and notifications
- **MFA/2FA**: Enable multi-factor authentication for enhanced security

**Full Documentation**: https://docs.goauthentik.io/

## 🔧 Advanced Configuration

### ITSM Protected Paths

To protect additional paths, edit `nginx/conf.d/itsm.conf`:

```nginx
# Add new protected location
location /your/protected/path/ {
    auth_request /auth-verify;
    error_page 401 = @error_auth_itsm;
    
    auth_request_set $auth_resp_x_authentik_username $upstream_http_x_authentik_username;
    auth_request_set $auth_resp_x_authentik_email $upstream_http_x_authentik_email;
    # ... rest of auth configuration
}
```

### Header Forwarding

Authenticated requests forward user identity:
- `X-Remote-User` - Username from Authentik
- `X-Remote-Email` - Email from Authentik

**Security:** nginx always clears client-provided identity headers to prevent spoofing.

## 🔒 Security Features

### TLS Hardening
- TLS 1.2+ only (TLS 1.0/1.1 disabled)
- Modern cipher suites (Mozilla Modern profile)
- HSTS enabled (1 year, includeSubDomains)
- OCSP stapling
- Perfect forward secrecy (DH params)

### nginx Hardening
- Server tokens disabled (hide version)
- Security headers (X-Frame-Options, CSP, etc.)
- Rate limiting (per-IP)
- Timeout configuration
- Client max body size limits

### Network Segmentation
- Internal networks isolated from internet
- Only nginx publishes ports to host
- Service-specific network separation
- No direct database access from internet

### Authentication
- Forward-auth integration with Authentik
- Header spoofing prevention
- Secure session handling
- Cookie domain scoping

## 📊 Monitoring & Logs

### View Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f nginx
docker compose logs -f authentik-server

# nginx access logs (inside container)
docker compose exec nginx tail -f /var/log/nginx/access.log

# nginx error logs
docker compose exec nginx tail -f /var/log/nginx/error.log
```

### Health Checks

```bash
# Check service health
docker compose ps

# Test nginx config
docker compose exec nginx nginx -t

# Check certificate expiry (Let's Encrypt)
docker compose exec nginx openssl x509 -in /etc/nginx/certs/live/auth.example.org/fullchain.pem -noout -dates
```

### Monitoring Endpoints

- nginx health: `http://localhost/health` (internal only)
- Authentik health: `https://auth.example.org/-/health/live/`

## 🔄 Maintenance

### Update Services

```bash
# Pull latest images
docker compose pull

# Recreate containers
docker compose up -d

# Or for Let's Encrypt mode
docker compose -f docker-compose.yml -f docker-compose.letsencrypt.yml up -d
```

### Backup Database

```bash
# Backup PostgreSQL
docker compose exec postgres pg_dump -U authentik authentik > backup_$(date +%Y%m%d).sql

# Restore
cat backup_20260108.sql | docker compose exec -T postgres psql -U authentik authentik
```

### Certificate Renewal (Let's Encrypt)

Automatic renewal runs every 12 hours. Manual renewal:

```bash
# Force renewal
docker compose -f docker-compose.yml -f docker-compose.letsencrypt.yml run --rm certbot renew --force-renewal

# Reload nginx
docker compose exec nginx nginx -s reload
```

### Reload nginx Config

After modifying nginx configs:

```bash
# Test configuration
docker compose exec nginx nginx -t

# Reload (zero-downtime)
docker compose exec nginx nginx -s reload
```

## 🛠️ Troubleshooting

### nginx Won't Start

```bash
# Check configuration syntax
docker compose exec nginx nginx -t

# Check logs
docker compose logs nginx

# Common issues:
# - Missing certificate files
# - Invalid nginx syntax
# - Port conflicts (80/443 already in use)
```

### Authentication Not Working

1. **Verify Authentik is running:**
   ```bash
   docker compose ps authentik-server
   curl -k https://auth.localhost/-/health/live/
   ```

2. **Verify Authentik outpost configuration:**
   - Check Authentik admin UI → Outposts → nginx-forward-auth
   - Should show "Healthy" status
   - Ensure proxy providers are configured correctly
   - Verify external host matches your domain exactly

3. **Check auth_request endpoint:**
   ```bash
   # Should return 401 or 302 (not 500/502)
   curl -I https://itsm.localhost/admin/
   ```

4. **Check nginx logs for auth errors:**
   ```bash
   docker compose logs nginx | grep auth
   ```

### Cookie/Session Issues (Login Doesn't Persist)

**Problem**: Login works on `auth.localhost` but session doesn't persist when accessing `itsm.localhost`

**Cause**: Cookie domain configuration issue

**Solution**:

1. **Check cookie domain in `.env`:**
   ```bash
   cat .env | grep AUTHENTIK_COOKIE_DOMAIN
   # Should show: AUTHENTIK_COOKIE_DOMAIN=.localhost (or .jade.local for testing)
   ```

2. **For local testing, use `.local` domains instead of `.test`:**
   - `.local` domains: Browser-friendly for cross-subdomain cookies ✅
   - `.test` domains: May be rejected by browsers ❌

3. **Verify cookie is being set:**
   - Open browser DevTools → Application/Storage → Cookies
   - Should see `authentik_session` cookie with domain `.localhost` (or your domain)

4. **Restart Authentik after changing cookie domain:**
   ```bash
   docker compose restart authentik-server authentik-worker
   ```

### Cannot Access Upstream Apps

1. **Verify external networks exist:**
   ```bash
   docker network ls | grep -E "itsm_backend|deepl_backend"
   ```

2. **Verify upstream containers are on correct networks:**
   ```bash
   docker network inspect itsm_backend
   # Should show itsm_nginx container
   ```

3. **Test connectivity from nginx:**
   ```bash
   docker compose exec nginx wget -O- http://itsm_nginx:8000
   ```

### Authentik Admin UI Returns 502 or Connection Error

1. **Check Authentik is running:**
   ```bash
   docker compose ps authentik-server
   docker compose logs authentik-server
   ```

2. **Check nginx can reach authentik-server:**
   ```bash
   docker compose exec nginx wget -O- http://authentik-server:9000/-/health/live/
   # Should return "healthy"
   ```

3. **Verify nginx config was generated correctly:**
   ```bash
   docker compose exec nginx cat /etc/nginx/conf.d/authentik.conf | grep server_name
   # Should show your actual domain, not ${DOMAIN_AUTH}
   ```

4. **If environment variables weren't substituted:**
   ```bash
   # Verify .env file has correct values
   cat .env | grep DOMAIN_
   
   # Restart nginx to regenerate configs
   docker compose restart nginx
   ```

### Let's Encrypt Certificate Failure

1. **Verify DNS:**
   ```bash
   nslookup itsm.example.org
   # Should point to your server IP
   ```

2. **Check port accessibility:**
   ```bash
   # From external machine
   curl http://your-server-ip/.well-known/acme-challenge/test
   ```

3. **Check rate limits:**
   - Let's Encrypt: 5 failures per hour per domain
   - Use staging mode for testing (set `STAGING=1` in init script)

4. **Review certbot logs:**
   ```bash
   docker compose logs certbot
   ```

## 📁 File Structure

```
0_nginx_authentik/
├── docker-compose.yml              # Main stack definition
├── docker-compose.letsencrypt.yml  # Let's Encrypt overlay
├── .env.example                    # Environment template
├── .env                           # Your configuration (create from .env.example)
├── .gitignore                      # Git ignore rules
├── README.md                      # This file
│
├── nginx/
│   ├── nginx.conf                 # Main nginx config
│   ├── docker-entrypoint.sh       # Env var substitution script
│   ├── dhparam.pem               # DH parameters (generate)
│   └── conf.d/
│       ├── authentik.conf.template  # auth.example.org (template)
│       ├── itsm.conf.template       # itsm.example.org (template)
│       ├── deepl.conf.template      # deepl.example.org (template)
│       └── *.conf                   # Generated at runtime (gitignored)
│
├── certs/                        # TLS certificates (Mode A)
│   ├── fullchain.pem            # Full cert chain
│   └── privkey.pem              # Private key
│
└── scripts/
    ├── init-env.sh               # Environment initialization (generates secrets)
    ├── init-selfsigned.sh        # Self-signed certificate generator (dev/test)
    └── init-letsencrypt.sh       # Let's Encrypt initialization (production)
```

## 🔐 Security Checklist

Before deploying to production:

- [ ] Change all default passwords in `.env`
- [ ] Generate strong `AUTHENTIK_SECRET_KEY` (60+ chars)
- [ ] Use strong `POSTGRES_PASSWORD` (20+ chars)
- [ ] Update domains from `example.org` to your actual domains
- [ ] Generate DH parameters (`openssl dhparam -out nginx/dhparam.pem 2048`)
- [ ] Verify HSTS is acceptable for your use case (cannot be easily undone)
- [ ] Configure Authentik email settings for password resets
- [ ] Set up regular database backups
- [ ] Review and adjust rate limiting as needed
- [ ] Test authentication flow thoroughly
- [ ] Verify header spoofing protection is working
- [ ] Enable firewall (allow only 22, 80, 443)
- [ ] Set up monitoring/alerting
- [ ] Review nginx logs regularly
- [ ] Keep services updated (security patches)

## 📚 Additional Resources

- [Authentik Documentation](https://docs.goauthentik.io/)
- [Authentik nginx Proxy Provider](https://docs.goauthentik.io/docs/providers/proxy/)
- [nginx auth_request Module](http://nginx.org/en/docs/http/ngx_http_auth_request_module.html)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- **[GIT_GUIDE.md](GIT_GUIDE.md)** - Git quick reference for Mercurial users

## 📝 License

This configuration is provided as-is for your use. Modify as needed for your environment.

## ⚠️ Important Notes

1. **HSTS Warning:** Once HSTS is enabled and browsers cache it, you cannot easily switch back to HTTP. Ensure HTTPS is working properly before enabling HSTS in production.

2. **External Networks:** The `itsm_backend` and `deepl_backend` networks must be created manually and shared with the respective application containers.

3. **Authentik Initial Setup:** Use the `/if/flow/initial-setup/` URL to create your admin account after first startup. Ensure cookie domains are configured correctly (use `.local` domains for local testing, not `.test`).

4. **Production Deployment:** This is a secure baseline configuration. Additional hardening may be needed based on your specific requirements and threat model.

5. **Certificate Renewals:** Let's Encrypt certificates expire after 90 days. The certbot container handles automatic renewal, but monitor logs to ensure it works correctly.
