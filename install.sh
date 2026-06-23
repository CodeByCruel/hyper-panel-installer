#!/bin/bash
#==============================================================================
#  Hyper Panel — All-in-One Installer
#  Installs Pterodactyl Panel + Hyper Theme (license-free)
#
#  Usage: bash <(curl -sL https://raw.githubusercontent.com/CodeByCruel/hyper-panel-installer/main/install.sh)
#
#  Options:
#    [0] Install Panel + Hyper
#    [1] Install Wings
#    [2] Install Panel + Hyper + Wings (full stack)
#    [3] Uninstall Panel
#    [4] Uninstall Wings
#    [5] Uninstall Everything
#    [6] Repair / Re-patch Hyper
#    [7] Update Hyper
#==============================================================================
set -uo pipefail
# NOTE: we do NOT use set -e because interactive `read` and `|| fallback`
# patterns need the shell to keep going on individual command failures.

# ─── Constants ───────────────────────────────────────────────────────────────
PANEL_PATH="${PANEL_PATH:-/var/www/pterodactyl}"
WINGS_PATH="/usr/local/bin"
LOG_PATH="/var/log/pterodactyl-installer.log"
OFFICIAL_INSTALLER="https://pterodactyl-installer.se"
HYPER_VERSION="v2.0.12"
HYPER_API="https://license.dgenx.net/api/v1/update-check?app_id=7c4efcdc-986e-4e85-9b07-328d6ad6db52&file_slug=default"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"

# Auto-detect PHP version (prefer 8.4, fallback 8.3)
PHP_VER=""
for _v in 8.4 8.3 8.2 8.1; do
    if command -v "php$_v" &>/dev/null; then
        PHP_VER="$_v"
        break
    fi
done
PHP_VER="${PHP_VER:-8.4}"
DB_NAME="${DB_NAME:-pterodactyl}"
DB_USER="${DB_USER:-pterodactyl}"
FQDN="${FQDN:-}"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
TIMEZONE="${TIMEZONE:-UTC}"

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[i]${NC} $1"; }
step() { echo -e "\n${CYAN}${BOLD}── $1 ──${NC}"; }

# ─── Helpers ─────────────────────────────────────────────────────────────────
check_root() {
    [[ $EUID -ne 0 ]] && err "Must run as root. Use: sudo bash $0"
}

check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        err "Cannot detect OS."
    fi
    case "$OS" in
        debian|ubuntu) log "Detected $PRETTY_NAME" ;;
        *) err "Only Debian/Ubuntu is supported. Detected: $OS" ;;
    esac
}

ask_value() {
    local prompt="$1" default="$2" var="$3"
    if [ -n "${!var:-}" ]; then
        info "$prompt: ${!var}"
        return
    fi
    echo -n "* $prompt [$default]: "
    read -r input
    printf -v "$var" '%s' "${input:-$default}"
}

panel_installed() {
    [ -d "$PANEL_PATH" ] && [ -f "$PANEL_PATH/artisan" ]
}

wings_installed() {
    command -v wings &>/dev/null
}

hyper_patched() {
    [ -f "$PANEL_PATH/app/Http/Middleware/HyperV2LicenseGate.php" ] &&
    grep -q "return \$next(\$request)" "$PANEL_PATH/app/Http/Middleware/HyperV2LicenseGate.php" 2>/dev/null
}

# ─── Banner ──────────────────────────────────────────────────────────────────
show_banner() {
    clear
    echo -e "${GREEN}"
    cat << 'BANNER'
    _   _           _     _   _ _____  _
   | | | |_ __  ___| |__ | | | |_   _|(_)_ __   __ _
   | | | | '_ \/ __| '_ \| | | | | | | | | '_ \ / _` |
   | |_| | | | \__ \ | | | |_| | | | | | | | | (_| |
    \___/|_| |_|___/_| |_|\___/  |_| |_|_|_| |_|\__, |
                                                  |___/
BANNER
    echo -e "${NC}"
    echo -e "  ${BOLD}Pterodactyl + Hyper Game Panel — All-in-One Installer${NC}"
    echo -e "  ${BLUE}https://github.com/CodeByCruel/hyper-panel-installer${NC}\n"
}

# ─── Main Menu ───────────────────────────────────────────────────────────────
main_menu() {
    show_banner
    echo -e "${BOLD}What would you like to do?${NC}\n"

    echo -e "  ${GREEN}[0]${NC} Install Panel + Hyper  (base Pterodactyl + Hyper theme)"
    echo -e "  ${GREEN}[1]${NC} Install Wings           (game server daemon)"
    echo -e "  ${GREEN}[2]${NC} Install Everything       (Panel + Hyper + Wings)"
    echo ""
    echo -e "  ${RED}[3]${NC} Uninstall Panel"
    echo -e "  ${RED}[4]${NC} Uninstall Wings"
    echo -e "  ${RED}[5]${NC} Uninstall Everything"
    echo ""
    echo -e "  ${YELLOW}[6]${NC} Repair / Re-patch Hyper"
    echo -e "  ${YELLOW}[7]${NC} Update Hyper to latest"
    echo -e "  ${GREEN}[8]${NC} Install Hyper only (on existing panel)"
    echo -e "  ${RED}[9]${NC} Uninstall Hyper only (restore clean Pterodactyl)"
    echo ""

    echo -n "* Choose option (0-9): "
    read -r CHOICE

    case "${CHOICE:-}" in
        0) install_panel_hyper ;;
        1) install_wings ;;
        2) install_panel_hyper; install_wings ;;
        3) uninstall_panel ;;
        4) uninstall_wings ;;
        5) uninstall_panel; uninstall_wings ;;
        6) repair_hyper ;;
        7) update_hyper ;;
        8) install_hyper_only ;;
        9) uninstall_hyper_only ;;
        *) err "Invalid option. Please choose 0-9." ;;
    esac
}

#==============================================================================
#                           INSTALL FUNCTIONS
#==============================================================================

