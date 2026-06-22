# Hyper Game Panel — License-Free Installer

One-line installer for **Hyper Game Panel v2.0.12** with license checks bypassed.

## Quick Install

```bash
bash <(curl -sL https://raw.githubusercontent.com/CodeByCruel/hyper-panel-installer/main/install.sh)
```

Or with custom options:

```bash
FQDN=panel.example.com \
ADMIN_EMAIL=admin@example.com \
ADMIN_PASSWORD=MySecurePass123 \
bash <(curl -sL https://raw.githubusercontent.com/CodeByCruel/hyper-panel-installer/main/install.sh)
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PANEL_PATH` | `/var/www/pterodactyl` | Panel installation directory |
| `FQDN` | `$(hostname -f)` | Domain name for the panel |
| `ADMIN_EMAIL` | `admin@$(hostname -f)` | Admin account email |
| `ADMIN_PASSWORD` | `ChangeMeNow123!` | Admin account password |
| `DB_HOST` | `127.0.0.1` | MySQL host |
| `DB_PORT` | `3306` | MySQL port |
| `DB_NAME` | `pterodactyl` | Database name |
| `DB_USER` | `pterodactyl` | Database user |
| `TIMEZONE` | `UTC` | Server timezone |

## What This Does

1. Installs PHP 8.4 + IonCube Loader
2. Installs MariaDB, Redis, Nginx, Supervisor
3. Downloads Hyper Game Panel v2.0.12 from official source
4. **Patches license system** — replaces 20+ encoded PHP files with clean stubs
5. **Patches JS** — license service always returns valid
6. **Empties security manifest** — no file integrity checks
7. Runs database migrations + seeds
8. Configures Nginx with SSL
9. Sets up queue worker + scheduler via Supervisor
10. Creates admin user

## What Gets Patched

### PHP Stubs (bypass license/security)
- `HyperV2LicenseGate` middleware → pass-through
- `HyperV2SecurityMonitor` middleware → pass-through
- `EnforceHyperV2PanelAccess` middleware → pass-through
- `LicenseController` → always returns `valid: true`
- `HyperV2LicenseService` → all methods return true
- `LicenseValidationService` → all methods return true
- `HyperV2IntegrityService` → integrity checks disabled
- Security manifest → empty (no hash verification)

### JS Patches (bypass client-side checks)
- `licenseService` → always reports valid license
- `LicenseMonitor` → no-op component

## Requirements

- **OS:** Debian 11+ / Ubuntu 20.04+
- **RAM:** 2GB minimum
- **Root access:** Required

## After Install

1. Visit `https://your-domain`
2. Login with admin credentials (shown at end of install)
3. Change admin password
4. Add nodes via Admin → Nodes

## Wings Node Install

```bash
curl -sSL https://raw.githubusercontent.com/pterodactyl/wings/master/install.sh | sudo bash
```

## License

This is for educational purposes only. Hyper Game Panel is commercial software.
