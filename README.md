# Hyper Panel — All-in-One Installer

One-line installer for **Pterodactyl Panel + Hyper Game Panel v2.0.12** with license bypass.

## Quick Start

```bash
bash <(curl -sL https://raw.githubusercontent.com/CodeByCruel/hyper-panel-installer/main/install.sh)
```

## Menu Options

```
[0] Install Panel + Hyper    — Pterodactyl panel + Hyper theme (license-free)
[1] Install Wings             — Game server daemon
[2] Install Everything        — Panel + Hyper + Wings (full stack)
[3] Uninstall Panel           — Remove panel (keeps database by default)
[4] Uninstall Wings           — Remove wings daemon
[5] Uninstall Everything      — Remove everything
[6] Repair / Re-patch Hyper   — Re-apply all license patches + fix permissions
[7] Update Hyper              — Download latest Hyper + re-patch
```

## Install Flow

When you run option **[0]** or **[2]**, the script will:

1. Ask for your config (domain, email, password)
2. Install PHP 8.4 + IonCube Loader
3. Install MariaDB, Redis, Nginx, Supervisor
4. Download Pterodactyl Panel from GitHub
5. Install Composer dependencies
6. Set up database + run migrations
7. **Download Hyper Game Panel v2.0.12**
8. **Patch 20+ license/security PHP files** with clean stubs
9. **Patch JS license files** (always returns valid)
10. **Empty security manifest** (no file integrity checks)
11. Configure Nginx with SSL
12. Set up queue worker + scheduler
13. Create admin user

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PANEL_PATH` | `/var/www/pterodactyl` | Panel installation directory |
| `FQDN` | `$(hostname -f)` | Domain name for the panel |
| `ADMIN_EMAIL` | `admin@$(hostname)` | Admin account email |
| `ADMIN_PASSWORD` | `ChangeMeNow123!` | Admin account password |
| `DB_HOST` | `127.0.0.1` | MySQL host |
| `DB_PORT` | `3306` | MySQL port |
| `DB_NAME` | `pterodactyl` | Database name |
| `DB_USER` | `pterodactyl` | Database user |
| `TIMEZONE` | `UTC` | Server timezone |

## Custom Install

```bash
FQDN=panel.example.com \
ADMIN_EMAIL=admin@example.com \
ADMIN_PASSWORD=SuperSecret123 \
DB_NAME=mypanel \
bash <(curl -sL https://raw.githubusercontent.com/CodeByCruel/hyper-panel-installer/main/install.sh)
```

## Repair / Update

If something breaks or you want to re-patch:

```bash
# Re-apply all Hyper patches
sudo bash install.sh   # then choose [6]

# Update to latest Hyper version
sudo bash install.sh   # then choose [7]
```

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
- + 10 more services and traits

### JS Patches (bypass client-side checks)
- `licenseService` → always reports valid license with all 8 feature categories
- `LicenseMonitor` → no-op component (returns null)

## Requirements

- **OS:** Debian 11+ / Ubuntu 20.04+
- **RAM:** 2GB minimum
- **Root access:** Required
- **Domain:** Point DNS to your server before install

## After Install

1. Visit `https://your-domain`
2. Login with admin credentials
3. Change admin password
4. Add nodes via Admin → Nodes
5. Install Wings on game server nodes

## Wings Node Install

On each game server node, run:

```bash
bash <(curl -sL https://raw.githubusercontent.com/CodeByCruel/hyper-panel-installer/main/install.sh)
# Choose [1] Install Wings
```

Then configure with your panel token:

```bash
wings configure --panel-url https://your-panel --token YOUR_NODE_TOKEN
```

## Uninstall

The uninstall option **[3]** removes:
- Panel files at `/var/www/pterodactyl`
- Nginx site configuration
- Supervisor worker configs
- Logrotate configs

**Database is preserved by default** (option to drop it).

## License

This is for educational purposes only. Hyper Game Panel is commercial software.
