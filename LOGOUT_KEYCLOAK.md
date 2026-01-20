# Keycloak Logout Configuration

## Overview
This stack implements **OIDC RP-Initiated Logout**, which ensures that when users click "Logout" in your Django application, they are logged out of both:
1. **Django session** (application-level)
2. **Keycloak SSO session** (identity provider level)

This prevents users from immediately re-logging in with a single click after logout.

## How It Works

## OAuth2-proxy Configuration

### Implementation Status

✅ **OIDC logout is already configured** in this stack's `docker-compose.yml`.

The OAuth2-proxy service includes all required parameters for OIDC RP-Initiated Logout:

```yaml
# Key parameters for OIDC logout (from docker-compose.yml):
--provider=oidc
--oidc-issuer-url=http://keycloak:8080/realms/${KEYCLOAK_REALM}
--redirect-url=https://${DOMAIN_AUTH}/oauth2/callback
--pass-user-headers=true          # Required for Django integration
--set-xauthrequest=true            # Required for nginx auth_request
--skip-provider-button=true        # Direct to Keycloak login
--whitelist-domain=${OAUTH2_PROXY_COOKIE_DOMAIN}  # Enables logout redirects
```

### Required Environment Variables

Ensure these are set in your `.env` file (created by `scripts/init-env.sh`):

```bash
DOMAIN_AUTH=auth.example.org               # Your Keycloak domain
OAUTH2_PROXY_COOKIE_DOMAIN=.example.org   # Cookie domain (with leading dot)
KEYCLOAK_REALM=master                      # Your Keycloak realm name
OAUTH2_PROXY_CLIENT_ID=your-client-id     # From Keycloak client config
OAUTH2_PROXY_CLIENT_SECRET=your-secret    # From Keycloak client config
```

### OIDC Logout Flow

When a user visits `/oauth2/sign_out?rd=/`, the following happens:

1. **Django logout view** clears the Django session
2. **Django** redirects to `/oauth2/sign_out?rd=/`
3. **OAuth2-proxy** clears its own session cookie
4. **OAuth2-proxy** redirects to Keycloak's `end_session_endpoint` with:
   - `id_token_hint` - the user's ID token
   - `post_logout_redirect_uri` - where to redirect after logout (from `rd` parameter)
5. **Keycloak** terminates the user's SSO session
6. **Keycloak** redirects back to the `post_logout_redirect_uri` (typically `/`)

Result: User is fully logged out and must re-enter credentials to log back in.

## Django Configuration

The Django app is already configured correctly in `views.py`:

```python
if settings.IS_PRODUCTION:
    # Redirects to /oauth2/sign_out?rd=/
    # OAuth2-proxy will handle the full OIDC logout
    return redirect('/oauth2/sign_out?rd=/')
```

## Keycloak Client Configuration

### Required Settings

For each OIDC client in Keycloak, configure the following:

1. **Access Type/Client Authentication**: `confidential` (ON)
   - Required for client secret authentication

2. **Standard Flow Enabled**: `ON`
   - Enables authorization code flow

3. **Valid Redirect URIs**: 
   ```
   https://${DOMAIN_AUTH}/oauth2/callback
   https://${DOMAIN_ITSM}/*
   https://${DOMAIN_DEEPL}/*
   ```
   Replace with your actual domains from `.env`

4. **Valid Post Logout Redirect URIs**: 
   ```
   https://${DOMAIN_ITSM}/*
   https://${DOMAIN_DEEPL}/*
   https://${DOMAIN_AUTH}/*
   ```
   **Critical**: Without these, logout redirects will fail

5. **Web Origins**: `+` (allows all valid redirect URIs)

### Example for ITSM Client

If your `.env` has:
```bash
DOMAIN_AUTH=auth.example.org
DOMAIN_ITSM=itsm.example.org
```

Then configure:
- **Client ID**: `itsm-client` (matches `OAUTH2_PROXY_CLIENT_ID`)
- **Valid Redirect URIs**: 
  - `https://auth.example.org/oauth2/callback`
  - `https://itsm.example.org/*`
- **Valid Post Logout Redirect URIs**:
  - `https://itsm.example.org/*`

## Testing the Logout Flow

### Step-by-Step Verification

1. **Log in to your application**
   - Access a protected Django page (e.g., `https://itsm.example.org/dashboard/`)
   - You should be redirected to Keycloak and prompted to log in
   - After login, you're redirected back to the protected page

2. **Click "Logout" in Django**
   - This should redirect to `/oauth2/sign_out?rd=/`
   - You should briefly see a Keycloak logout page (or redirect immediately)
   - You should end up at the homepage (`/`)

