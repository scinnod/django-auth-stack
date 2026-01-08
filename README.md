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

1. Create certificate directory and place certificates:
```bash
mkdir -p certs
# Copy your certificates:
# certs/fullchain.pem - Full certificate chain
# certs/privkey.pem - Private key
```

2. Generate DH parameters (recommended):
```bash
openssl dhparam -out nginx/dhparam.pem 2048
```

3. Start stack:
```bash
docker compose up -d
```

#### Option B: Let's Encrypt (Automated)

1. Update domains in `scripts/init-letsencrypt.sh`:
```bash
nano scripts/init-letsencrypt.sh
# Modify DOMAINS array with your actual domains
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

Replace `example.org` with your actual domains in:
- `nginx/conf.d/authentik.conf` - `server_name auth.yourdomain.com;`
- `nginx/conf.d/itsm.conf` - `server_name itsm.yourdomain.com;`
- `nginx/conf.d/deepl.conf` - `server_name deepl.yourdomain.com;`
- `.env` - `DOMAIN_*` variables
- `scripts/init-letsencrypt.sh` - `DOMAINS` array (if using Let's Encrypt)

### Authentik Configuration

1. Access Authentik UI: `https://auth.example.org`

2. Initial setup wizard will run on first access

3. Create authentication flows and providers:
   - Create a **Proxy Provider** for each application (ITSM, DeepL)
   - Configure **Forward Auth (single application)** mode
   - Set **External host** to your application domain
   - Configure **Authorization flow** (authentication requirements)

4. Create **Outpost** for nginx integration:
   - Type: **Proxy**
   - Configuration: Select your proxy providers
   - Integration: Note the outpost token if needed

5. **CRITICAL**: Update nginx configs if Authentik endpoints differ:
   - Default auth endpoint: `/outpost.goauthentik.io/auth/nginx`
   - Default login endpoint: `/outpost.goauthentik.io/start`
   - Verify in Authentik documentation for your version

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
   curl -k https://auth.example.org/-/health/live/
   ```

2. **Check auth_request endpoint:**
   ```bash
   # Should return 401 or 302 (not 500/502)
   curl -I https://itsm.example.org/admin/
   ```

3. **Verify Authentik outpost configuration:**
   - Check Authentik admin UI > Outposts
   - Ensure proxy provider is configured
   - Verify external host matches your domain

4. **Check nginx logs for auth errors:**
   ```bash
   docker compose logs nginx | grep auth
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
│   ├── dhparam.pem               # DH parameters (generate)
│   └── conf.d/
│       ├── authentik.conf        # auth.example.org vhost
│       ├── itsm.conf             # itsm.example.org vhost (mixed auth)
│       └── deepl.conf            # deepl.example.org vhost (full auth)
│
├── certs/                        # TLS certificates (Mode A)
│   ├── fullchain.pem            # Full cert chain
│   └── privkey.pem              # Private key
│
└── scripts/
    ├── init-env.sh               # Environment initialization (generates secrets)
    └── init-letsencrypt.sh       # Let's Encrypt initialization
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

3. **Authentik Configuration:** After first startup, complete the Authentik setup wizard and configure proxy providers for forward-auth integration.

4. **Production Deployment:** This is a secure baseline configuration. Additional hardening may be needed based on your specific requirements and threat model.

5. **Certificate Renewals:** Let's Encrypt certificates expire after 90 days. The certbot container handles automatic renewal, but monitor logs to ensure it works correctly.