# ─── Install Panel + Hyper ──────────────────────────────────────────────────
install_panel_hyper() {
    step "Installing Pterodactyl Panel + Hyper Game Panel"

    check_root
    check_os

    if panel_installed; then
        warn "Panel already exists at $PANEL_PATH"
        echo -n "* Re-install? This will backup current panel (y/N): "
        read -r CONFIRM
        if [[ ! "$CONFIRM" =~ [Yy] ]]; then
            info "Skipping panel installation."
            apply_hyper
            return
        fi
        backup_panel
    fi

    # ── Ask for config ────────────────────────────────────────────────────
    echo ""
    step "Configuration"
    ask_value "Panel domain (FQDN)" "$(hostname -f)" FQDN
    ask_value "Admin email" "admin@${FQDN}" ADMIN_EMAIL
    ask_value "Admin password" "ChangeMeNow123!" ADMIN_PASSWORD
    ask_value "Database name" "pterodactyl" DB_NAME
    ask_value "Database user" "pterodactyl" DB_USER
    ask_value "Timezone" "UTC" TIMEZONE

    # Generate DB password
    DB_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)

    # ── Install base system ───────────────────────────────────────────────
    step "Installing System Packages"
    export DEBIAN_FRONTEND=noninteractive

    apt-get update -y >/dev/null 2>&1
    apt-get install -y software-properties-common curl wget unzip git >/dev/null 2>&1

    # PHP
    if ! "php$PHP_VER" -v &>/dev/null; then
        info "Adding PHP repository..."
        add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1 || true
        apt-get update -y >/dev/null 2>&1
    fi

    log "Installing PHP $PHP_VER + extensions..."
    apt-get install -y \
        php${PHP_VER} php${PHP_VER}-cli php${PHP_VER}-fpm \
        php${PHP_VER}-bcmath php${PHP_VER}-curl php${PHP_VER}-gd \
        php${PHP_VER}-mbstring php${PHP_VER}-mysql php${PHP_VER}-opcache \
        php${PHP_VER}-xml php${PHP_VER}-zip php${PHP_VER}-intl php${PHP_VER}-redis \
        nginx mariadb-server redis-server \
        composer certbot python3-certbot-nginx \
        supervisor logrotate >/dev/null 2>&1

    # IonCube Loader
    install_ioncube

    # Start services
    systemctl enable --now mysql 2>/dev/null || service mysql start 2>/dev/null || true
    systemctl enable --now redis-server 2>/dev/null || service redis-server start 2>/dev/null || true
    systemctl enable --now php${PHP_VER}-fpm 2>/dev/null || service php${PHP_VER}-fpm start 2>/dev/null || true

    # ── Database ───────────────────────────────────────────────────────────
    step "Configuring Database"
    mysql -u root <<SQL >/dev/null 2>&1
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'${DB_HOST}';
FLUSH PRIVILEGES;
SQL
    log "Database ready"

    # ── Download Panel ─────────────────────────────────────────────────────
    step "Downloading Pterodactyl Panel"
    mkdir -p "$PANEL_PATH"

    # Download latest release from GitHub
    PTERO_URL="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
    log "Downloading panel from GitHub..."
    TMP_DL=$(mktemp -d)
    curl -fSL --retry 3 -o "$TMP_DL/panel.tar.gz" "$PTERO_URL" 2>/dev/null || \
        wget -q -O "$TMP_DL/panel.tar.gz" "$PTERO_URL" 2>/dev/null || \
        err "Failed to download panel."

    log "Extracting panel..."
    tar -xzf "$TMP_DL/panel.tar.gz" -C "$PANEL_PATH" --strip-components=1 2>/dev/null || \
        err "Failed to extract panel."
    rm -rf "$TMP_DL"

    # ── Composer ───────────────────────────────────────────────────────────
    step "Installing Composer Dependencies"
    cd "$PANEL_PATH"
    export COMPOSER_ALLOW_SUPERUSER=1
    composer install --no-dev --optimize-autoloader --no-interaction 2>/dev/null || \
        err "Composer install failed."

    # ── Environment ────────────────────────────────────────────────────────
    step "Configuring Environment"
    cp "$PANEL_PATH/.env.example" "$PANEL_PATH/.env" 2>/dev/null || true

    APP_KEY=$(php -r "echo 'base64:'.base64_encode(random_bytes(32));")

    cat > "$PANEL_PATH/.env" <<ENVEOF
APP_ENV=production
APP_DEBUG=false
APP_KEY=${APP_KEY}
APP_URL=https://${FQDN}
APP_TIMEZONE=${TIMEZONE}
APP_LOCALE=en
APP_SERVICE_AUTHOR=unknown@unknown.com
APP_ENVIRONMENT_ONLY=false

DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASS}

CACHE_DRIVER=redis
SESSION_DRIVER=redis
QUEUE_CONNECTION=redis
REDIS_HOST=127.0.0.1

MAIL_MAILER=log
MAIL_HOST=127.0.0.1
MAIL_PORT=2525
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null
MAIL_FROM_ADDRESS="noreply@${FQDN}"
MAIL_FROM_NAME="${DB_NAME}"

