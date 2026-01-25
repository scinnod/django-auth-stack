<!--
SPDX-FileCopyrightText: 2024-2026 David Kleinhans, Jade University of Applied Sciences
SPDX-License-Identifier: Apache-2.0
-->

# Keycloak Logout Configuration

## Overview
This stack implements **OIDC RP-Initiated Logout**, which ensures that when users click "Logout" in your Django application, they are logged out of both:
1. **Django session** (application-level)
2. **Keycloak SSO session** (identity provider level)

This prevents users from immediately re-logging in with a single click after logout.

## How It Works

## Nginx-Based OIDC Logout (OAuth2-proxy v7.6.0)

### The Challenge

OAuth2-proxy v7.6.0 does **not** implement OIDC RP-Initiated Logout. When you
call `/oauth2/sign_out`, it only:
1. Clears the oauth2-proxy cookie
2. Redirects to the `rd` parameter

It does **not** redirect to Keycloak's `end_session_endpoint`, so the Keycloak
session persists. Users get re-authenticated automatically without entering
credentials again.

### Our Solution: Nginx-Handled Logout

Instead of relying on oauth2-proxy, nginx handles the full logout flow. This is configured in the service pattern templates (`service-pattern-a.conf.template` and `service-pattern-b.conf.template`):

```nginx
# Example from service-pattern-a.conf.template (Pattern B uses identical logout handling)
location = /oauth2/sign_out {
    # Clear the oauth2-proxy cookie
    add_header Set-Cookie "_oauth2_proxy=; Path=/; Domain=${OAUTH2_PROXY_COOKIE_DOMAIN}; HttpOnly; Secure; SameSite=Lax; Max-Age=0" always;
    
    # Redirect to Keycloak's end_session_endpoint
    # __SERVICE_DOMAIN__ is replaced with the actual service domain during startup
    return 302 https://${DOMAIN_AUTH}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/logout?post_logout_redirect_uri=https://__SERVICE_DOMAIN__/&client_id=${OAUTH2_PROXY_CLIENT_ID};
}
```

This approach:
- ✅ nginx clears the oauth2-proxy session cookie
- ✅ nginx redirects to Keycloak's external logout URL
- ✅ Keycloak terminates the SSO session
- ⚠️ Without `id_token_hint`, Keycloak shows a logout confirmation page (secure and expected)

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

When a user visits `/oauth2/sign_out` on any configured service, the following happens:

1. **Django logout view** clears the Django session
2. **Django** redirects to `/oauth2/sign_out`
3. **nginx** clears the oauth2-proxy cookie (`_oauth2_proxy`)
4. **nginx** redirects (302) to Keycloak's `end_session_endpoint` with:
   - `client_id` - identifies the application
   - `post_logout_redirect_uri` - where to redirect after logout (service-specific)
