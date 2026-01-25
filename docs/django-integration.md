<!--
SPDX-FileCopyrightText: 2024-2026 David Kleinhans, Jade University of Applied Sciences
SPDX-License-Identifier: Apache-2.0
-->

# Django Integration with Keycloak via OAuth2-proxy

This document describes the **standard** Django configuration patterns for integrating with Keycloak SSO using OAuth2-proxy as the authentication gateway.

## Two Authentication Patterns

This stack provides **two authentication patterns** configured per-service in `.env`:

### Pattern A: Django-Controlled Authentication

**When to use:** You want Django to control which pages are public vs protected.

**How it works:**
- Public Django pages accessible without Keycloak login
- Django `@login_required` decorator triggers Keycloak authentication
- Special `/sso-login/` endpoint handles OAuth2-proxy authentication
- After Keycloak login, Django session handles subsequent requests
- **Example:** Public marketing pages, blog, docs; login required for dashboard/admin

**nginx template:** `service-pattern-a.conf.template`

**Configuration:**
```bash
SERVICE_1_PATTERN=A
```

### Pattern B: Full nginx-Level Authentication

**When to use:** Everything should be protected, no public pages.

**How it works:**
- ALL requests (including static files) require Keycloak login
- nginx validates every request via OAuth2-proxy (fast cookie check)
- Django receives authenticated user headers for all requests
- Simple, secure, no public access whatsoever
- **Example:** Internal tools, admin dashboards, confidential services

**nginx template:** `service-pattern-b.conf.template`

**Configuration:**
```bash
SERVICE_1_PATTERN=B
```

---

## Pattern A: Django-Controlled Authentication (Recommended)

This pattern gives you maximum flexibility - Django decides what's public.

### Architecture Overview

```
User → Nginx (TLS) → Django (public pages served directly)
         ↓
       /sso-login/ endpoint → OAuth2-proxy → Keycloak (OIDC)
         ↓ (X-Remote-User header)
       Django (RemoteUserBackend creates session)
```

### Authentication Flow (Pattern A)

1. **User accesses public Django page** → Django serves it normally (no Keycloak)
2. **User accesses page with `@login_required`** → Django redirects to `/sso-login/?next=/protected/`
3. **Nginx intercepts `/sso-login/`** → Checks OAuth2-proxy
   - If not authenticated → OAuth2-proxy redirects to Keycloak login
4. **User logs in via Keycloak** → OAuth2-proxy creates session cookie
5. **OAuth2-proxy returns to `/sso-login/`** with `X-Auth-Request-User` header
6. **Nginx passes request to Django** with `X-Remote-User` header
7. **Django RemoteUserMiddleware**:
   - Reads `X-Remote-User` header
   - Creates/updates Django User object automatically
   - Creates Django session cookie
8. **Django view redirects** to originally requested page (`/protected/`)
9. **Subsequent requests** → Django session cookie only, no OAuth2-proxy involvement

## Django Configuration (Pattern A)

### 1. Required Settings (`settings.py`)

```python
# =============================================================================
# AUTHENTICATION CONFIGURATION - Keycloak via OAuth2-proxy (Pattern A)
# =============================================================================

# IMPORTANT: Point Django's login to the SSO endpoint
LOGIN_URL = '/sso-login/'

# Authentication backends - MUST be in this order
AUTHENTICATION_BACKENDS = [
    'django.contrib.auth.backends.RemoteUserBackend',  # Primary: Trust reverse proxy
    'django.contrib.auth.backends.ModelBackend',       # Fallback: Django sessions/admin
]

# Middleware - RemoteUserMiddleware MUST come after AuthenticationMiddleware
MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',  # First
    'django.contrib.auth.middleware.RemoteUserMiddleware',      # Second - reads REMOTE_USER
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

# Header configuration - tells RemoteUserMiddleware which header to trust
REMOTE_USER_HEADER = 'HTTP_X_REMOTE_USER'
```

### 2. Create SSO Login View

```python
# views.py
from django.shortcuts import redirect

def sso_login(request):
    """
    SSO login endpoint. nginx adds X-Remote-User header here after Keycloak auth.
    RemoteUserMiddleware will create Django session from the header.
    Then redirect to the page that triggered login.
    """
    next_url = request.GET.get('next', '/')
    return redirect(next_url)

# urls.py
from django.urls import path
from . import views

urlpatterns = [
    path('sso-login/', views.sso_login, name='sso_login'),
    # ... other URLs
]
```

