# Django Integration with Keycloak via OAuth2-proxy

This document describes the **standard** Django configuration pattern for integrating with Keycloak SSO using OAuth2-proxy as the authentication gateway.

## Architecture Overview

```
User → Nginx (TLS) → OAuth2-proxy → Keycloak (OIDC)
         ↓ (X-Remote-User header)
       Django (RemoteUserBackend)
```

### Authentication Flow

1. **User accesses protected Django URL** (e.g., view with `@login_required`)
2. **Nginx checks authentication** via `auth_request` to OAuth2-proxy
3. **OAuth2-proxy validates session**:
   - If valid → returns 200 with `X-Auth-Request-User` header
   - If invalid → returns 401, nginx redirects to `/oauth2/start` → Keycloak login
4. **Keycloak authenticates user** (username/password, LDAP, 2FA, etc.)
5. **OAuth2-proxy creates session**, sets `X-Auth-Request-User` header
6. **Nginx forwards request to Django** with `X-Remote-User` header
7. **Django RemoteUserBackend**:
   - Reads `X-Remote-User` header
   - Creates/updates Django User object automatically
   - Creates Django session
8. **Django's `@login_required` decorator** sees authenticated user → allows access

## Django Configuration

### 1. Required Settings (`settings.py`)

```python
# =============================================================================
# AUTHENTICATION CONFIGURATION - Keycloak via OAuth2-proxy
# =============================================================================

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
# This header is set by nginx from OAuth2-proxy's X-Auth-Request-User
REMOTE_USER_HEADER = 'HTTP_X_REMOTE_USER'

# =============================================================================
# OPTIONAL: Auto-create users from trusted header
# =============================================================================
# If you want Django to automatically create user accounts when someone
# authenticates via Keycloak for the first time, RemoteUserBackend already
# does this by default. The user will be created with:
#   - username = value from X-Remote-User header (Keycloak username)
#   - is_staff = False
#   - is_superuser = False

# To customize auto-created users (e.g., set email from X-Remote-Email header):
class CustomRemoteUserBackend(RemoteUserBackend):
    """
    Custom backend that populates email from X-Remote-Email header.
    """
    def configure_user(self, request, user):
        """
        Called when a user is created for the first time via remote auth.
        """
        # Get email from nginx header (set from OAuth2-proxy's X-Auth-Request-Email)
        email = request.META.get('HTTP_X_REMOTE_EMAIL', '')
        if email:
            user.email = email
            user.save()
        return user

# Then use in AUTHENTICATION_BACKENDS:
# AUTHENTICATION_BACKENDS = [
#     'yourapp.backends.CustomRemoteUserBackend',
#     'django.contrib.auth.backends.ModelBackend',
# ]
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
3. nginx redirects to `/oauth2/start?rd=https://itsm.jade.local/de/admin/`
4. After Keycloak login, OAuth2-proxy redirects back to `/de/admin/`
5. Language prefix is preserved throughout the flow
6. Django receives request with both X-Remote-User header and correct language

**No special configuration needed** - the nginx `location /` block matches all paths including language-prefixed ones. The `$request_uri` variable in the redirect preserves the full path including language prefix.
```

### 3. Logout Handling

```python
from django.contrib.auth import logout
from django.shortcuts import redirect

def logout_view(request):
    """
    Logout from both Django and Keycloak.
    
    Two-step logout:
    1. Clear Django session
    2. Redirect to OAuth2-proxy logout endpoint
    3. OAuth2-proxy clears its cookie
    4. Optionally redirect to Keycloak logout (not configured by default)
    """
    # Clear Django session
    logout(request)
    
    # Redirect to OAuth2-proxy logout, which clears the auth cookie
    # Then redirect back to homepage
    return redirect('/oauth2/sign_out?rd=/')
```

### 5. Custom User Model (Optional)

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
        'username': request.user.username,
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
curl -I https://itsm.jade.local/admin/
# Expected: 302 redirect to /oauth2/start

# 2. After Keycloak login, access again with cookie
curl -H "Cookie: _oauth2_proxy=..." https://itsm.jade.local/admin/
# Expected: 200 OK, rendered page

# 3. Check Django sees authenticated user
curl -H "Cookie: _oauth2_proxy=..." https://itsm.jade.local/debug_auth
# Expected: {"username": "david.kleinhans", "is_authenticated": true}
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
# docker-compose.yml
services:
  nginx:
    networks:
      - auth_backend    # Can talk to oauth2-proxy
      - itsm_backend    # Can talk to itsm_nginx
  
  oauth2_proxy:
    networks:
      - auth_backend    # Can talk to nginx, keycloak
      - keycloak_net    # Internal only
  
  itsm_nginx:  # Your Django container
    networks:
      - itsm_backend    # ONLY accessible via nginx
    # NOT exposed to host network
```

This setup is secure because:
- Django container is NOT exposed to host (`ports:` is missing)
- Django container is on isolated `itsm_backend` network
- ONLY nginx can reach Django container
- Users cannot bypass nginx to send forged headers

### 3. **Header Validation** (Optional Extra Security)

```python
# settings.py
ALLOWED_HOSTS = ['itsm.jade.local']

# Middleware to validate headers come from trusted proxy
class ValidateProxyHeadersMiddleware:
    """
    Extra security: validate requests come from nginx.
    """
    def __init__(self, get_response):
        self.get_response = get_response
    
    def __call__(self, request):
        # Check for nginx-specific header
        if request.META.get('HTTP_X_FORWARDED_HOST') != 'itsm.jade.local':
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

### Problem: Logout doesn't work

**Diagnosis:**
After logout, user still authenticated on next request.

**Possible Causes:**
1. Only clearing Django session, not OAuth2-proxy cookie
2. Browser cache

**Solution:**
```python
# Logout view must redirect to OAuth2-proxy logout endpoint
def logout_view(request):
    logout(request)  # Clear Django session
    return redirect('/oauth2/sign_out?rd=/')  # Clear OAuth2-proxy cookie
```

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
    'https://itsm.jade.local',
    'https://auth.jade.local',
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