5. **Keycloak** shows logout confirmation (because no `id_token_hint`)
6. **User clicks "Logout"** on Keycloak page
7. **Keycloak** terminates the SSO session
8. **Keycloak** redirects back to `post_logout_redirect_uri` (the service's homepage)

Result: User is fully logged out and must re-enter credentials to log back in.

**Note:** This flow is identical for both authentication patterns (Django-Controlled and Full nginx-Level). The only difference is the `post_logout_redirect_uri` which points to the respective service's homepage.

### Note on Logout Confirmation

Without `id_token_hint`, Keycloak displays a confirmation page asking the user
to confirm logout. This is **intentional security behavior** - it prevents
logout CSRF attacks. Users simply click "Logout" to complete the process.

## Django Configuration

Your Django logout view should redirect to the nginx-handled sign_out endpoint:

```python
from django.contrib.auth import logout
from django.shortcuts import redirect

def logout_view(request):
    """Logout from both Django and Keycloak SSO."""
    # Clear Django session
    logout(request)
    
    # Redirect to nginx sign_out endpoint
    # nginx clears oauth2-proxy cookie and redirects to Keycloak logout
    return redirect('/oauth2/sign_out')
```

**Note**: The `rd` parameter is no longer needed - nginx handles the redirect to Keycloak
and the `post_logout_redirect_uri` is configured in the nginx template.

See [Django Integration Guide](django-integration.md#5-logout-handling) for complete implementation details.

## Keycloak Client Configuration

### Quick Checklist

Before testing logout, ensure you've configured in Keycloak Admin Console:

- [ ] ✅ **Valid Post Logout Redirect URIs** - `https://your-domain/*` (see detailed steps below)
- [ ] ✅ **Valid Redirect URIs** - Include `https://auth.domain/oauth2/callback`

**Without these, logout will fail or login will break.**

### Required Settings

For each OIDC client in Keycloak, configure the following:

1. **Access Type/Client Authentication**: `confidential` (ON)
   - Required for client secret authentication

2. **Standard Flow Enabled**: `ON`
   - Enables authorization code flow

3. **Valid Redirect URIs**: 
   ```
   https://${DOMAIN_AUTH}/oauth2/callback
   https://service1.example.org/*
   https://service2.example.org/*
   ```
   Replace with your actual service domains from `.env`

4. **Valid Post Logout Redirect URIs**: 
   ```
   https://service1.example.org/*
   https://service2.example.org/*
   https://${DOMAIN_AUTH}/*
   ```
   **⚠️ CRITICAL**: Without these URIs configured, **logout will fail** with "Invalid redirect URI" error.
   
   **Steps to configure:**
   1. Go to Keycloak Admin Console → Your Realm → Clients → Your Client
   2. Scroll down to **Login settings** section
   3. Find **Valid post logout redirect URIs** field
   4. Add each domain where users can be redirected after logout:
      - `https://myapp.example.org/*` (for each configured service)
      - Or use `*` to allow any redirect (less secure)
   5. Click **Save**

5. **Web Origins**: `+` (allows all valid redirect URIs)

### Example Client Configuration

If your `.env` has:
```bash
DOMAIN_AUTH=auth.example.org
SERVICE_1_DOMAIN=myapp.example.org
```

Then configure:
- **Client ID**: `myapp-client` (matches `OAUTH2_PROXY_CLIENT_ID`)
- **Valid Redirect URIs**: 
  - `https://auth.example.org/oauth2/callback`
  - `https://myapp.example.org/*`
- **Valid Post Logout Redirect URIs**:
  - `https://myapp.example.org/*`

## Testing the Logout Flow

### Step-by-Step Verification

1. **Log in to your application**
   - Access a protected Django page (e.g., `https://myapp.example.org/dashboard/`)
   - You should be redirected to Keycloak and prompted to log in
   - After login, you're redirected back to the protected page

2. **Click "Logout" in Django**
   - This should redirect to `/oauth2/sign_out`
   - nginx clears the oauth2-proxy cookie and redirects to Keycloak
   - Keycloak shows a logout confirmation page (click "Logout")
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
1. Add your domain to Keycloak client's "Valid Post Logout Redirect URIs":
   - `https://myapp.example.org/*` (for each configured service)
2. Use wildcards as shown above
3. Verify the `post_logout_redirect_uri` in the nginx template matches a configured URI

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
- User logs out of ServiceA → Also logged out of ServiceB (and any other apps in the same realm)
- This is standard SSO behavior (true single sign-on)

**If you need independent logout**:
- Use separate Keycloak realms for each application
- Or only clear Django + OAuth2-proxy sessions (remove Keycloak logout)
  - Modify the nginx `/oauth2/sign_out` location to only clear the cookie without redirecting to Keycloak
  - Example: Change `return 302 https://...` to `return 302 /` after clearing the cookie

### Security vs Convenience Trade-off

- ✅ **Full OIDC Logout (current)**: More secure, complete session termination
  - Users must re-enter credentials after logout
  - Recommended for sensitive/internal applications
  
- ❌ **Partial Logout**: Less secure, only clears application cookies
  - Users can re-login with one click (Keycloak session persists)
  - Not recommended but faster for development

## References

- [OAuth2-proxy OIDC Configuration](https://oauth2-proxy.github.io/oauth2-proxy/configuration/providers/oidc)
- [OIDC RP-Initiated Logout](https://openid.net/specs/openid-connect-rpinitiated-1_0.html)
- [Keycloak OIDC Logout](https://www.keycloak.org/docs/latest/securing_apps/#logout)
- [This Stack's Django Integration](django-integration.md#5-logout-handling)
