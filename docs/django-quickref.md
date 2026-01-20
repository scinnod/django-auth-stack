<!--
SPDX-FileCopyrightText: 2024-2026 David Kleinhans, Jade University of Applied Sciences
SPDX-License-Identifier: Apache-2.0
-->

# Django + Keycloak Quick Reference

## Two Authentication Patterns

This stack provides **two scaffold configurations**:

| Pattern | Use Case | nginx Config | Public Pages? |
|---------|----------|--------------|---------------|
| **A: Django-Controlled** | Public + protected pages | `itsm.conf.template` | ✅ Yes |
| **B: Full nginx Auth** | Everything protected | `deepl.conf.template` | ❌ No |

---

## Pattern A: Django-Controlled (ITSM)

✅ Django decides what's public vs protected  
✅ `@login_required` triggers Keycloak  
✅ Flexible for mixed public/private content  

### Configuration

```python
# settings.py
LOGIN_URL = '/sso-login/'  # IMPORTANT!

AUTHENTICATION_BACKENDS = [
    'django.contrib.auth.backends.RemoteUserBackend',
    'django.contrib.auth.backends.ModelBackend',
]

MIDDLEWARE = [
    # ...
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.auth.middleware.RemoteUserMiddleware',
    # ...
]

REMOTE_USER_HEADER = 'HTTP_X_REMOTE_USER'
```

```python
# views.py
from django.shortcuts import redirect

def sso_login(request):
    """SSO endpoint - nginx adds X-Remote-User here"""
    return redirect(request.GET.get('next', '/'))

# urls.py
urlpatterns = [path('sso-login/', views.sso_login), ...]
```

### Usage

```python
# Public view - no login required
def homepage(request):
    return render(request, 'home.html')

# Protected - triggers Keycloak login
@login_required
def dashboard(request):
    return render(request, 'dashboard.html')
```

---

## Pattern B: Full nginx Auth (DeepL)

✅ Everything protected (including static files)  
✅ Simpler Django setup  
✅ Maximum security  

### Configuration

```python
# settings.py (simpler - no LOGIN_URL or sso_login view!)

AUTHENTICATION_BACKENDS = [
    'django.contrib.auth.backends.RemoteUserBackend',
    'django.contrib.auth.backends.ModelBackend',
]

MIDDLEWARE = [
    # ...
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.auth.middleware.RemoteUserMiddleware',
    # ...
]

REMOTE_USER_HEADER = 'HTTP_X_REMOTE_USER'
```

---

## Common: Email & Auto-Creation

✅ **Email is available!** Both patterns receive:
- `request.META['HTTP_X_REMOTE_USER']` → Keycloak username
- `request.META['HTTP_X_REMOTE_EMAIL']` → Keycloak email

✅ **Users created automatically!** First login creates Django User account

### Populate Email from Keycloak

### settings.py
```python
# Authentication backends
AUTHENTICATION_BACKENDS = [
    'django.contrib.auth.backends.RemoteUserBackend',
    'django.contrib.auth.backends.ModelBackend',
]

# Middleware - order matters!
MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',  # BEFORE RemoteUserMiddleware
    'django.contrib.auth.middleware.RemoteUserMiddleware',      # AFTER AuthenticationMiddleware
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

# Header configuration
REMOTE_USER_HEADER = 'HTTP_X_REMOTE_USER'

# CSRF trusted origins (for reverse proxy)
CSRF_TRUSTED_ORIGINS = [
    'https://itsm.jade.local',
    'https://auth.jade.local',
]
```

## Usage in Views

### Protected Views
```python
from django.contrib.auth.decorators import login_required

@login_required
def my_view(request):
    # User is automatically authenticated via Keycloak
    # request.user is populated from X-Remote-User header
    return render(request, 'template.html', {
        'username': request.user.username,
        'email': request.user.email,
    })
```

### Django i18n_patterns Compatibility

The nginx configuration **fully supports** Django's `i18n_patterns()`:

```python
# urls.py
from django.conf.urls.i18n import i18n_patterns
from django.urls import path

urlpatterns = i18n_patterns(
    path('admin/', admin.site.urls),
    path('dashboard/', views.dashboard),
    # Paths will be: /de/admin/, /en/admin/, /de/dashboard/, /en/dashboard/
)
```

**How it works:**
- User accesses `/de/admin/` (not authenticated)
- nginx redirects to `/oauth2/start?rd=https://itsm.jade.local/de/admin/`
- After Keycloak login, OAuth2-proxy redirects back to `/de/admin/` (language prefix preserved!)
- Django receives request with X-Remote-User header and correct language prefix
- Everything works as expected with `@login_required` decorators

**No nginx configuration changes needed** - the `location /` block matches all paths including language-prefixed ones.

