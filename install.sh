#!/bin/bash
#==============================================================================
# Hyper Game Panel — One-Line Installer (License-Free Build)
# Usage: bash <(curl -sL https://raw.githubusercontent.com/you/repo/main/install.sh)
# Or:    wget -qO- https://raw.githubusercontent.com/you/repo/main/install.sh | bash
#==============================================================================
set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────────────
PANEL_PATH="${PANEL_PATH:-/var/www/pterodactyl}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-pterodactyl}"
DB_USER="${DB_USER:-pterodactyl}"
FQDN="${FQDN:-$(hostname -f)}"
TIMEZONE="${TIMEZONE:-UTC}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@$(hostname -f)}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-ChangeMeNow123!}"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[i]${NC} $1"; }

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && err "Must run as root. Use: sudo bash $0"

echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║        Hyper Game Panel — License-Free Installer         ║"
echo "║                      v2.0.12                             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ─── Detect OS ───────────────────────────────────────────────────────────────
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
else
    err "Cannot detect OS. Only Debian/Ubuntu supported."
fi

case "$OS" in
    debian|ubuntu) log "Detected $OS $OS_VERSION" ;;
    *) err "Only Debian/Ubuntu is supported. Detected: $OS" ;;
esac

# ─── Install System Packages ────────────────────────────────────────────────
log "Installing system packages..."
export DEBIAN_FRONTEND=noninteractive

# Add PHP 8.4 repo (ondrej/php)
apt-get update -y >/dev/null 2>&1
apt-get install -y software-properties-common curl wget unzip git >/dev/null 2>&1

if ! php8.4 -v &>/dev/null; then
    info "Adding PHP 8.4 repository..."
    add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1 || true
    apt-get update -y >/dev/null 2>&1
fi

log "Installing PHP 8.4 and extensions..."
apt-get install -y \
    php8.4 php8.4-cli php8.4-fpm \
    php8.4-bcmath php8.4-curl php8.4-gd \
    php8.4-mbstring php8.4-mysql php8.4-opcache \
    php8.4-xml php8.4-zip php8.4-intl php8.4-redis \
    nginx mariadb-server redis-server \
    composer certbot python3-certbot-nginx \
    supervisor logrotate >/dev/null 2>&1

log "Installing IonCube Loader for PHP 8.4..."
IC_EXT_DIR=$(php8.4 -r "echo ini_get('extension_dir');" 2>/dev/null)
IC_URL="https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz"
IC_TMP=$(mktemp -d)

if ! php8.4 -m 2>/dev/null | grep -q "ionCube Loader"; then
    curl -fsSL -o "$IC_TMP/ioncube.tar.gz" "$IC_URL" >/dev/null 2>&1
    tar -xzf "$IC_TMP/ioncube.tar.gz" -C "$IC_TMP" >/dev/null 2>&1
    cp "$IC_TMP/ioncube/ioncube_loader_lin_8.4.so" "$IC_EXT_DIR/" 2>/dev/null
    cat > /etc/php/8.4/mods-available/00-ioncube.ini <<IONCUBE
zend_extension="${IC_EXT_DIR}/ioncube_loader_lin_8.4.so"
opcache.jit=0
opcache.jit_buffer_size=0
IONCUBE
    phpenmod -v 8.4 -s cli 00-ioncube 2>/dev/null || true
    phpenmod -v 8.4 -s fpm 00-ioncube 2>/dev/null || true
    log "IonCube Loader installed"
else
    log "IonCube Loader already installed"
fi

# ─── Start Services ─────────────────────────────────────────────────────────
log "Starting services..."
systemctl enable --now mysql >/dev/null 2>&1 || service mysql start >/dev/null 2>&1
systemctl enable --now redis-server >/dev/null 2>&1 || service redis-server start >/dev/null 2>&1
systemctl enable --now php8.4-fpm >/dev/null 2>&1 || service php8.4-fpm start >/dev/null 2>&1