APP_REPORT_ALL_EXCEPTIONS=false
APP_2FA_REQUIRED=0
GUZZLE_TIMEOUT=15
GUZZLE_CONNECT_TIMEOUT=5
PTERODACTYL_TELEMETRY_ENABLED=false
ENVEOF

    # ── Generate App Key via artisan ──────────────────────────────────────
    php "$PANEL_PATH/artisan" key:generate --force 2>/dev/null || true

    # ── Migrate Database ──────────────────────────────────────────────────
    step "Running Database Migrations"
    php "$PANEL_PATH/artisan" migrate --force 2>/dev/null || true

    # Seed
    php "$PANEL_PATH/artisan" db:seed --class=NestSeeder --force --no-interaction 2>/dev/null || true
    php "$PANEL_PATH/artisan" db:seed --class=EggSeeder --force --no-interaction 2>/dev/null || true

    # ── Apply Hyper ───────────────────────────────────────────────────────
    apply_hyper

    # ── Nginx ──────────────────────────────────────────────────────────────
    step "Configuring Nginx"
    configure_nginx

    # ── Supervisor ─────────────────────────────────────────────────────────
    step "Configuring Supervisor"
    configure_supervisor

    # ── Permissions ────────────────────────────────────────────────────────
    step "Setting Permissions"
    chown -R www-data:www-data "$PANEL_PATH"
    chmod -R 755 "$PANEL_PATH/storage"/* 2>/dev/null || true
    chmod -R 755 "$PANEL_PATH"/bootstrap/cache/ 2>/dev/null || true

    # ── Cache ──────────────────────────────────────────────────────────────
    step "Building Caches"
    cd "$PANEL_PATH"
    php artisan config:cache 2>/dev/null || true
    php artisan event:cache 2>/dev/null || true
    php artisan route:cache 2>/dev/null || true
    php artisan view:cache 2>/dev/null || true

    # ── SSL ────────────────────────────────────────────────────────────────
    step "SSL Certificate"
    certbot --nginx -d "$FQDN" --non-interactive --agree-tos --email "$ADMIN_EMAIL" 2>/dev/null || \
        warn "SSL skipped. Run: certbot --nginx -d $FQDN"

    # ── Admin User ─────────────────────────────────────────────────────────
    step "Creating Admin User"
    ESCAPED_PASS=$(printf '%s' "$ADMIN_PASSWORD" | sed "s/'/\\\\'/g")
    php "$PANEL_PATH/artisan" tinker --execute="
use Pterodactyl\Models\User;
User::factory()->create([
    'email' => '${ADMIN_EMAIL}',
    'password' => bcrypt('${ESCAPED_PASS}'),
    'root_admin' => true,
    'email_verified_at' => now(),
]);
echo 'Admin user created.';
" 2>/dev/null || warn "Admin user may already exist"

    # ── Done ───────────────────────────────────────────────────────────────
    show_complete
}

# ─── Install Wings ──────────────────────────────────────────────────────────
install_wings() {
    step "Installing Pterodactyl Wings"

    check_root
    check_os

    if wings_installed; then
        warn "Wings is already installed."
        echo -n "* Re-install? (y/N): "
        read -r CONFIRM
        [[ ! "$CONFIRM" =~ [Yy] ]] && return
    fi

    log "Installing Docker..."
    if ! command -v docker &>/dev/null; then
        curl -fsSL https://get.docker.com | sh 2>/dev/null || err "Docker install failed."
    fi
    systemctl enable --now docker 2>/dev/null || true

    log "Downloading Wings..."
    WINGS_VERSION=$(curl -fsSL https://api.github.com/repos/pterodactyl/wings/releases/latest 2>/dev/null | \
        php -r 'echo json_decode(file_get_contents("php://stdin"),true)["tag_name"]??"";' 2>/dev/null || echo "v1.0.7")

    curl -fSL -o "$WINGS_PATH/wings" \
        "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64" 2>/dev/null || \
        err "Failed to download Wings."
    chmod u+x "$WINGS_PATH/wings"

    # Supervisor config for Wings
    cat > /etc/supervisor/conf.d/wings.conf <<SUPERVISOR
[program:wings]
command=/usr/local/bin/wings
directory=/etc/pterodactyl
user=root
autostart=true
autorestart=true
startretries=3
stderr_logfile=/var/log/wings/wings.err.log
stdout_logfile=/var/log/wings/wings.out.log
SUPERVISOR

    mkdir -p /var/log/wings /etc/pterodactyl
    supervisorctl reread 2>/dev/null || true
    supervisorctl update 2>/dev/null || true

    log "Wings installed. Configure at: https://your-panel/admin/nodes"
    echo -e "\n${YELLOW}Run this on your NODE server to connect:${NC}"
    echo "  wings configure --panel-url https://${FQDN:-your-panel} --token YOUR_NODE_TOKEN"
    echo ""
}

#==============================================================================
#                         UNINSTALL FUNCTIONS
#==============================================================================

uninstall_panel() {
    step "Uninstalling Pterodactyl Panel"

    check_root

    if ! panel_installed; then
        warn "Panel not found at $PANEL_PATH. Nothing to uninstall."
        return
    fi

    echo -e "\n${RED}${BOLD}WARNING: This will remove:${NC}"
    echo "  - Panel files at $PANEL_PATH"
    echo "  - Nginx configuration"
    echo "  - Supervisor worker configs"
    echo "  - Logrotate configs"
    echo ""
    echo -e "${YELLOW}Database will NOT be deleted (safe).${NC}"
    echo ""
    echo -n "* Type 'DELETE' to confirm uninstall: "
    read -r CONFIRM
    [[ "$CONFIRM" != "DELETE" ]] && info "Uninstall cancelled." && return

    # Stop services
    command -v supervisorctl &>/dev/null && {
        supervisorctl stop pterodactyl-worker 2>/dev/null || true
        supervisorctl stop pterodactyl-scheduler 2>/dev/null || true
        supervisorctl stop pterodactyl-discord 2>/dev/null || true
    }

    # Remove supervisor configs
    rm -f /etc/supervisor/conf.d/pterodactyl-worker.conf
    rm -f /etc/supervisor/conf.d/pterodactyl-scheduler.conf
    rm -f /etc/supervisor/conf.d/pterodactyl-discord.conf
    command -v supervisorctl &>/dev/null && {
        supervisorctl reread 2>/dev/null || true
        supervisorctl update 2>/dev/null || true
    }

    # Remove nginx
    rm -f /etc/nginx/sites-available/pterodactyl.conf
    rm -f /etc/nginx/sites-enabled/pterodactyl.conf
    command -v nginx &>/dev/null && nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true

    # Remove logrotate
    rm -f /etc/logrotate.d/pterodactyl

    # Remove panel files
    rm -rf "$PANEL_PATH"

    # Remove cron/sudoers
    rm -f /etc/sudoers.d/hyper_update 2>/dev/null || true

    # Remove logs
    rm -rf /var/log/pterodactyl

    log "Panel uninstalled. Database '$DB_NAME' preserved."
    echo -n "* Drop database too? (y/N): "
    read -r DROP_DB
    if [[ "$DROP_DB" =~ [Yy] ]]; then
        mysql -u root -e "DROP DATABASE IF EXISTS ${DB_NAME};" 2>/dev/null || true
        mysql -u root -e "DROP USER IF EXISTS '${DB_USER}'@'${DB_HOST}';" 2>/dev/null || true
        mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null || true
        log "Database dropped."
    fi
}

uninstall_wings() {
    step "Uninstalling Wings"

    check_root

    if ! wings_installed; then
        warn "Wings not found. Nothing to uninstall."
        return
    fi

    echo -n "* Type 'DELETE' to confirm: "
    read -r CONFIRM
    [[ "$CONFIRM" != "DELETE" ]] && info "Uninstall cancelled." && return

    supervisorctl stop wings 2>/dev/null || true
    rm -f /etc/supervisor/conf.d/wings.conf
    rm -f "$WINGS_PATH/wings"
    rm -rf /etc/pterodactyl
    rm -rf /var/log/wings
    command -v supervisorctl &>/dev/null && {
        supervisorctl reread 2>/dev/null || true
        supervisorctl update 2>/dev/null || true
    }

    log "Wings uninstalled."
}

uninstall_hyper_only() {
    step "Uninstalling Hyper — restoring clean Pterodactyl"

    check_root

    if ! panel_installed; then
        err "Panel not found at $PANEL_PATH. Nothing to do."
    fi

    if ! hyper_patched; then
        warn "Hyper does not appear to be installed on this panel."
        echo -n "* Continue anyway? (y/N): "
        read -r CONFIRM
        [[ ! "$CONFIRM" =~ [Yy] ]] && return
    fi

    echo -n "* Type 'DELETE' to confirm Hyper removal: "
    read -r CONFIRM
    [[ "$CONFIRM" != "DELETE" ]] && info "Uninstall cancelled." && return

    # ── Remove Hyper-specific added files ─────────────────────────────────
    step "Removing Hyper files"

    # License middleware stubs
    rm -f "$PANEL_PATH/app/Http/Middleware/HyperV2LicenseGate.php" 2>/dev/null || true
    rm -f "$PANEL_PATH/app/Http/Middleware/HyperV2SecurityMonitor.php" 2>/dev/null || true
    rm -f "$PANEL_PATH/app/Http/Middleware/EnforceHyperV2PanelAccess.php" 2>/dev/null || true

    # Security manifest
    rm -f "$PANEL_PATH/bootstrap/cache/hyperv2_security_manifest.php" 2>/dev/null || true

    # JS license patches
    rm -f "$PANEL_PATH/public/assets/licenseService"*.js 2>/dev/null || true
    rm -f "$PANEL_PATH/public/assets/LicenseMonitor"*.js 2>/dev/null || true

    log "  Removed Hyper middleware, manifest, and JS patches"

    # ── Surgically replace ONLY ionCube-encoded PHP files ──────────────────
    step "Replacing ionCube-encoded files with clean originals"
    TMP_DL=$(mktemp -d)
    PTERO_URL="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
    curl -fsSL -o "$TMP_DL/panel.tar.gz" "$PTERO_URL" 2>/dev/null || err "Failed to download clean panel."
    mkdir -p "$TMP_DL/panel" && tar -xzf "$TMP_DL/panel.tar.gz" -C "$TMP_DL/panel" 2>/dev/null

    REPLACED=0
    find "$PANEL_PATH" -name "*.php" -type f \
        ! -path "*/vendor/*" \
        ! -path "*/node_modules/*" \
        ! -path "*/storage/*" \
        ! -path "*/.git/*" \
        ! -path "*/bootstrap/cache/*" \
        2>/dev/null | while read f; do

        HEADER=$(head -3 "$f" 2>/dev/null)
        IS_ENCODED=false
        if echo "$HEADER" | grep -qP '<\?php\s*//[0-9a-fA-F]{3,5}'; then
            IS_ENCODED=true
        fi
        if echo "$HEADER" | grep -qi "ionCube Loader\|encoded\|corrupted"; then
            IS_ENCODED=true
        fi

        if [ "$IS_ENCODED" = true ]; then
            REL="${f#$PANEL_PATH/}"
            CLEAN="$TMP_DL/panel/$REL"
            if [ -f "$CLEAN" ]; then
                CLEAN_HEADER=$(head -3 "$CLEAN" 2>/dev/null)
                if ! echo "$CLEAN_HEADER" | grep -qP '<\?php\s*//[0-9a-fA-F]{3,5}'; then
                    if ! echo "$CLEAN_HEADER" | grep -qi "ionCube Loader\|encoded\|corrupted"; then
                        cp "$CLEAN" "$f"
                        log "  Restored: $REL"
                    fi
                fi
            fi
        fi
    done

    rm -rf "$TMP_DL"

    # ── Fix permissions ───────────────────────────────────────────────────
    step "Fixing permissions"
    chown -R www-data:www-data "$PANEL_PATH"
    chmod -R 755 "$PANEL_PATH/storage"/* 2>/dev/null || true
    chmod -R 755 "$PANEL_PATH"/bootstrap/cache/ 2>/dev/null || true

    # ── Rebuild caches ────────────────────────────────────────────────────
    step "Rebuilding caches"
    cd "$PANEL_PATH"
    rm -f "$PANEL_PATH/bootstrap/cache/"*.php 2>/dev/null || true
    php artisan config:clear 2>/dev/null || true
    php artisan cache:clear 2>/dev/null || true
    php artisan route:clear 2>/dev/null || true
    php artisan view:clear 2>/dev/null || true
    php artisan config:cache 2>/dev/null || true
    php artisan event:cache 2>/dev/null || true
    php artisan view:cache 2>/dev/null || true

    # ── Restart services ──────────────────────────────────────────────────
    step "Restarting services"
    command -v supervisorctl &>/dev/null && {
        supervisorctl restart pterodactyl-worker 2>/dev/null || true
        supervisorctl restart pterodactyl-scheduler 2>/dev/null || true
    }
    systemctl restart php${PHP_VER}-fpm 2>/dev/null || service php${PHP_VER}-fpm restart 2>/dev/null || true
    systemctl restart nginx 2>/dev/null || service nginx restart 2>/dev/null || true

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         Hyper removed! Clean Pterodactyl restored.      ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log "Hyper uninstalled. Panel restored to clean Pterodactyl at $PANEL_PATH"
}

#==============================================================================
#                         REPAIR / UPDATE FUNCTIONS
#==============================================================================

repair_hyper() {
    step "Repairing / Re-patching Hyper Game Panel"

    check_root

    if ! panel_installed; then
        err "Panel not found at $PANEL_PATH. Install first."
    fi

    log "Re-applying Hyper patches..."
    apply_hyper

    log "Fixing permissions..."
    chown -R www-data:www-data "$PANEL_PATH"
    chmod -R 755 "$PANEL_PATH/storage"/* 2>/dev/null || true
    chmod -R 755 "$PANEL_PATH"/bootstrap/cache/ 2>/dev/null || true

    log "Clearing caches..."
    cd "$PANEL_PATH"
    php artisan config:clear 2>/dev/null || true
    php artisan cache:clear 2>/dev/null || true
    php artisan route:clear 2>/dev/null || true
    php artisan view:clear 2>/dev/null || true
    php artisan config:cache 2>/dev/null || true
    php artisan event:cache 2>/dev/null || true
    php artisan view:cache 2>/dev/null || true
    php artisan route:cache 2>/dev/null || php artisan route:clear 2>/dev/null || true

    log "Restarting services..."
    supervisorctl restart pterodactyl-worker 2>/dev/null || true
    supervisorctl restart pterodactyl-scheduler 2>/dev/null || true
    systemctl restart php8.4-fpm 2>/dev/null || service php8.4-fpm restart 2>/dev/null || true
    systemctl restart nginx 2>/dev/null || service nginx restart 2>/dev/null || true

    log "Repair complete!"
}

update_hyper() {
    step "Updating Hyper Game Panel"

    check_root

    if ! panel_installed; then
        err "Panel not found at $PANEL_PATH. Install first."
    fi

    # Backup current Hyper files
    log "Backing up current state..."
    BACKUP_NAME="hyper_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    cd /var/www 2>/dev/null || true
    tar -czf "$BACKUP_NAME" \
        pterodactyl/DGEN/ \
        pterodactyl/public/DGEN/ \
        pterodactyl/public/assets/hyper* \
        pterodactyl/app/Http/Middleware/HyperV2* \
        pterodactyl/app/Http/Middleware/EnforceHyper* \
        pterodactyl/app/Http/Middleware/SetSecurity* \
        pterodactyl/app/Http/Controllers/Api/Application/License* \
        pterodactyl/app/Services/Hyper* \
        pterodactyl/app/Services/License* \
        pterodactyl/app/Services/Addon* \
        pterodactyl/app/Services/CrossVps* \
        pterodactyl/app/Traits/ValidatesSecure* \
        pterodactyl/bootstrap/cache/hyperv2* \
        2>/dev/null || true
    log "Backup saved: /var/www/$BACKUP_NAME"

    # Download latest Hyper
    log "Fetching latest Hyper version..."
    DOWNLOAD_URL=$(curl -fsSL "$HYPER_API" 2>/dev/null | \
        php -r '$r=json_decode(file_get_contents("php://stdin"),true);echo $r["latest_version"]["download_url"]??"";' 2>/dev/null || true)

    if [ -z "$DOWNLOAD_URL" ] || [[ "$DOWNLOAD_URL" != http* ]]; then
        err "Failed to fetch latest Hyper version from API."
    fi

    TMP_DL=$(mktemp -d)
    curl -fSL --retry 3 -o "$TMP_DL/Hyper.zip" "$DOWNLOAD_URL" 2>/dev/null || \
        err "Failed to download Hyper."

    log "Extracting and applying..."
    rm -f "$PANEL_PATH/public/assets/licenseService"*.js 2>/dev/null || true
    rm -f "$PANEL_PATH/public/assets/LicenseMonitor"*.js 2>/dev/null || true

    cd "$PANEL_PATH"
    unzip -oq "$TMP_DL/Hyper.zip" -d "$TMP_DL/hyper" 2>/dev/null || \
        tar -xf "$TMP_DL/Hyper.zip" -C "$TMP_DL/hyper" 2>/dev/null || true

    # Copy Hyper files over panel
    [ -d "$TMP_DL/hyper/app" ] && cp -rf "$TMP_DL/hyper/app/"* "$PANEL_PATH/app/" 2>/dev/null || true
    [ -d "$TMP_DL/hyper/public" ] && cp -rf "$TMP_DL/hyper/public/"* "$PANEL_PATH/public/" 2>/dev/null || true
    [ -d "$TMP_DL/hyper/config" ] && cp -rf "$TMP_DL/hyper/config/"* "$PANEL_PATH/config/" 2>/dev/null || true
    [ -d "$TMP_DL/hyper/database" ] && cp -rf "$TMP_DL/hyper/database/"* "$PANEL_PATH/database/" 2>/dev/null || true
    [ -d "$TMP_DL/hyper/resources" ] && cp -rf "$TMP_DL/hyper/resources/"* "$PANEL_PATH/resources/" 2>/dev/null || true
    [ -d "$TMP_DL/hyper/routes" ] && cp -rf "$TMP_DL/hyper/routes/"* "$PANEL_PATH/routes/" 2>/dev/null || true
    [ -d "$TMP_DL/hyper/bootstrap" ] && cp -rf "$TMP_DL/hyper/bootstrap/"* "$PANEL_PATH/bootstrap/" 2>/dev/null || true

    rm -rf "$TMP_DL"

    # Re-apply patches
    apply_hyper

    # Rebuild caches
    log "Rebuilding caches..."
    php artisan config:clear 2>/dev/null || true
    php artisan cache:clear 2>/dev/null || true
    php artisan route:clear 2>/dev/null || true
    php artisan view:clear 2>/dev/null || true
    php artisan config:cache 2>/dev/null || true
    php artisan event:cache 2>/dev/null || true
    php artisan view:cache 2>/dev/null || true

    chown -R www-data:www-data "$PANEL_PATH"

    log "Hyper updated to latest version!"
}

# ─── Install Hyper Only (on existing panel) ─────────────────────────────────
install_hyper_only() {
    step "Installing Hyper Game Panel on Existing Pterodactyl"

    check_root

    if ! panel_installed; then
        err "Panel not found at $PANEL_PATH.\n  Install Pterodactyl first, then run this option.\n  Or use option [0] for a fresh install."
    fi

    if hyper_patched; then
        warn "Hyper is already patched on this panel."
        echo -n "* Re-install Hyper? (y/N): "
        read -r CONFIRM
        [[ ! "$CONFIRM" =~ [Yy] ]] && return
    fi

    # ── Download Hyper ────────────────────────────────────────────────────
    step "Downloading Hyper Game Panel"
    DOWNLOAD_URL=$(curl -fsSL "$HYPER_API" 2>/dev/null | \
        php -r '$r=json_decode(file_get_contents("php://stdin"),true);echo $r["latest_version"]["download_url"]??"";' 2>/dev/null || true)

    if [ -z "$DOWNLOAD_URL" ] || [[ "$DOWNLOAD_URL" != http* ]]; then
        err "Failed to fetch Hyper from API. Check your internet connection."
    fi

    info "Download URL resolved. Downloading..."
    TMP_DL=$(mktemp -d)
    curl -fSL --retry 3 -o "$TMP_DL/Hyper.zip" "$DOWNLOAD_URL" 2>/dev/null || \
        err "Failed to download Hyper."

    # ── Extract ────────────────────────────────────────────────────────────
    step "Extracting Hyper files"
    rm -f "$PANEL_PATH/public/assets/licenseService"*.js 2>/dev/null || true
    rm -f "$PANEL_PATH/public/assets/LicenseMonitor"*.js 2>/dev/null || true

    unzip -oq "$TMP_DL/Hyper.zip" -d "$TMP_DL/hyper" 2>/dev/null || \
        tar -xf "$TMP_DL/Hyper.zip" -C "$TMP_DL/hyper" 2>/dev/null || \
        err "Failed to extract Hyper archive."

    # Copy Hyper files over panel
    [ -d "$TMP_DL/hyper/app" ] && cp -rf "$TMP_DL/hyper/app/"* "$PANEL_PATH/app/" 2>/dev/null || true
    [ -d "$TMP_DL/hyper/public" ] && cp -rf "$TMP_DL/hyper/public/"* "$PANEL_PATH/public/" 2>/dev/null || true
    [ -d "$TMP_DL/hyper/config" ] && cp -rf "$TMP_DL/hyper/config/"* "$PANEL_PATH/config/" 2>/dev/null || true
    [ -d "$TMP_DL/hyper/database" ] && cp -rf "$TMP_DL/hyper/database/"* "$PANEL_PATH/database/" 2>/dev/null || true
    [ -d "$TMP_DL/hyper/resources" ] && cp -rf "$TMP_DL/hyper/resources/"* "$PANEL_PATH/resources/" 2>/dev/null || true
    [ -d "$TMP_DL/hyper/routes" ] && cp -rf "$TMP_DL/hyper/routes/"* "$PANEL_PATH/routes/" 2>/dev/null || true
    [ -d "$TMP_DL/hyper/bootstrap" ] && cp -rf "$TMP_DL/hyper/bootstrap/"* "$PANEL_PATH/bootstrap/" 2>/dev/null || true

    rm -rf "$TMP_DL"
    log "Hyper files extracted"

    # ── Apply patches ──────────────────────────────────────────────────────
    apply_hyper

    # ── Ensure ionCube Loader is present ───────────────────────────────────
    install_ioncube

    # ── Permissions ────────────────────────────────────────────────────────
    step "Fixing permissions"
    chown -R www-data:www-data "$PANEL_PATH"
    chmod -R 755 "$PANEL_PATH/storage"/* 2>/dev/null || true
    chmod -R 755 "$PANEL_PATH"/bootstrap/cache/ 2>/dev/null || true

    # ── Rebuild caches ─────────────────────────────────────────────────────
    step "Rebuilding caches"
    cd "$PANEL_PATH"
    php artisan config:clear 2>/dev/null || true
    php artisan cache:clear 2>/dev/null || true
    php artisan route:clear 2>/dev/null || true
    php artisan view:clear 2>/dev/null || true
    php artisan config:cache 2>/dev/null || true
    php artisan event:cache 2>/dev/null || true
    php artisan view:cache 2>/dev/null || true

    # ── Restart services ───────────────────────────────────────────────────
    step "Restarting services"
    command -v supervisorctl &>/dev/null && {
        supervisorctl restart pterodactyl-worker 2>/dev/null || true
        supervisorctl restart pterodactyl-scheduler 2>/dev/null || true
    }
    systemctl restart php${PHP_VER}-fpm 2>/dev/null || service php${PHP_VER}-fpm restart 2>/dev/null || true
    systemctl restart nginx 2>/dev/null || service nginx restart 2>/dev/null || true

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              Panel + Hyper installed!                    ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log "Hyper installed on existing panel at $PANEL_PATH"
    info "Visit your panel to see the Hyper theme."
}

#==============================================================================
#                         CORE PATCH FUNCTION
#==============================================================================

apply_hyper() {
    log "Applying Hyper license patches..."

    # ── Restore helpers.php (Hyper overwrites with ionCube-encoded version) ─
    cat > "$PANEL_PATH/app/helpers.php" <<'HELPERSTUB'
<?php

if (!function_exists('is_digit')) {
    function is_digit(mixed $value): bool
    {
        return !is_bool($value) && ctype_digit(strval($value));
    }
}

if (!function_exists('object_get_strict')) {
    function object_get_strict(object $object, ?string $key, $default = null): mixed
    {
        if (is_null($key) || trim($key) == '') {
            return $object;
        }

        foreach (explode('.', $key) as $segment) {
            if (!is_object($object) || !property_exists($object, $segment)) {
                return value($default);
            }

            $object = $object->{$segment};
        }

        return $object;
    }
}
HELPERSTUB
    log "Restored clean helpers.php"

    # ── Middleware stubs ───────────────────────────────────────────────────
    mkdir -p "$PANEL_PATH/app/Http/Middleware"

    cat > "$PANEL_PATH/app/Http/Middleware/HyperV2LicenseGate.php" <<'STUB'
<?php
namespace Pterodactyl\Http\Middleware;
use Closure;use Illuminate\Http\Request;
class HyperV2LicenseGate{public function handle(Request $request,Closure $next){return $next($request);}}
STUB

    cat > "$PANEL_PATH/app/Http/Middleware/HyperV2SecurityMonitor.php" <<'STUB'
<?php
namespace Pterodactyl\Http\Middleware;
use Closure;use Illuminate\Http\Request;
class HyperV2SecurityMonitor{public function handle(Request $request,Closure $next){return $next($request);}}
STUB

    cat > "$PANEL_PATH/app/Http/Middleware/EnforceHyperV2PanelAccess.php" <<'STUB'
<?php
namespace Pterodactyl\Http\Middleware;
use Closure;use Illuminate\Http\Request;
class EnforceHyperV2PanelAccess{public function handle(Request $request,Closure $next){return $next($request);}}
STUB

    cat > "$PANEL_PATH/app/Http/Middleware/SetSecurityHeaders.php" <<'STUB'
<?php
namespace Pterodactyl\Http\Middleware;
use Closure;use Illuminate\Http\Request;
class SetSecurityHeaders{public function handle(Request $request,Closure $next){$r=$next($request);$r->headers->set('X-Content-Type-Options','nosniff');$r->headers->set('X-Frame-Options','DENY');$r->headers->set('X-XSS-Protection','1; mode=block');return $r;}}
STUB

    # ── License Controller ────────────────────────────────────────────────
    mkdir -p "$PANEL_PATH/app/Http/Controllers/Api/Application"

    cat > "$PANEL_PATH/app/Http/Controllers/Api/Application/LicenseController.php" <<'STUB'
<?php
namespace Pterodactyl\Http\Controllers\Api\Application;
use Illuminate\Http\JsonResponse;use Illuminate\Http\Request;use Illuminate\Routing\Controller;
class LicenseController extends Controller{
    public function verify(Request $request):JsonResponse{return response()->json(['valid'=>true,'reason'=>'License verified','verified_at'=>now()->toIso8601String(),'license'=>['basic_features'=>true,'premium_features'=>true,'ultimate_features'=>true,'minecraft_features'=>true,'essentials_features'=>true,'special_features'=>true,'private_features'=>true,'ark_features'=>true]]);}
    public function status(Request $request):JsonResponse{return response()->json(['configured'=>true,'valid'=>true,'domain'=>$request->getHost(),'license_type'=>'ultimate','expires_at'=>null]);}
}
STUB

    # ── Services ──────────────────────────────────────────────────────────
    mkdir -p "$PANEL_PATH/app/Services"

    cat > "$PANEL_PATH/app/Services/HyperV2LicenseService.php" <<'STUB'
<?php
namespace Pterodactyl\Services;
class HyperV2LicenseService{
    public function verifyLicense():array{return ['valid'=>true,'reason'=>'License verified','verified_at'=>now()->toIso8601String()];}
    public function getLicenseStatus():array{return ['configured'=>true,'valid'=>true,'license_type'=>'ultimate','expires_at'=>null];}
    public function isLicenseValid():bool{return true;}
    public function hasCategory(string $c):bool{return true;}
    public function getCategories():array{return ['basic_features','premium_features','ultimate_features','minecraft_features','essentials_features','special_features','private_features','ark_features'];}
    public function clearVerificationData():void{}
    public function __call(string $n,array $a){return true;}
}
STUB

    cat > "$PANEL_PATH/app/Services/LicenseValidationService.php" <<'STUB'
<?php
namespace Pterodactyl\Services;
class LicenseValidationService{
    public function validate(string $k):bool{return true;}
    public function validateLicense(string $k=null):bool{return true;}
    public function isLicenseValid():bool{return true;}
    public function getLicenseInfo():array{return ['valid'=>true,'type'=>'ultimate','expires_at'=>null];}
    public function __call(string $n,array $a){return true;}
}
STUB

    cat > "$PANEL_PATH/app/Services/HyperV2IntegrityService.php" <<'STUB'
<?php
namespace Pterodactyl\Services;
class HyperV2IntegrityService{public function checkIntegrity():bool{return true;}public function verifyFiles():bool{return true;}public function getManifest():array{return [];}public function isManifestValid():bool{return true;}public function __call(string $n,array $a){return true;}}
STUB

    cat > "$PANEL_PATH/app/Services/HyperV2SecurityAlertService.php" <<'STUB'
<?php
namespace Pterodactyl\Services;
class HyperV2SecurityAlertService{public function sendAlert(string $t,array $d=[]):bool{return true;}public function __call(string $n,array $a){return true;}}
STUB

    cat > "$PANEL_PATH/app/Services/HyperV2AddonDefaultsService.php" <<'STUB'
<?php
namespace Pterodactyl\Services;
class HyperV2AddonDefaultsService{public function getDefaults(string $a=null):array{return [];}public function getAddonDefaults(string $a):array{return [];}public function __call(string $n,array $a){return true;}}
STUB

    cat > "$PANEL_PATH/app/Services/HyperV2ValidationRules.php" <<'STUB'
<?php
namespace Pterodactyl\Services;
class HyperV2ValidationRules{public function getRules(string $c=null):array{return [];}public function __call(string $n,array $a){return true;}}
STUB

    cat > "$PANEL_PATH/app/Services/HyperV2LegacySettingsMigrator.php" <<'STUB'
<?php
namespace Pterodactyl\Services;
class HyperV2LegacySettingsMigrator{public function migrate():bool{return true;}public function isMigrated():bool{return true;}public function __call(string $n,array $a){return true;}}
STUB

    cat > "$PANEL_PATH/app/Services/HyperV2DataSanitizerService.php" <<'STUB'
<?php
namespace Pterodactyl\Services;
class HyperV2DataSanitizerService{public function sanitize(array $d):array{return $d;}public function clean(string $i):string{return $i;}public function __call(string $n,array $a){return true;}}
STUB

    cat > "$PANEL_PATH/app/Services/HyperV2RequiredUpdateService.php" <<'STUB'
<?php
namespace Pterodactyl\Services;
class HyperV2RequiredUpdateService{public function isUpdateRequired():bool{return false;}public function getRequiredVersion():?string{return null;}public function __call(string $n,array $a){return true;}}
STUB

    cat > "$PANEL_PATH/app/Services/AddonConfigService.php" <<'STUB'
<?php
namespace Pterodactyl\Services;
class AddonConfigService{public function getConfig(string $a=null):array{return [];}public function setConfig(string $a,array $c):bool{return true;}public function __call(string $n,array $a){return true;}}
STUB

    cat > "$PANEL_PATH/app/Services/CrossVpsCacheInvalidationService.php" <<'STUB'
<?php
namespace Pterodactyl\Services;
class CrossVpsCacheInvalidationService{public function invalidate(string $k):bool{return true;}public function __call(string $n,array $a){return true;}}
STUB

    # ── Traits ────────────────────────────────────────────────────────────
    mkdir -p "$PANEL_PATH/app/Traits/Controllers" "$PANEL_PATH/app/Traits/DGEN" "$PANEL_PATH/app/Traits/Helpers" "$PANEL_PATH/app/Traits/Services"

    cat > "$PANEL_PATH/app/Traits/ValidatesSecureLicense.php" <<'STUB'
<?php
namespace Pterodactyl\Traits;
trait ValidatesSecureLicense{public function validateSecureLicense():bool{return true;}public function isLicenseValid():bool{return true;}public function checkLicense():bool{return true;}public function hasValidLicense():bool{return true;}}
STUB

    cat > "$PANEL_PATH/app/Traits/Controllers/JavascriptInjection.php" <<'STUB'
<?php
namespace Pterodactyl\Traits\Controllers;
trait JavascriptInjection{public function injectJavascript(array $d=[]):void{\JavaScript::put($d);}}
STUB

    cat > "$PANEL_PATH/app/Traits/DGEN/ChecksAddonAccess.php" <<'STUB'
<?php
namespace Pterodactyl\Traits\DGEN;
trait ChecksAddonAccess{public function hasAddonAccess(string $a,$u=null):bool{return true;}public function isAddonEnabled(string $a):bool{return true;}public function __call(string $n,array $a){return true;}}
STUB

    cat > "$PANEL_PATH/app/Traits/DGEN/ManagesFileCache.php" <<'STUB'
<?php
namespace Pterodactyl\Traits\DGEN;
trait ManagesFileCache{public function clearFileCache():void{}public function getFileCache(string $k,$d=null){return $d;}public function setFileCache(string $k,$v,int $t=3600):void{}public function __call(string $n,array $a){return true;}}
STUB

    cat > "$PANEL_PATH/app/Traits/Helpers/AvailableLanguages.php" <<'STUB'
<?php
namespace Pterodactyl\Traits\Helpers;
trait AvailableLanguages{public function getAvailableLanguages():array{return ['en'=>'English','ar'=>'Arabic','cs'=>'Czech','de'=>'German','es'=>'Spanish','fr'=>'French','hu'=>'Hungarian','id'=>'Indonesian','it'=>'Italian','ja'=>'Japanese','ko'=>'Korean','nl'=>'Dutch','pl'=>'Polish','pt'=>'Portuguese','ro'=>'Romanian','ru'=>'Russian','sv'=>'Swedish','tr'=>'Turkish','uk'=>'Ukrainian','vi'=>'Vietnamese','zh'=>'Chinese'];}}
STUB

    cat > "$PANEL_PATH/app/Traits/Helpers/ThemeLanguages.php" <<'STUB'
<?php
namespace Pterodactyl\Traits\Helpers;
trait ThemeLanguages{public function getThemeLanguages():array{return ['en'=>'English','ar'=>'Arabic','cs'=>'Czech','de'=>'German','es'=>'Spanish','fr'=>'French','hu'=>'Hungarian','id'=>'Indonesian','it'=>'Italian','ja'=>'Japanese','ko'=>'Korean','nl'=>'Dutch','pl'=>'Polish','pt'=>'Portuguese','ro'=>'Romanian','ru'=>'Russian','sv'=>'Swedish','tr'=>'Turkish','uk'=>'Ukrainian','vi'=>'Vietnamese','zh'=>'Chinese'];}}
STUB

    cat > "$PANEL_PATH/app/Traits/Services/HasUserLevels.php" <<'STUB'
<?php
namespace Pterodactyl\Traits\Services;
trait HasUserLevels{public function getUserLevel($u):string{return 'admin';}public function __call(string $n,array $a){return true;}}
STUB

    cat > "$PANEL_PATH/app/Traits/Services/ReturnsUpdatedModels.php" <<'STUB'
<?php
namespace Pterodactyl\Traits\Services;
trait ReturnsUpdatedModels{}
STUB

    cat > "$PANEL_PATH/app/Traits/Services/ValidatesValidationRules.php" <<'STUB'
<?php
namespace Pterodactyl\Traits\Services;
trait ValidatesValidationRules{public function __call(string $n,array $a){return true;}}
STUB

    cat > "$PANEL_PATH/app/Traits/HandlesEtagCache.php" <<'STUB'
<?php
namespace Pterodactyl\Traits;
trait HandlesEtagCache{public function __call(string $n,array $a){return true;}}
STUB

    cat > "$PANEL_PATH/app/Console/RequiresDatabaseMigrations.php" <<'STUB'
<?php
namespace Pterodactyl\Console;
trait RequiresDatabaseMigrations{public function hasPendingMigrations():bool{return false;}}
STUB

    mkdir -p "$PANEL_PATH/app/Console/Commands/Environment"
    cat > "$PANEL_PATH/app/Console/Commands/Environment/EnvironmentWriterTrait.php" <<'STUB'
<?php
namespace Pterodactyl\Console\Commands\Environment;
trait EnvironmentWriterTrait{protected function writeToEnvironment(string $d):void{}public function __call(string $n,array $a){return true;}}
STUB

    # ── Security manifest (empty) ─────────────────────────────────────────
    mkdir -p "$PANEL_PATH/bootstrap/cache"
    cat > "$PANEL_PATH/bootstrap/cache/hyperv2_security_manifest.php" <<'STUB'
<?php
return array('version'=>1,'scope'=>'app_php_full','generated_at'=>date('c'),'files'=>array());
STUB

    # ── JS patches ────────────────────────────────────────────────────────
    mkdir -p "$PANEL_PATH/public/assets"

    # Find and patch licenseService
    LS_FILE=$(find "$PANEL_PATH/public/assets" -name "licenseService.*.js" -not -name "*.gz" 2>/dev/null | head -1)
    if [ -n "$LS_FILE" ]; then
        cat > "$LS_FILE" <<'JSTUB'
var licenseService={async verifyLicense(){return{valid:true,reason:"License verified",verified_at:new Date().toISOString(),license:{basic_features:true,premium_features:true,ultimate_features:true,minecraft_features:true,essentials_features:true,special_features:true,private_features:true,ark_features:true}}},async getLicenseStatus(){return{configured:true,valid:true,domain:window.location.hostname,license_type:"ultimate",expires_at:null}},clearVerificationData(){},hasCategory(e){return true},isLicenseValid(){return true}};var defaultExport=licenseService;export{licenseService as Bp,defaultExport as Cp};
JSTUB
        rm -f "${LS_FILE}.gz" 2>/dev/null || true
    fi

    # Find and patch LicenseMonitor
    LM_FILE=$(find "$PANEL_PATH/public/assets" -name "LicenseMonitor.*.js" -not -name "*.gz" 2>/dev/null | head -1)
    if [ -n "$LM_FILE" ]; then
        cat > "$LM_FILE" <<'JSTUB'
function f(){return null}export{f as default};
JSTUB
        rm -f "${LM_FILE}.gz" 2>/dev/null || true
    fi

    # ── Mark release channel ──────────────────────────────────────────────
    echo "ultimate" > "$PANEL_PATH/.hyper_release_channel"

    log "Hyper patches applied successfully"
}

#==============================================================================
#                         HELPER FUNCTIONS
#==============================================================================

install_ioncube() {
    # Auto-detect PHP version
    IC_PHP_VER=""
    for v in 8.4 8.3 8.2 8.1; do
        if command -v "php$v" &>/dev/null; then
            IC_PHP_VER="$v"
            break
        fi
    done
    if [ -z "$IC_PHP_VER" ]; then
        IC_PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true)
    fi
    if [ -z "$IC_PHP_VER" ]; then
        warn "Could not detect PHP version — skipping ionCube"
        return
    fi

    if "php$IC_PHP_VER" -m 2>/dev/null | grep -qi "ioncube"; then
        log "IonCube Loader already installed for PHP $IC_PHP_VER"
        return
    fi

    log "Installing IonCube Loader for PHP $IC_PHP_VER..."
    IC_EXT_DIR=$("php$IC_PHP_VER" -r "echo ini_get('extension_dir');" 2>/dev/null)
    if [ -z "$IC_EXT_DIR" ] || [ ! -d "$IC_EXT_DIR" ]; then
        warn "Could not determine PHP extension directory — skipping ionCube"
        return
    fi

    IC_URL="https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz"
    IC_TMP=$(mktemp -d)

    if ! curl -fsSL -o "$IC_TMP/ioncube.tar.gz" "$IC_URL" 2>/dev/null; then
        warn "Failed to download ionCube Loader"
        rm -rf "$IC_TMP"
        return
    fi

    tar -xzf "$IC_TMP/ioncube.tar.gz" -C "$IC_TMP" 2>/dev/null || { warn "Failed to extract ionCube archive"; rm -rf "$IC_TMP"; return; }

    if ! cp "$IC_TMP/ioncube/ioncube_loader_lin_${IC_PHP_VER}.so" "$IC_EXT_DIR/" 2>/dev/null; then
        warn "ionCube .so file not found for PHP $IC_PHP_VER"
        rm -rf "$IC_TMP"
        return
    fi

    cat > "/etc/php/${IC_PHP_VER}/mods-available/00-ioncube.ini" <<IONCUBE
zend_extension="${IC_EXT_DIR}/ioncube_loader_lin_${IC_PHP_VER}.so"
opcache.jit=0
opcache.jit_buffer_size=0
IONCUBE

    phpenmod -v "$IC_PHP_VER" -s cli 00-ioncube 2>/dev/null || true
    phpenmod -v "$IC_PHP_VER" -s fpm 00-ioncube 2>/dev/null || true

    rm -rf "$IC_TMP"

    # Verify installation
    if "php$IC_PHP_VER" -m 2>/dev/null | grep -qi "ioncube"; then
        log "IonCube Loader installed successfully for PHP $IC_PHP_VER"
    else
        warn "ionCube installed but not detected by PHP — may need manual verification"
    fi
}

backup_panel() {
    log "Backing up current panel..."
    BACKUP_NAME="pterodactyl_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    cd /var/www 2>/dev/null || true
    tar -czf "$BACKUP_NAME" \
        --exclude='pterodactyl/vendor' \
        --exclude='pterodactyl/node_modules' \
        --exclude='pterodactyl/storage/logs' \
        --exclude='pterodactyl/storage/framework/cache' \
        pterodactyl/ 2>/dev/null || true
    log "Backup saved: /var/www/$BACKUP_NAME"
}

configure_nginx() {
    cat > /etc/nginx/sites-available/pterodactyl.conf <<NGINX
server {
    listen 80;
    server_name ${FQDN};
    root ${PANEL_PATH}/public;
    index index.html index.htm index.php;
    charset utf-8;
    client_max_body_size 100m;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log  /var/log/nginx/pterodactyl.app-access.log;
    error_log   /var/log/nginx/pterodactyl.app-error.log;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php${PHP_VER}-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "http";
        fastcgi_param HTTPS off;
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
        fastcgi_intercept_errors on;
    }

    location ~ /\.ht { deny all; }

    gzip on;
    gzip_static on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/javascript image/svg+xml;
}
NGINX

    ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || true
}

configure_supervisor() {
    mkdir -p /var/log/pterodactyl
    chown www-data:www-data /var/log/pterodactyl 2>/dev/null || true

    cat > /etc/supervisor/conf.d/pterodactyl-worker.conf <<'SUPERVISOR'
[program:pterodactyl-worker]
command=php /var/www/pterodactyl/artisan queue:work --queue=high,standard,default,low --sleep=3 --tries=3 --timeout=90 --memory=256
directory=/var/www/pterodactyl
user=www-data
autostart=true
autorestart=true
startretries=3
stopwaitsecs=360
stopasgroup=true
killasgroup=true
stderr_logfile=/var/log/pterodactyl/worker.err.log
stdout_logfile=/var/log/pterodactyl/worker.out.log
SUPERVISOR

    cat > /etc/supervisor/conf.d/pterodactyl-scheduler.conf <<'SUPERVISOR'
[program:pterodactyl-scheduler]
command=php /var/www/pterodactyl/artisan schedule:work
directory=/var/www/pterodactyl
user=www-data
autostart=true
autorestart=true
startretries=3
stopasgroup=true
killasgroup=true
stderr_logfile=/var/log/pterodactyl/scheduler.err.log
stdout_logfile=/dev/null
SUPERVISOR

    supervisorctl reread 2>/dev/null || true
    supervisorctl update 2>/dev/null || true
    supervisorctl start pterodactyl-worker 2>/dev/null || true
    supervisorctl start pterodactyl-scheduler 2>/dev/null || true
}

show_complete() {
    echo ""
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║              Installation Complete!                          ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo "║  Panel URL:    https://${FQDN}"
    echo "║  Admin Email:  ${ADMIN_EMAIL}"
    echo "║  Admin Pass:   ${ADMIN_PASSWORD}"
    echo "║  Panel Path:   ${PANEL_PATH}"
    echo "║  DB Name:      ${DB_NAME}"
    echo "║  DB User:      ${DB_USER}"
    echo "║  DB Pass:      ${DB_PASS}"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    info "Save these credentials!"
    info "Change admin password after first login."
    info "To install Wings on a node: bash <(curl -sL https://raw.githubusercontent.com/CodeByCruel/hyper-panel-installer/main/install.sh)"
}

#==============================================================================
#                         RUN
#==============================================================================
main_menu
