<!--
SPDX-FileCopyrightText: 2024-2026 David Kleinhans, Jade University of Applied Sciences
SPDX-License-Identifier: Apache-2.0
-->

# Keycloak Realm Configuration (Config-as-Code)

This directory is for storing Keycloak realm configurations as JSON files.

## Why Config-as-Code?

Instead of clicking through the Keycloak admin UI every time you set up a new environment, you can:
1. Configure Keycloak once via the web UI
2. Export the realm configuration to JSON
3. Store it here for version control and reproducibility
4. Import it automatically on fresh deployments

## How to Export a Realm

After configuring your realm in the Keycloak admin UI:

```bash
# Export the realm (replace 'jade' with your realm name)
sudo docker exec edge_keycloak /opt/keycloak/bin/kc.sh export \
  --realm jade \
  --file /tmp/jade-realm.json \
  --users realm_file

# Copy to local directory
sudo docker cp edge_keycloak:/tmp/jade-realm.json ./keycloak/realms/

# Commit to version control
git add keycloak/realms/jade-realm.json
git commit -m "Add Keycloak realm configuration"
```

## How to Import a Realm

On a fresh deployment, Keycloak will automatically import any JSON files from this directory on startup.

Alternatively, import manually:

```bash
# Copy realm file to container
sudo docker cp ./keycloak/realms/jade-realm.json edge_keycloak:/tmp/

# Import the realm
sudo docker exec edge_keycloak /opt/keycloak/bin/kc.sh import \
  --file /tmp/jade-realm.json

# Restart Keycloak to apply changes
sudo docker compose restart keycloak
```

## ⚠️ Security Warning

**Realm exports contain sensitive data:**
- Client secrets
- User password hashes (if --users option is used)
- SAML/OIDC private keys

**Best practices:**
1. **DO NOT** commit realm exports with `--users realm_file` to public repositories
2. Use `--users skip` for public repos (export configuration only)
3. Add `*.json` to `.gitignore` if realm contains sensitive data
4. Store user data separately in a secure backup location

## Example: Public-Safe Export

For public repositories, export without user data:

```bash
sudo docker exec edge_keycloak /opt/keycloak/bin/kc.sh export \
  --realm jade \
  --file /tmp/jade-realm-public.json \
  --users skip
```

This exports:
✅ Realm settings
✅ Client configurations (without secrets)
✅ Authentication flows
✅ Identity provider settings
❌ User accounts and passwords

## Recommended Workflow

1. **Development**: Configure via web UI
2. **Export**: Use `--users skip` for public repo
3. **Version Control**: Commit realm JSON
4. **Production**: Import realm + create users separately via Keycloak API or web UI

## Additional Resources

- [Keycloak Export/Import Documentation](https://www.keycloak.org/server/importExport)
- [Keycloak CLI Reference](https://www.keycloak.org/server/configuration)
- [Client Configuration for Logout](../../docs/keycloak-logout.md#keycloak-client-configuration) - Required settings for OIDC logout

## Required Client Configuration

When creating OIDC clients for this stack, ensure these settings are configured:

### Critical for Logout
- **Valid Post Logout Redirect URIs**: `https://your-domain/*`
  - Without this, OIDC logout will fail
  - See [keycloak-logout.md](../../docs/keycloak-logout.md) for details

### Standard Settings
- **Client Authentication**: ON (confidential clients)
- **Standard Flow**: Enabled
- **Valid Redirect URIs**: `https://auth.domain/oauth2/callback`, `https://app.domain/*`
