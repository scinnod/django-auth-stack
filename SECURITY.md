<!--
SPDX-FileCopyrightText: 2024-2026 David Kleinhans, Jade University of Applied Sciences
SPDX-License-Identifier: Apache-2.0
-->

# Security Policy

## Reporting Vulnerabilities

Please report security vulnerabilities privately via email to:
**david.kleinhans@jade-hs.de**

Do not open public issues for security vulnerabilities.

## Supported Versions

Only the latest version receives security updates.

## Security Best Practices

- Never commit `.env` files (contains secrets)
- Use strong, unique passwords for all services
- Keep Keycloak and all containers updated
- Use TLS certificates in production
- Regularly rotate secrets and credentials
- Monitor container logs for suspicious activity