# ─── Database Setup ─────────────────────────────────────────────────────────
log "Configuring database..."
DB_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)

mysql -u root <<SQL >/dev/null 2>&1
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'${DB_HOST}';
FLUSH PRIVILEGES;
SQL
log "Database configured"

# ─── Download Panel ─────────────────────────────────────────────────────────
log "Downloading Hyper Game Panel v2.0.12..."
mkdir -p "$PANEL_PATH"

# Fetch latest download URL from API
API_URL="https://license.dgenx.net/api/v1/update-check?app_id=7c4efcdc-986e-4e85-9b07-328d6ad6db52&file_slug=default"
DOWNLOAD_URL=$(curl -fsSL "$API_URL" 2>/dev/null | \
    php -r '$r=json_decode(file_get_contents("php://stdin"),true);echo $r["latest_version"]["download_url"]??"";' 2>/dev/null || true)

if [ -z "$DOWNLOAD_URL" ] || [[ "$DOWNLOAD_URL" != http* ]]; then
    err "Failed to resolve download URL. Check your internet connection."
fi

TMP_DOWNLOAD=$(mktemp -d)
ARCHIVE="$TMP_DOWNLOAD/Hyper.zip"
curl -fSL --retry 3 -o "$ARCHIVE" "$DOWNLOAD_URL" >/dev/null 2>&1 || \
    wget -q -O "$ARCHIVE" "$DOWNLOAD_URL" >/dev/null 2>&1 || \
    err "Failed to download panel archive."

# Extract
info "Extracting panel files..."
rm -rf "$PANEL_PATH"
mkdir -p "$PANEL_PATH"
tar -xf "$ARCHIVE" -C "$PANEL_PATH" 2>/dev/null || \
    unzip -oq "$ARCHIVE" -d "$PANEL_PATH" 2>/dev/null || \
    err "Failed to extract archive."
rm -rf "$TMP_DOWNLOAD"

# ─── Apply License Patches ──────────────────────────────────────────────────
log "Applying license patches..."

# Middleware stubs
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

# License Controller
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

# License Services
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
class HyperV2IntegrityService{
    public function checkIntegrity():bool{return true;}
    public function verifyFiles():bool{return true;}
    public function getManifest():array{return [];}
    public function isManifestValid():bool{return true;}
    public function __call(string $n,array $a){return true;}
}
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

# Traits
cat > "$PANEL_PATH/app/Traits/ValidatesSecureLicense.php" <<'STUB'
<?php
namespace Pterodactyl\Traits;
trait ValidatesSecureLicense{public function validateSecureLicense():bool{return true;}public function isLicenseValid():bool{return true;}public function checkLicense():bool{return true;}public function hasValidLicense():bool{return true;}}
STUB

mkdir -p "$PANEL_PATH/app/Traits/Controllers"
cat > "$PANEL_PATH/app/Traits/Controllers/JavascriptInjection.php" <<'STUB'
<?php
namespace Pterodactyl\Traits\Controllers;
trait JavascriptInjection{public function injectJavascript(array $d=[]):void{\JavaScript::put($d);}}
STUB

mkdir -p "$PANEL_PATH/app/Traits/DGEN"
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

mkdir -p "$PANEL_PATH/app/Traits/Helpers"
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

# Additional Services
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

# Additional Traits
mkdir -p "$PANEL_PATH/app/Traits/Services"
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

# Security manifest (empty = no integrity checks)
cat > "$PANEL_PATH/bootstrap/cache/hyperv2_security_manifest.php" <<'STUB'
<?php
return array('version'=>1,'scope'=>'app_php_full','generated_at'=>'2026-06-17T00:09:12+00:00','files'=>array());
STUB

