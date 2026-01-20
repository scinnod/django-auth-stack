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

Instead of relying on oauth2-proxy, nginx handles the full logout flow:

```nginx
location = /oauth2/sign_out {
    # Clear the oauth2-proxy cookie
    add_header Set-Cookie "_oauth2_proxy=; Path=/; Domain=${OAUTH2_PROXY_COOKIE_DOMAIN}; HttpOnly; Secure; SameSite=Lax; Max-Age=0" always;
    
    # Redirect to Keycloak's end_session_endpoint
    return 302 https://${DOMAIN_AUTH}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/logout?post_logout_redirect_uri=https://${DOMAIN_ITSM}/&client_id=${OAUTH2_PROXY_CLIENT_ID};
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

When a user visits `/oauth2/sign_out`, the following happens:

1. **Django logout view** clears the Django session
2. **Django** redirects to `/oauth2/sign_out`
3. **nginx** clears the oauth2-proxy cookie (`_oauth2_proxy`)
4. **nginx** redirects (302) to Keycloak's `end_session_endpoint` with:
   - `client_id` - identifies the application
   - `post_logout_redirect_uri` - where to redirect after logout
5. **Keycloak** shows logout confirmation (because no `id_token_hint`)
6. **User clicks "Logout"** on Keycloak page
7. **Keycloak** terminates the SSO session
8. **Keycloak** redirects back to `post_logout_redirect_uri`

Result: User is fully logged out and must re-enter credentials to log back in.

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
- [ ] ✅ **Audience Mapper** - Add client ID to `aud` claim (see detailed steps below)
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
   https://${DOMAIN_ITSM}/*
   https://${DOMAIN_TRANSLATION}/*
   ```
   Replace with your actual domains from `.env`

4. **Valid Post Logout Redirect URIs**: 
   ```
   https://${DOMAIN_ITSM}/*
   https://${DOMAIN_TRANSLATION}/*
   https://${DOMAIN_AUTH}/*
   ```
   **⚠️ CRITICAL**: Without these URIs configured, **logout will fail** with "Invalid redirect URI" error.
   
   **Steps to configure:**
   1. Go to Keycloak Admin Console → Your Realm → Clients → Your Client
   2. Scroll down to **Login settings** section
   3. Find **Valid post logout redirect URIs** field
   4. Add each domain where users can be redirected after logout:
      - `https://itsm.example.org/*`
      - `https://translation.example.org/*` (if using Translation service)
      - Or use `*` to allow any redirect (less secure)
   5. Click **Save**

5. **Web Origins**: `+` (allows all valid redirect URIs)

### Required: Audience Mapper (for keycloak-oidc provider)

OAuth2-proxy with `--provider=keycloak-oidc` requires the client ID to be included
in the `aud` (audience) claim of the JWT token. Keycloak doesn't do this by default.

**Steps to add the audience mapper:**

1. Go to Keycloak Admin Console → Your Realm → Clients → Your Client
2. Click the **Client scopes** tab
3. Click on `<your-client-id>-dedicated` (e.g., `oauth2-proxy-dedicated`)
4. Click **Configure a new mapper** (or **Add mapper** → **By configuration**)
5. Select **Audience**
6. Configure:
   - **Name**: `audience-mapper` (or any descriptive name)
   - **Included Client Audience**: Select your client (e.g., `oauth2-proxy`)
   - **Add to ID token**: ON
   - **Add to access token**: ON
7. Click **Save**

**Verification**: After adding the mapper, you can test by:
1. Go to Clients → Your Client → Client scopes → Evaluate
2. Select a test user
3. Click **Generated ID token** or **Generated access token**
4. Verify the `aud` claim includes your client ID:
   ```json
   {
     "aud": ["oauth2-proxy", "account"],
     ...
   }
   ```

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
- User logs out of ITSM → Also logged out of Translation (and any other apps in the same realm)
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
- [This Stack's Django Integration](django-integration.md#5-logout-handling)