3. **Verify full logout**
   - Try to access the protected page again
   - You should be redirected to Keycloak login
   - **Important**: You should see the Keycloak login form, NOT be automatically logged in

4. **Check browser cookies**
   - Open browser DevTools → Application → Cookies
   - After logout, these should be cleared:
     - `_oauth2_proxy` (OAuth2-proxy session)
     - `KEYCLOAK_SESSION` (Keycloak session)
     - Django's `sessionid` cookie

### Troubleshooting

If you're still automatically logged in after logout:

```bash
# Check OAuth2-proxy logs
sudo docker logs edge_oauth2_proxy --tail 50

# Look for:
# - "OIDC logout" or "end_session" redirects
# - "Error" messages related to logout

# Check Keycloak logs
sudo docker logs edge_keycloak --tail 50
```

## Common Issues

### Issue: Still automatically logged in after logout

**Symptoms**: After clicking logout, accessing protected pages doesn't require re-entering credentials.

**Diagnosis**:
```bash
# Check if OAuth2-proxy is attempting OIDC logout
sudo docker logs edge_oauth2_proxy 2>&1 | grep -i "end_session\|logout"

# Check Keycloak sessions
# Access Keycloak Admin → Realm → Sessions
# Sessions should be empty after logout
```

**Solutions**:
1. Verify `OAUTH2_PROXY_COOKIE_DOMAIN` in `.env` matches your domain
2. Check Keycloak's "Valid Post Logout Redirect URIs" includes your domain
3. Ensure `--whitelist-domain` is set correctly in docker-compose.yml
4. Restart OAuth2-proxy: `sudo docker restart edge_oauth2_proxy`

### Issue: Redirect loop after logout

**Symptoms**: After logout, browser keeps redirecting between pages.

**Solutions**:
1. Check Keycloak's "Valid Post Logout Redirect URIs":
   - Must include `https://your-domain/*`
   - Wildcards are allowed
2. Verify `--whitelist-domain=${OAUTH2_PROXY_COOKIE_DOMAIN}` is set
3. Clear browser cookies completely and try again

### Issue: "Invalid redirect URI" error during logout

**Symptoms**: Keycloak shows error: "Invalid parameter: redirect_uri"

**Solutions**:
1. Add your domain to Keycloak client's "Valid Post Logout Redirect URIs"
2. Use wildcards: `https://itsm.example.org/*`
3. Ensure the `rd` parameter in `/oauth2/sign_out?rd=/` points to a valid URI

### Issue: Can't log back in after logout

**Symptoms**: After logout, login fails or shows errors.

**Solutions**:
1. Check Keycloak's "Valid Redirect URIs" includes:
   - `https://${DOMAIN_AUTH}/oauth2/callback`
2. Verify OAuth2-proxy `--redirect-url` matches Keycloak configuration
3. Check cookie settings:
   ```bash
   # Ensure these are set correctly in .env
   OAUTH2_PROXY_COOKIE_DOMAIN=.example.org  # Note the leading dot
   ```

## Important Considerations

### Cross-Application SSO Impact

⚠️ **Important**: When using OIDC RP-Initiated Logout, logging out of one application will terminate the **entire Keycloak SSO session**.

**This means**:
- User logs out of ITSM → Also logged out of DeepL (and any other apps in the same realm)
- This is standard SSO behavior (true single sign-on)

**If you need independent logout**:
- Use separate Keycloak realms for each application
- Or only clear Django + OAuth2-proxy sessions (remove Keycloak logout)
  - Change Django view to: `return redirect('/oauth2/sign_out?rd=/')` (already implemented)
  - Remove `--whitelist-domain` from OAuth2-proxy (partial logout only)

### Security vs Convenience Trade-off

- ✅ **Full OIDC Logout (current)**: More secure, complete session termination
  - Users must re-enter credentials after logout
  - Recommended for sensitive/internal applications (ITSM)
  
- ❌ **Partial Logout**: Less secure, only clears application cookies
  - Users can re-login with one click (Keycloak session persists)
  - Not recommended but faster for development

## References

- [OAuth2-proxy OIDC Configuration](https://oauth2-proxy.github.io/oauth2-proxy/configuration/providers/oidc)
- [OIDC RP-Initiated Logout](https://openid.net/specs/openid-connect-rpinitiated-1_0.html)
- [Keycloak OIDC Logout](https://www.keycloak.org/docs/latest/securing_apps/#logout)
- [This Stack's Django Integration](keycloak/DJANGO_INTEGRATION.md#5-logout-handling)