### Public Views (No Decorator)
```python
def public_view(request):
    # Still accessible, but user is authenticated if they logged in elsewhere
    if request.user.is_authenticated:
        return HttpResponse(f"Hello {request.user.username}")
    else:
        return HttpResponse("Hello anonymous user")
```

### Class-Based Views
```python
from django.contrib.auth.mixins import LoginRequiredMixin

class ProtectedView(LoginRequiredMixin, View):
    def get(self, request):
        # User is authenticated
        return render(request, 'template.html')
```

## Logout

```python
from django.contrib.auth import logout
from django.shortcuts import redirect

def logout_view(request):
    # Logout from Django
    logout(request)
    
    # Redirect to OAuth2-proxy logout (clears Keycloak session)
    return redirect('/oauth2/sign_out?rd=/')
```

## Custom User Creation

### Populate Email from Keycloak (Recommended)
```python
# yourapp/backends.py
from django.contrib.auth.backends import RemoteUserBackend

class CustomRemoteUserBackend(RemoteUserBackend):
    def configure_user(self, request, user):
        """Called when user is created for the first time."""
        user.email = request.META.get('HTTP_X_REMOTE_EMAIL', '')
        user.save()
        return user
    
    def configure_user_on_login(self, request, user):
        """Optional: Update email on every login (sync changes from Keycloak)."""
        email = request.META.get('HTTP_X_REMOTE_EMAIL', '')
        if email and user.email != email:
            user.email = email
            user.save()
        return user
```

```python
# settings.py
AUTHENTICATION_BACKENDS = [
    'yourapp.backends.CustomRemoteUserBackend',  # Use custom backend with email
    'django.contrib.auth.backends.ModelBackend',
]
```

### Use Email as Username Instead
```python
# If you want users to login with email addresses instead of usernames
class EmailRemoteUserBackend(RemoteUserBackend):
    def authenticate(self, request, remote_user):
        if not remote_user:
            return None
        # Use email as username
        email = request.META.get('HTTP_X_REMOTE_EMAIL', remote_user)
        return super().authenticate(request, remote_user=email)
    
    def configure_user(self, request, user):
        user.email = request.META.get('HTTP_X_REMOTE_EMAIL', '')
        user.save()
        return user
```

## Testing

### Check Headers in View
```python
@login_required
def debug_auth(request):
    return JsonResponse({
        'user': request.user.username,
        'email': request.user.email,
        'is_authenticated': request.user.is_authenticated,
        'headers': {
            'HTTP_X_REMOTE_USER': request.META.get('HTTP_X_REMOTE_USER'),
            'HTTP_X_REMOTE_EMAIL': request.META.get('HTTP_X_REMOTE_EMAIL'),
        }
    }, indent=2)
```

### Command Line Test
```bash
# Not authenticated - should redirect to Keycloak
curl -I https://itsm.jade.local/protected/
# Expected: HTTP 302 → /oauth2/start

# After login (with cookie)
curl -H "Cookie: _oauth2_proxy=..." https://itsm.jade.local/protected/
# Expected: HTTP 200
```

## Troubleshooting

### Problem: request.user is AnonymousUser
**Check:**
1. Is `RemoteUserMiddleware` in `MIDDLEWARE`?
2. Is `RemoteUserMiddleware` AFTER `AuthenticationMiddleware`?
3. Is `REMOTE_USER_HEADER = 'HTTP_X_REMOTE_USER'` set?
4. Is nginx setting the header? (Check with debug view above)

### Problem: Users not auto-created
**Check:**
1. Is `RemoteUserBackend` in `AUTHENTICATION_BACKENDS`?
2. Have you run migrations? (`python manage.py migrate`)

### Problem: Logout doesn't work
**Solution:** Redirect to OAuth2-proxy logout endpoint
```python
def logout_view(request):
    logout(request)
    return redirect('/oauth2/sign_out?rd=/')  # Important!
```

## What Happens Under the Hood

1. User accesses Django URL (e.g., `/admin/`)
2. Nginx checks authentication via OAuth2-proxy
3. If not authenticated → redirect to Keycloak login
4. After Keycloak login → OAuth2-proxy sets cookie
5. Nginx forwards request with `X-Remote-User: username` header
6. Django `RemoteUserMiddleware` reads header
7. Django `RemoteUserBackend` creates/loads User object
8. Django creates session for the user
9. `@login_required` sees `request.user.is_authenticated = True`
10. View executes normally

## Public Paths (No Authentication)

These paths bypass OAuth2-proxy completely:
- `/static/` - Static files (CSS, JS, images)
- `/media/` - User uploads
- `/health` - Health check endpoint

All other paths require authentication!

## Documentation

- **Detailed Guide**: [django-integration.md](django-integration.md)
- **Django Docs**: https://docs.djangoproject.com/en/stable/howto/auth-remote-user/
- **OAuth2-proxy**: https://oauth2-proxy.github.io/oauth2-proxy/