### 3. Use @login_required Normally

```python
from django.contrib.auth.decorators import login_required

# Public view - anyone can access
def homepage(request):
    return render(request, 'home.html')

# Protected view - triggers Keycloak login
@login_required
def dashboard(request):
    # User is authenticated via Keycloak
    return render(request, 'dashboard.html', {
        'username': request.user.username,
        'email': request.user.email,
    })
```

---

## Pattern B: Full nginx-Level Authentication

For services where everything should be protected (e.g., translation service).

### Django Configuration (Pattern B)

```python
# settings.py - Simpler than Pattern A

AUTHENTICATION_BACKENDS = [
    'django.contrib.auth.backends.RemoteUserBackend',
    'django.contrib.auth.backends.ModelBackend',
]

MIDDLEWARE = [
    # ... same middleware as Pattern A
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.auth.middleware.RemoteUserMiddleware',
    # ...
]

REMOTE_USER_HEADER = 'HTTP_X_REMOTE_USER'

# No LOGIN_URL needed - nginx handles all authentication
```

**Key differences from Pattern A:**
- No `LOGIN_URL = '/sso-login/'` (nginx authenticates everything)
- No SSO login view needed
- `@login_required` still works, but users are already authenticated
- Simpler setup, but no public pages
- **Logout works the same way** - redirect to `/oauth2/sign_out` (see [Logout Handling](#5-logout-handling))

---

## Common Configuration (Both Patterns)

### User Identification & Email Handling

Nginx passes two separate headers from OAuth2-proxy to Django:
- `X-Remote-User` header → Keycloak username (e.g., `davidkl`) from the `preferred_username` claim
- `X-Remote-Email` header → Keycloak email (e.g., `david.kleinhans@jade-hs.de`) from the `email` claim

**Implications for Django:**
1. Django will create users with the actual Keycloak username (e.g., `davidkl`)
2. Use a custom backend to capture the email from `X-Remote-Email` header

This configuration ensures:
- Django usernames match Keycloak usernames (intuitive user management)
- Django has the user's email for notifications, password resets, etc.

**Automatic User Creation:**
When a user logs in via Keycloak for the first time, Django's `RemoteUserBackend` **automatically creates** a Django User account:
- `username` = value from `X-Remote-User` header (Keycloak's `preferred_username`)
- `email` = empty by default (see below to populate from header)
- `is_staff` = False
- `is_superuser` = False
- No password is set (authentication is handled by Keycloak)

### Option 1: Basic RemoteUserBackend (Simplest)

No custom backend needed - Django will use the Keycloak username directly:

```python
# settings.py
REMOTE_USER_HEADER = 'HTTP_X_REMOTE_USER'

AUTHENTICATION_BACKENDS = [
    'django.contrib.auth.backends.RemoteUserBackend',
    'django.contrib.auth.backends.ModelBackend',
]
```

**Result:** Django creates users with:
- `username` = `davidkl` (from Keycloak)
- `email` = empty (not automatically populated)

### Option 2: Custom Backend with Email Support (Recommended)

Use a custom backend to also capture the email address:

```python
# yourapp/backends.py
from django.contrib.auth.backends import RemoteUserBackend

class CustomRemoteUserBackend(RemoteUserBackend):
    """
    Custom backend that captures email from X-Remote-Email header.
    
    OAuth2-proxy provides:
    - X-Remote-User: Keycloak username (preferred_username claim)
    - X-Remote-Email: Keycloak email (email claim)
    """
    
    def configure_user(self, request, user, created=True):
        """
        Configure user on first login - capture email from header.
        """
        email = request.META.get('HTTP_X_REMOTE_EMAIL', '')
        if email:
            user.email = email
            user.save()
        return user
    
    def authenticate(self, request, remote_user):
        """
        Authenticate and update email on every login.
        """
        if not remote_user:
            return None
        
        user = super().authenticate(request, remote_user)
        
        # Update email on every login (in case it changed in Keycloak)
        if user:
            email = request.META.get('HTTP_X_REMOTE_EMAIL', '')
            if email and user.email != email:
                user.email = email
                user.save()
        
        return user

# settings.py
AUTHENTICATION_BACKENDS = [
    'yourapp.backends.CustomRemoteUserBackend',
    'django.contrib.auth.backends.ModelBackend',
]
```

**Result:** Django creates users with:
- `username` = `davidkl` (from Keycloak)
- `email` = `david.kleinhans@jade-hs.de` (from Keycloak)
```

### 2. Understanding `@login_required` Behavior

```python
from django.contrib.auth.decorators import login_required
from django.http import JsonResponse

# This decorator now works with Keycloak authentication!
@login_required
def protected_view(request):
    """
    This view is protected by Keycloak via OAuth2-proxy.
    
    Flow:
    1. User accesses /protected/ (not authenticated)
    2. Nginx auth_request checks OAuth2-proxy → 401
    3. Nginx redirects to /oauth2/start → Keycloak login
    4. User logs in via Keycloak
    5. OAuth2-proxy sets cookie, nginx forwards with X-Remote-User header
    6. Django RemoteUserMiddleware creates session from header
    7. @login_required sees request.user.is_authenticated = True
    8. View executes normally
    """
    return JsonResponse({
        'user': request.user.username,
        'email': request.user.email,
        'is_staff': request.user.is_staff,
    })

# Public views work without decorator
def public_view(request):
    """
    This view is accessible to everyone (but user is still authenticated if
    they logged in elsewhere, since nginx passes X-Remote-User for all paths).
    """
    if request.user.is_authenticated:
        return JsonResponse({'message': f'Hello {request.user.username}'})
    else:
        return JsonResponse({'message': 'Hello anonymous user'})
```

### 3. Django i18n_patterns Support

The nginx configuration **fully supports** Django's internationalization URL patterns:

```python
# urls.py
from django.conf.urls.i18n import i18n_patterns
from django.urls import path
from django.contrib import admin

urlpatterns = i18n_patterns(
    path('admin/', admin.site.urls),
    path('dashboard/', views.dashboard),
    path('reports/', views.reports),
    # These become: /de/admin/, /en/admin/, /fr/admin/, etc.
)
```

**Authentication flow with i18n_patterns:**
1. User accesses `/de/admin/` (German admin interface)
2. nginx checks auth → not authenticated
3. nginx redirects to `/oauth2/start?rd=https://myapp.example.org/de/admin/`
4. After Keycloak login, OAuth2-proxy redirects back to `/de/admin/`
5. Language prefix is preserved throughout the flow
6. Django receives request with both X-Remote-User header and correct language

**No special configuration needed** - the nginx `location /` block matches all paths including language-prefixed ones. The `$request_uri` variable in the redirect preserves the full path including language prefix.

### 5. Logout Handling

Logout handling works **identically for both Pattern A and Pattern B**. Both `service-pattern-a.conf.template` and `service-pattern-b.conf.template` implement nginx-based OIDC logout.

```python
from django.contrib.auth import logout
from django.shortcuts import redirect

def logout_view(request):
    """
    Logout from both Django and Keycloak (full OIDC logout).
    Works for both Pattern A (Django-Controlled) and Pattern B (Full nginx-Level).
    
    This stack is configured for OIDC RP-Initiated Logout:
    1. Clear Django session (logout)
    2. Redirect to /oauth2/sign_out
    3. nginx clears the oauth2-proxy cookie
    4. nginx redirects to Keycloak's end_session_endpoint
    5. Keycloak terminates the SSO session
    6. User is redirected back to homepage
    
    Result: Full logout from both Django and Keycloak.
    User must re-enter credentials to log back in.
    
    See keycloak-logout.md for configuration details.
    """
    # Clear Django session
    logout(request)
    
    # Redirect to nginx-handled sign_out endpoint
    # nginx clears oauth2-proxy cookie and redirects to Keycloak logout
    # Note: The 'rd' parameter is no longer needed - nginx handles the redirect
    return redirect('/oauth2/sign_out')
```

### 6. Custom User Model (Optional)

If you use a custom user model, ensure it's compatible with RemoteUserBackend:

```python
# models.py
from django.contrib.auth.models import AbstractUser

class CustomUser(AbstractUser):
    """
    Custom user model with additional fields from Keycloak.
    """
    # Add any additional fields you want
    department = models.CharField(max_length=100, blank=True)
    employee_id = models.CharField(max_length=50, blank=True)
    
    # REQUIRED: username field must exist (inherited from AbstractUser)
    # RemoteUserBackend uses username for authentication

# settings.py
AUTH_USER_MODEL = 'yourapp.CustomUser'

# backends.py
class CustomRemoteUserBackend(RemoteUserBackend):
    def configure_user(self, request, user):
        """
        Populate additional fields from headers/Keycloak claims.
        """
        user.email = request.META.get('HTTP_X_REMOTE_EMAIL', '')
        
        # You can also access additional claims passed by OAuth2-proxy
        # (configure oauth2-proxy with --set-xauthrequest to pass more headers)
        user.department = request.META.get('HTTP_X_AUTH_REQUEST_DEPARTMENT', '')
        user.save()
        return user
```

## Testing the Integration

### 1. Verify Headers in Django

Create a debug view to see what headers Django receives:

```python
from django.http import JsonResponse
from django.contrib.auth.decorators import login_required

@login_required
def debug_auth(request):
    """Debug view to see authentication headers."""
    return JsonResponse({
        'username': request.user.username,  # e.g., 'john.doe' (from preferred_username)
        'email': request.user.email,
        'is_authenticated': request.user.is_authenticated,
        'headers': {
            'HTTP_X_REMOTE_USER': request.META.get('HTTP_X_REMOTE_USER'),
            'HTTP_X_REMOTE_EMAIL': request.META.get('HTTP_X_REMOTE_EMAIL'),
            'HTTP_X_AUTH_REQUEST_USER': request.META.get('HTTP_X_AUTH_REQUEST_USER'),
            'HTTP_X_AUTH_REQUEST_EMAIL': request.META.get('HTTP_X_AUTH_REQUEST_EMAIL'),
        }
    }, indent=2)
```

### 2. Test Authentication Flow

```bash
# 1. Access protected view (not authenticated)
curl -I https://myapp.example.org/admin/
# Expected: 302 redirect to /oauth2/start

# 2. After Keycloak login, access again with cookie
curl -H "Cookie: _oauth2_proxy=..." https://myapp.example.org/admin/
# Expected: 200 OK, rendered page

# 3. Check Django sees authenticated user
curl -H "Cookie: _oauth2_proxy=..." https://myapp.example.org/debug_auth
# Expected: {"username": "john.doe", "is_authenticated": true}
# Note: Username is from Keycloak's preferred_username claim, not UUID
```

### 3. Test @login_required Decorator

```python
# urls.py
from django.urls import path
from . import views

urlpatterns = [
    path('public/', views.public_view),      # No decorator
    path('protected/', views.protected_view), # @login_required
]

# Access /public/ → works without authentication (but user is authenticated due to nginx)
# Access /protected/ → requires Keycloak authentication
```

## Security Considerations

### 1. **Trust Boundary**

- **CRITICAL**: Only use `RemoteUserBackend` when nginx is the ONLY way to access Django
- If Django is accessible without going through nginx, anyone can forge `X-Remote-User` headers
- Ensure your Docker network configuration prevents direct access to the Django container

### 2. **Current Setup** (Secure ✅)

```yaml
# docker-compose.yml (for your Django service)
services:
  nginx:
    networks:
      - auth_backend       # Can talk to oauth2-proxy
      - myapp_backend      # Can talk to myapp_nginx
  
  oauth2_proxy:
    networks:
      - auth_backend       # Can talk to nginx, keycloak
      - keycloak_net       # Internal only
  
  myapp_nginx:  # Your Django container
    networks:
      - myapp_backend      # ONLY accessible via nginx
    # NOT exposed to host network
```

This setup is secure because:
- Django container is NOT exposed to host (`ports:` is missing)
- Django container is on isolated `<service>_backend` network
- ONLY nginx can reach Django container
- Users cannot bypass nginx to send forged headers

### 3. **Header Validation** (Optional Extra Security)

```python
# settings.py
ALLOWED_HOSTS = ['myapp.example.local']

# Middleware to validate headers come from trusted proxy
class ValidateProxyHeadersMiddleware:
    """
    Extra security: validate requests come from nginx.
    """
    def __init__(self, get_response):
        self.get_response = get_response
    
    def __call__(self, request):
        # Check for nginx-specific header
        if request.META.get('HTTP_X_FORWARDED_HOST') != 'myapp.example.local':
            # Request didn't come through nginx - reject it
            return HttpResponseForbidden("Direct access forbidden")
        
        return self.get_response(request)

# Add to MIDDLEWARE (before RemoteUserMiddleware)
```

## Troubleshooting

### Problem: `request.user` is `AnonymousUser` despite authentication

**Diagnosis:**
```python
# In Django view, check:
print(request.META.get('HTTP_X_REMOTE_USER'))  # Should print username
print(request.user)  # Shows AnonymousUser?
```

**Possible Causes:**
1. `RemoteUserMiddleware` not in `MIDDLEWARE` list
2. `RemoteUserMiddleware` placed BEFORE `AuthenticationMiddleware`
3. Wrong `REMOTE_USER_HEADER` setting (should be `HTTP_X_REMOTE_USER`)
4. Nginx not setting the header (check nginx config)

**Solution:**
```python
# settings.py - Correct order:
MIDDLEWARE = [
    # ...
    'django.contrib.auth.middleware.AuthenticationMiddleware',  # FIRST
    'django.contrib.auth.middleware.RemoteUserMiddleware',      # SECOND
    # ...
]
```

### Problem: Users not auto-created in Django

**Diagnosis:**
Check Django logs when accessing protected view for first time.

**Possible Causes:**
1. `RemoteUserBackend` not in `AUTHENTICATION_BACKENDS`
2. Database migration not run (`django.contrib.auth` tables missing)

**Solution:**
```bash
# Run migrations
python manage.py migrate

# Verify backend configuration
python manage.py shell
>>> from django.conf import settings
>>> print(settings.AUTHENTICATION_BACKENDS)
['django.contrib.auth.backends.RemoteUserBackend', ...]
```

### Problem: Logout doesn't work (still auto-logged in)

**Diagnosis:**
After logout, user can immediately access protected pages without re-entering credentials.

**Possible Causes:**
1. Keycloak SSO session still active (OIDC logout not working)
2. OAuth2-proxy cookie not cleared
3. Browser cache
4. Keycloak client missing \"Valid Post Logout Redirect URIs\"

**Solution:**
```python
# Logout view must redirect to nginx-handled sign_out endpoint
def logout_view(request):
    logout(request)  # Clear Django session
    return redirect('/oauth2/sign_out')  # Triggers full OIDC logout via nginx
```

**Additional checks:**
1. Verify OAuth2-proxy configuration includes `--pass-user-headers=true` (already in docker-compose.yml)
2. Check Keycloak client settings:
   - \"Valid Post Logout Redirect URIs\" must include your service domains:
     - `https://myapp.example.org/*` (for each configured service)
3. Check nginx logs: `sudo docker logs edge_nginx --tail 50`
4. See [keycloak-logout.md](keycloak-logout.md) for detailed troubleshooting

### Problem: CSRF errors on POST requests

**Diagnosis:**
```
Forbidden (403)
CSRF verification failed. Request aborted.
```

**Possible Causes:**
Django's CSRF protection expects forms to have CSRF tokens, which may not work correctly with OAuth2-proxy redirects.

**Solution:**
```python
# settings.py
# Trust CSRF token from cookies (set by OAuth2-proxy)
CSRF_TRUSTED_ORIGINS = [
    'https://myapp.example.local',
    'https://auth.example.local',
]

# Optional: Use more lenient CSRF for reverse proxy setups
CSRF_COOKIE_SECURE = True  # HTTPS only
CSRF_COOKIE_HTTPONLY = False  # Allow JavaScript access if needed
```

## References

- [Django RemoteUserBackend Documentation](https://docs.djangoproject.com/en/stable/howto/auth-remote-user/)
- [Django Authentication System](https://docs.djangoproject.com/en/stable/topics/auth/)
- [OAuth2-proxy Documentation](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Keycloak Integration Patterns](https://www.keycloak.org/docs/latest/securing_apps/)

## Summary

This integration uses **Django's standard RemoteUserBackend** which:
- ✅ Is officially supported by Django
- ✅ Works with Django's `@login_required` decorators
- ✅ Automatically creates user accounts from Keycloak
- ✅ Maintains Django sessions for performance
- ✅ Supports Django's permission system (`is_staff`, `is_superuser`, groups)
- ✅ Requires minimal code changes
- ✅ Is well-documented and widely used

**No custom OAuth2 libraries needed!** The authentication is handled by OAuth2-proxy at the nginx level, Django just trusts the `X-Remote-User` header from the trusted reverse proxy.