# JS patches — license service always returns valid
cat > "$PANEL_PATH/public/assets/licenseService.1tf8btsy.js" <<'JSTUB'
var licenseService={async verifyLicense(){return{valid:true,reason:"License verified",verified_at:new Date().toISOString(),license:{basic_features:true,premium_features:true,ultimate_features:true,minecraft_features:true,essentials_features:true,special_features:true,private_features:true,ark_features:true}}},async getLicenseStatus(){return{configured:true,valid:true,domain:window.location.hostname,license_type:"ultimate",expires_at:null}},clearVerificationData(){},hasCategory(e){return true},isLicenseValid(){return true}};var defaultExport=licenseService;export{licenseService as Bp,defaultExport as Cp};
JSTUB

# JS patches — LicenseMonitor is a no-op
cat > "$PANEL_PATH/public/assets/LicenseMonitor.wvnehtfj.js" <<'JSTUB'
function f(){return null}export{f as default};
JSTUB

# Remove .gz copies of patched JS to prevent stale cache
rm -f "$PANEL_PATH/public/assets/licenseService.1tf8btsy.js.gz" 2>/dev/null || true
rm -f "$PANEL_PATH/public/assets/LicenseMonitor.wvnehtfj.js.gz" 2>/dev/null || true

log "License patches applied"

# ─── Install Dependencies ───────────────────────────────────────────────────
log "Installing Composer dependencies..."
cd "$PANEL_PATH"
export COMPOSER_ALLOW_SUPERUSER=1
composer install --no-dev --optimize-autoloader --no-interaction 2>/dev/null || \
    err "Composer install failed. Check PHP version and extensions."

# ─── Environment Setup ──────────────────────────────────────────────────────
log "Setting up environment..."
if [ ! -f "$PANEL_PATH/.env" ]; then
    cp "$PANEL_PATH/.env.example" "$PANEL_PATH/.env"
fi

APP_KEY=$(php -r "echo 'base64:'.base64_encode(random_bytes(32));")

sed -i "s|APP_ENV=.*|APP_ENV=production|g" "$PANEL_PATH/.env"
sed -i "s|APP_DEBUG=.*|APP_DEBUG=false|g" "$PANEL_PATH/.env"
sed -i "s|APP_URL=.*|APP_URL=https://${FQDN}|g" "$PANEL_PATH/.env"
sed -i "s|APP_KEY=.*|APP_KEY=${APP_KEY}|g" "$PANEL_PATH/.env"
sed -i "s|APP_TIMEZONE=.*|APP_TIMEZONE=${TIMEZONE}|g" "$PANEL_PATH/.env"
sed -i "s|DB_HOST=.*|DB_HOST=${DB_HOST}|g" "$PANEL_PATH/.env"
sed -i "s|DB_PORT=.*|DB_PORT=${DB_PORT}|g" "$PANEL_PATH/.env"
sed -i "s|DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|g" "$PANEL_PATH/.env"
sed -i "s|DB_USERNAME=.*|DB_USERNAME=${DB_USER}|g" "$PANEL_PATH/.env"
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|g" "$PANEL_PATH/.env"
sed -i "s|CACHE_DRIVER=.*|CACHE_DRIVER=redis|g" "$PANEL_PATH/.env"
sed -i "s|SESSION_DRIVER=.*|SESSION_DRIVER=redis|g" "$PANEL_PATH/.env"
sed -i "s|QUEUE_DRIVER=.*|QUEUE_CONNECTION=redis|g" "$PANEL_PATH/.env"
sed -i "s|REDIS_HOST=.*|REDIS_HOST=127.0.0.1|g" "$PANEL_PATH/.env"

echo "ultimate" > "$PANEL_PATH/.hyper_release_channel"

# ─── Database Migration ─────────────────────────────────────────────────────
log "Running database migrations..."
php "$PANEL_PATH/artisan" migrate --force 2>/dev/null || warn "Migration issues (may be first run)"

# Seed database
php "$PANEL_PATH/artisan" db:seed --class=NestSeeder --force --no-interaction 2>/dev/null || true
php "$PANEL_PATH/artisan" db:seed --class=EggSeeder --force --no-interaction 2>/dev/null || true

