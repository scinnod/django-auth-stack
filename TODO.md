<!--
SPDX-FileCopyrightText: 2024-2026 David Kleinhans, Jade University of Applied Sciences
SPDX-License-Identifier: Apache-2.0
-->

# Pre-Publication Checklist

## ✅ Completed

- [x] **SECURITY.md** - Added contact email (david.kleinhans@jade-hs.de)
- [x] **LICENSE** - Full Apache-2.0 with copyright attribution to David Kleinhans, Jade University
- [x] **NOTICE** - Created with Apache-2.0 notice and third-party component licenses
- [x] **CONTRIBUTING.md** - University infrastructure guidelines added, Apache-2.0 license
- [x] **License headers** - Updated all SPDX headers from AGPL-3.0-or-later to Apache-2.0
- [x] **Documentation** - Restructured into docs/ folder with consistent naming
- [x] **README** - Updated license badge and license section to Apache-2.0

## License Conversion Verification TODOs

- [ ] **TODO: Verify third-party licenses** - Confirm all third-party component licenses in NOTICE file are accurate and up-to-date
- [ ] **TODO: Missing SPDX headers** - Check if any new files need SPDX-License-Identifier: Apache-2.0 headers
- [ ] **TODO: License references in configs** - Verify no AGPL references remain in configuration files, comments, or deployment scripts
- [ ] **TODO: Documentation license updates** - Ensure all documentation files reference Apache-2.0 correctly
- [ ] **TODO: Review NOTICE file** - Annually review and update third-party component versions and licenses
- [ ] **TODO: Verify compliance** - Ensure all dependencies are compatible with Apache-2.0 licensing

## Before Publishing

- [ ] **Update .env.example** `LETSENCRYPT_EMAIL` from `admin@example.com` to your email
- [ ] **Verify no secrets** committed (see Security Verification below)
- [ ] **Git add and commit** the new/changed files

## Domain Names

The docs use `jade.local` as example domains, which is appropriate for the Jade University context.
This is intentional and shows a real-world setup.

## Repository Settings (GitHub)

- [ ] Add repository description: "Production-ready authentication gateway with nginx, Keycloak SSO, and OAuth2-proxy for Django services"
- [ ] Add topics: `keycloak`, `nginx`, `oauth2-proxy`, `docker`, `sso`, `authentication`, `django`
- [ ] Enable security alerts (Dependabot)
- [ ] Set up branch protection for `main`

## Optional Enhancements

- [ ] Add GitHub Actions for docker-compose validation
- [ ] Create GitHub issue templates
- [ ] Add screenshots to README
- [ ] Create a CHANGELOG.md

## Security Verification

Run these commands to verify no secrets are exposed:

```bash
# Check for any .env files in git history
git log --all --full-history --oneline -- "*.env"

# Check for certificate files
git log --all --full-history --oneline -- "*.pem" "*.key" "*.crt"

# Check for realm exports with secrets
git log --all --full-history --oneline -- "keycloak/realms/*.json"

# Search for potential secrets in tracked files
git grep -i "password\|secret\|key" -- ':!*.example' ':!*.md' ':!*.template'
```