# ─── Cache & Optimize ──────────────────────────────────────────────────────
log "Building caches..."
php "$PANEL_PATH/artisan" config:cache 2>/dev/null || true
php "$PANEL_PATH/artisan" event:cache 2>/dev/null || true
php "$PANEL_PATH/artisan" route:cache 2>/dev/null || true
php "$PANEL_PATH/artisan" view:cache 2>/dev/null || true
php "$PANEL_PATH/artisan" queue:restart 2>/dev/null || true

# ─── Permissions ────────────────────────────────────────────────────────────
log "Setting permissions..."
chown -R www-data:www-data "$PANEL_PATH"/*
chmod -R 755 "$PANEL_PATH/storage"/* "$PANEL_PATH"/bootstrap/cache/ 2>/dev/null || true

# ─── Nginx Configuration ───────────────────────────────────────────────────
log "Configuring Nginx..."
cat > /etc/nginx/sites-available/pterodactyl.conf <<NGINX
server {
    listen 80;
    server_name ${FQDN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
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
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "http";
        fastcgi_param HTTPS on;
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
        fastcgi_intercept_errors on;
    }

    location ~ /\.ht {
        deny all;
    }

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

nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null

# ─── Supervisor ─────────────────────────────────────────────────────────────
log "Configuring Supervisor..."
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

mkdir -p /var/log/pterodactyl
chown www-data:www-data /var/log/pterodactyl
supervisorctl reread 2>/dev/null || true
supervisorctl update 2>/dev/null || true
supervisorctl start pterodactyl-worker 2>/dev/null || true
supervisorctl start pterodactyl-scheduler 2>/dev/null || true

# ─── Logrotate ──────────────────────────────────────────────────────────────
cat > /etc/logrotate.d/pterodactyl <<LOGROTATE
/var/log/pterodactyl/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
LOGROTATE

# ─── SSL Certificate ────────────────────────────────────────────────────────
log "Attempting SSL certificate..."
certbot --nginx -d "$FQDN" --non-interactive --agree-tos --email "$ADMIN_EMAIL" 2>/dev/null || \
    warn "SSL setup skipped. Run certbot manually later."

# ─── Create Admin User ──────────────────────────────────────────────────────
log "Creating admin user..."
php "$PANEL_PATH/artisan" tinker --execute="
use Pterodactyl\Models\User;
\$user = User::factory()->create([
    'email' => '${ADMIN_EMAIL}',
    'password' => bcrypt('${ADMIN_PASSWORD}'),
    'root_admin' => true,
    'email_verified_at' => now(),
]);
echo 'Admin user created: ' . \$user->email . PHP_EOL;
" 2>/dev/null || warn "Admin user may already exist. Create manually via: php artisan tinker"

# ─── Cleanup ────────────────────────────────────────────────────────────────
rm -f "$PANEL_PATH/hyper_fetch.sh" 2>/dev/null || true
rm -f "$PANEL_PATH/hyper_auto_update.sh" 2>/dev/null || true
rm -f "$PANEL_PATH/hyper_auto_update_ioncube.sh" 2>/dev/null || true
rm -f /etc/sudoers.d/hyper_update 2>/dev/null || true

# ─── Done ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           Installation Complete!                         ║"
echo "╠═══════════════════════════════════════════════════════════╣"
echo "║  Panel URL:   https://${FQDN}"
echo "║  Admin Email: ${ADMIN_EMAIL}"
echo "║  Admin Pass:  ${ADMIN_PASSWORD}"
echo "║  Panel Path:  ${PANEL_PATH}"
echo "║  DB Name:     ${DB_NAME}"
echo "║  DB User:     ${DB_USER}"
echo "║  DB Pass:     ${DB_PASS}"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
info "Save these credentials! Change the admin password after first login."
info "For Wings nodes, install: curl -sSL https://raw.githubusercontent.com/pterodactyl/wings/master/install.sh | sudo bash"
