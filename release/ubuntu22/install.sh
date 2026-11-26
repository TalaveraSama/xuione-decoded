#!/bin/bash
# =============================================================================
# XUI One Decoded - Automated Installation Script for Ubuntu 22.04
# =============================================================================
# This script installs XUI One Decoded (IPTV Panel) on a fresh Ubuntu 22.04 server
# Repository: https://github.com/TalaveraSama/xuione-decoded
# Documentation: https://github.com/TalaveraSama/IUX-ZONE
# License: Apache 2.0 (original by tealcavalon/xuione_decoded)
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables (can be overridden via environment)
XUI_DOMAIN="${XUI_DOMAIN:-your-domain.com}"
XUI_DB_PASSWORD="${XUI_DB_PASSWORD:-$(openssl rand -base64 32)}"
XUI_REDIS_PASSWORD="${XUI_REDIS_PASSWORD:-$(openssl rand -base64 32)}"
XUI_ADMIN_USER="${XUI_ADMIN_USER:-admin}"
XUI_ADMIN_PASS="${XUI_ADMIN_PASS:-$(openssl rand -base64 16)}"
XUI_TIMEZONE="${XUI_TIMEZONE:-America/New_York}"
XUI_INSTALL_PATH="${XUI_INSTALL_PATH:-/var/www/xui}"
XUI_GITHUB_REPO="${XUI_GITHUB_REPO:-https://github.com/TalaveraSama/xuione-decoded.git}"
XUI_BRANCH="${XUI_BRANCH:-main}"

# Logging
LOG_FILE="/var/log/xui-install.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_ubuntu() {
    if ! grep -q "Ubuntu 22.04" /etc/os-release; then
        log_warning "This script is designed for Ubuntu 22.04. Current OS: $(lsb_release -d | cut -f2)"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

prompt_config() {
    echo
    log_info "=== Configuration ==="
    echo "Press Enter to use defaults (shown in brackets)"
    echo
    
    read -p "Domain name [$XUI_DOMAIN]: " input
    XUI_DOMAIN="${input:-$XUI_DOMAIN}"
    
    read -p "Database password [auto-generated]: " input
    XUI_DB_PASSWORD="${input:-$XUI_DB_PASSWORD}"
    
    read -p "Redis password [auto-generated]: " input
    XUI_REDIS_PASSWORD="${input:-$XUI_REDIS_PASSWORD}"
    
    read -p "Admin username [$XUI_ADMIN_USER]: " input
    XUI_ADMIN_USER="${input:-$XUI_ADMIN_USER}"
    
    read -p "Admin password [auto-generated]: " input
    XUI_ADMIN_PASS="${input:-$XUI_ADMIN_PASS}"
    
    read -p "Timezone [$XUI_TIMEZONE]: " input
    XUI_TIMEZONE="${input:-$XUI_TIMEZONE}"
    
    read -p "Install path [$XUI_INSTALL_PATH]: " input
    XUI_INSTALL_PATH="${input:-$XUI_INSTALL_PATH}"
    
    echo
    log_info "=== Summary ==="
    echo "Domain: $XUI_DOMAIN"
    echo "Install Path: $XUI_INSTALL_PATH"
    echo "Timezone: $XUI_TIMEZONE"
    echo "Admin User: $XUI_ADMIN_USER"
    echo "Database Password: ${XUI_DB_PASSWORD:0:8}..."
    echo "Redis Password: ${XUI_REDIS_PASSWORD:0:8}..."
    echo
    read -p "Proceed with installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
}

# =============================================================================
# Installation Steps
# =============================================================================

step_update_system() {
    log_info "Step 1/12: Updating system packages..."
    apt-get update -y
    apt-get upgrade -y
    apt-get install -y curl wget gnupg2 software-properties-common \
        apt-transport-https ca-certificates lsb-release unzip git
    log_success "System updated"
}

step_install_nginx() {
    log_info "Step 2/12: Installing Nginx..."
    apt-get install -y nginx
    systemctl enable --now nginx
    log_success "Nginx installed and started"
}

step_install_mariadb() {
    log_info "Step 3/12: Installing MariaDB..."
    apt-get install -y mariadb-server mariadb-client
    systemctl enable --now mariadb
    
    # Secure installation (automated)
    mysql -e "DELETE FROM mysql.user WHERE User='';"
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -e "DROP DATABASE IF EXISTS test;"
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    mysql -e "FLUSH PRIVILEGES;"
    
    log_success "MariaDB installed and secured"
}

step_install_redis() {
    log_info "Step 4/12: Installing Redis..."
    apt-get install -y redis-server
    
    # Configure Redis
    sed -i "s/^# requirepass .*/requirepass $XUI_REDIS_PASSWORD/" /etc/redis/redis.conf
    sed -i 's/^bind 127.0.0.1 ::1/bind 127.0.0.1/' /etc/redis/redis.conf
    systemctl enable --now redis-server
    
    # Test Redis
    if redis-cli -a "$XUI_REDIS_PASSWORD" ping | grep -q PONG; then
        log_success "Redis installed and configured"
    else
        log_error "Redis configuration failed"
        exit 1
    fi
}

step_install_php() {
    log_info "Step 5/12: Installing PHP 8.1 and extensions..."
    
    # Add Ondrej PPA for latest PHP
    add-apt-repository -y ppa:ondrej/php
    apt-get update -y
    
    apt-get install -y php8.1-cli php8.1-fpm php8.1-mysql php8.1-redis \
        php8.1-igbinary php8.1-curl php8.1-mbstring php8.1-xml php8.1-zip \
        php8.1-gd php8.1-bcmath php8.1-intl php8.1-opcache php8.1-readline
    
    # Configure PHP-FPM
    cat > /etc/php/8.1/fpm/pool.d/xui.conf <<EOF
[xui]
user = www-data
group = www-data
listen = /run/php/php8.1-fpm-xui.sock
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
pm.max_requests = 500
php_admin_value[memory_limit] = 512M
php_admin_value[max_execution_time] = 300
php_admin_value[max_input_time] = 300
php_admin_value[post_max_size] = 100M
php_admin_value[upload_max_filesize] = 100M
php_admin_value[date.timezone] = $XUI_TIMEZONE
php_admin_value[opcache.enable] = 1
php_admin_value[opcache.memory_consumption] = 256
php_admin_value[opcache.max_accelerated_files] = 20000
php_admin_value[expose_php] = Off
php_admin_flag[display_errors] = Off
php_admin_value[error_log] = /var/log/php8.1-fpm-xui.log
EOF
    
    # Configure PHP.ini
    sed -i "s/^;date.timezone =.*/date.timezone = $XUI_TIMEZONE/" /etc/php/8.1/fpm/php.ini
    sed -i "s/^memory_limit =.*/memory_limit = 512M/" /etc/php/8.1/fpm/php.ini
    sed -i "s/^max_execution_time =.*/max_execution_time = 300/" /etc/php/8.1/fpm/php.ini
    sed -i "s/^post_max_size =.*/post_max_size = 100M/" /etc/php/8.1/fpm/php.ini
    sed -i "s/^upload_max_filesize =.*/upload_max_filesize = 100M/" /etc/php/8.1/fpm/php.ini
    sed -i "s/^opcache.enable=.*/opcache.enable=1/" /etc/php/8.1/fpm/php.ini
    sed -i "s/^;opcache.memory_consumption=.*/opcache.memory_consumption=256/" /etc/php/8.1/fpm/php.ini
    sed -i "s/^;opcache.max_accelerated_files=.*/opcache.max_accelerated_files=20000/" /etc/php/8.1/fpm/php.ini
    sed -i "s/^expose_php =.*/expose_php = Off/" /etc/php/8.1/fpm/php.ini
    
    systemctl enable --now php8.1-fpm
    log_success "PHP 8.1 installed and configured"
}

step_install_ffmpeg() {
    log_info "Step 6/12: Installing FFmpeg..."
    apt-get install -y ffmpeg
    
    # Verify installation
    if ffmpeg -version | head -1 | grep -q ffmpeg; then
        log_success "FFmpeg installed: $(ffmpeg -version | head -1)"
    else
        log_error "FFmpeg installation failed"
        exit 1
    fi
}

step_create_database() {
    log_info "Step 7/12: Creating database and user..."
    
    mysql -e "CREATE DATABASE IF NOT EXISTS xui CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -e "CREATE USER IF NOT EXISTS 'xui'@'localhost' IDENTIFIED BY '$XUI_DB_PASSWORD';"
    mysql -e "GRANT ALL PRIVILEGES ON xui.* TO 'xui'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    
    # Test connection
    if mysql -u xui -p"$XUI_DB_PASSWORD" -e "USE xui; SELECT 1;" >/dev/null 2>&1; then
        log_success "Database created and user configured"
    else
        log_error "Database setup failed"
        exit 1
    fi
}

step_clone_repository() {
    log_info "Step 8/12: Cloning XUI One Decoded repository..."
    
    mkdir -p "$XUI_INSTALL_PATH"
    cd "$XUI_INSTALL_PATH"
    
    if [[ -d .git ]]; then
        log_info "Repository exists, pulling latest changes..."
        git pull origin "$XUI_BRANCH"
    else
        git clone -b "$XUI_BRANCH" "$XUI_GITHUB_REPO" .
    fi
    
    log_success "Repository cloned to $XUI_INSTALL_PATH"
}

step_configure_xui() {
    log_info "Step 9/12: Configuring XUI One..."
    
    # Create config directory
    mkdir -p "$XUI_INSTALL_PATH/config"
    
    # Generate security key
    SECURITY_KEY=$(openssl rand -hex 32)
    
    # Create config.ini
    cat > "$XUI_INSTALL_PATH/config/config.ini" <<EOF
[database]
host = localhost
port = 3306
username = xui
password = $XUI_DB_PASSWORD
dbname = xui

[redis]
host = 127.0.0.1
port = 6379
password = $XUI_REDIS_PASSWORD
db = 0

[panel]
url = https://$XUI_DOMAIN
timezone = $XUI_TIMEZONE
language = en
theme = default

[security]
flood_limit = 50
flood_seconds = 60
flood_ips_exclude = 127.0.0.1,::1
bruteforce_mac_attempts = 10
bruteforce_username_attempts = 10
bruteforce_frequency = 300
security_key = $SECURITY_KEY

[streaming]
ffmpeg_cpu = 4.4
ffmpeg_gpu = 4.0
segment_type = hls
seg_time = 10
seg_list_size = 5
seg_delete_threshold = 3
hls_encryption = 0
token_expiry = 3600

[paths]
home = $XUI_INSTALL_PATH/
tmp = $XUI_INSTALL_PATH/tmp/
logs = $XUI_INSTALL_PATH/tmp/logs/
cache = $XUI_INSTALL_PATH/tmp/cache/
flood = $XUI_INSTALL_PATH/tmp/flood/
records = $XUI_INSTALL_PATH/tmp/records/
thumbnails = $XUI_INSTALL_PATH/tmp/thumbnails/

[epg]
update_interval = 21600
source_timeout = 30
max_epg_days = 7

[recording]
max_concurrent = 5
default_duration = 7200
keep_days = 30
format = ts

[transcoding]
enabled = 1
preset = fast
crf = 23
audio_bitrate = 128k
video_codec = libx264
audio_codec = aac
hwaccel = auto
EOF
    
    # Update constants.php with correct paths
    sed -i "s|define('XUI_HOME',.*|define('XUI_HOME', '$XUI_INSTALL_PATH/');|" \
        "$XUI_INSTALL_PATH/decoded/www/constants.php"
    
    # Create tmp directories
    mkdir -p "$XUI_INSTALL_PATH/tmp"/{cache,flood,logs,records,thumbnails}
    chown -R www-data:www-data "$XUI_INSTALL_PATH/tmp"
    chmod -R 777 "$XUI_INSTALL_PATH/tmp"
    
    # Secure config.ini
    chmod 640 "$XUI_INSTALL_PATH/config/config.ini"
    chown www-data:www-data "$XUI_INSTALL_PATH/config/config.ini"
    
    log_success "XUI configuration created"
}

step_configure_nginx() {
    log_info "Step 10/12: Configuring Nginx..."
    
    # Create Nginx site configuration
    cat > /etc/nginx/sites-available/xui <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $XUI_DOMAIN;
    root $XUI_INSTALL_PATH/decoded/www;
    index index.php;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml application/json application/rss+xml image/svg+xml;

    # Client max body size
    client_max_body_size 100M;

    # Main location
    location / {
        try_files \$uri \$uri/ /init.php?\$query_string;
    }

    # PHP handling
    location ~ \.php$ {
        fastcgi_pass unix:/run/php/php8.1-fpm-xui.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        include fastcgi_params;
        fastcgi_read_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
    }

    # Deny access to sensitive files
    location ~ /\.(git|env|htaccess|gitignore) {
        deny all;
        return 404;
    }

    location ~ /(config|tmp|includes|cli)/ {
        deny all;
        return 404;
    }

    # Static files caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # HLS segment files (no cache for live)
    location ~* \.(m3u8|ts)$ {
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header Access-Control-Allow-Origin "*";
        access_log off;
    }

    # Logging
    access_log /var/log/nginx/xui_access.log;
    error_log /var/log/nginx/xui_error.log;
}
EOF
    
    # Enable site
    ln -sf /etc/nginx/sites-available/xui /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Test configuration
    nginx -t
    
    # Reload Nginx
    systemctl reload nginx
    
    log_success "Nginx configured"
}

step_configure_ssl() {
    log_info "Step 11/12: Setting up SSL with Let's Encrypt..."
    
    # Install Certbot
    apt-get install -y certbot python3-certbot-nginx
    
    # Get certificate
    if certbot --nginx -d "$XUI_DOMAIN" --non-interactive --agree-tos --email "admin@$XUI_DOMAIN" --redirect; then
        log_success "SSL certificate obtained and configured"
        
        # Setup auto-renewal
        systemctl enable --now certbot.timer
    else
        log_warning "SSL setup failed. You can run manually later: certbot --nginx -d $XUI_DOMAIN"
    fi
}

step_setup_cron() {
    log_info "Step 12/12: Setting up cron jobs..."
    
    # Create cron file for www-data
    cat > /etc/cron.d/xui <<EOF
# XUI One Decoded Cron Jobs
# Run as www-data user

# System monitoring (every minute)
* * * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/monitor.php > /dev/null 2>&1

# Task queue (every minute)
* * * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/queue.php > /dev/null 2>&1

# Delayed tasks (every minute)
* * * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/delay.php > /dev/null 2>&1

# Recording management (every minute)
* * * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/record.php start > /dev/null 2>&1
* * * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/record.php stop > /dev/null 2>&1

# Watchdog (every 5 minutes)
*/5 * * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/watchdog.php > /dev/null 2>&1

# Proxy testing (every 30 minutes)
*/30 * * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/proxy.php test > /dev/null 2>&1

# EPG updates (every 6 hours)
0 */6 * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/epg.php > /dev/null 2>&1

# Cache cleanup (daily at 3 AM)
0 3 * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/cache_handler.php clean > /dev/null 2>&1

# Backup (daily at 2 AM)
0 2 * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/backup.php > /dev/null 2>&1

# Channel scanning (daily at 4 AM)
0 4 * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/scanner.php > /dev/null 2>&1

# Certificate renewal check (daily at 6 AM)
0 6 * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/certbot.php renew > /dev/null 2>&1

# Weekly update check (Sunday 5 AM)
0 5 * * 0 www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/update.php --check > /dev/null 2>&1

# Recording cleanup (daily at 1 AM)
0 1 * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/record.php cleanup > /dev/null 2>&1

# Log archiving (weekly Sunday 3 AM)
0 3 * * 0 www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/archive.php logs 30 > /dev/null 2>&1
EOF
    
    log_success "Cron jobs configured"
}

step_finalize() {
    log_info "Finalizing installation..."
    
    # Set correct permissions
    chown -R www-data:www-data "$XUI_INSTALL_PATH"
    find "$XUI_INSTALL_PATH" -type f -name "*.php" -exec chmod 644 {} \;
    find "$XUI_INSTALL_PATH" -type d -exec chmod 755 {} \;
    chmod -R 777 "$XUI_INSTALL_PATH/tmp"
    
    # Restart services
    systemctl restart php8.1-fpm
    systemctl reload nginx
    
    # Save credentials
    cat > "$XUI_INSTALL_PATH/CREDENTIALS.txt" <<EOF
====================================================
XUI One Decoded - Installation Credentials
====================================================
Installation Date: $(date)
Domain: https://$XUI_DOMAIN
Install Path: $XUI_INSTALL_PATH

Admin Panel: https://$XUI_DOMAIN/admin/
Username: $XUI_ADMIN_USER
Password: $XUI_ADMIN_PASS

Database:
  Host: localhost
  Database: xui
  Username: xui
  Password: $XUI_DB_PASSWORD

Redis:
  Host: 127.0.0.1
  Port: 6379
  Password: $XUI_REDIS_PASSWORD

Player API: https://$XUI_DOMAIN/player_api.php
M3U Playlist: https://$XUI_DOMAIN/playlist.php?username=USER&password=PASS
EPG XMLTV: https://$XUI_DOMAIN/epg.php?username=USER&password=PASS

Logs:
  Nginx: /var/log/nginx/xui_*.log
  PHP-FPM: /var/log/php8.1-fpm-xui.log
  XUI: $XUI_INSTALL_PATH/tmp/logs/

Documentation: https://github.com/TalaveraSama/IUX-ZONE
Repository: https://github.com/TalaveraSama/xuione-decoded
====================================================
EOF
    
    chmod 600 "$XUI_INSTALL_PATH/CREDENTIALS.txt"
    chown root:root "$XUI_INSTALL_PATH/CREDENTIALS.txt"
    
    log_success "Installation completed!"
}

# =============================================================================
# Main
# =============================================================================

main() {
    clear
    echo "================================================================"
    echo "  XUI One Decoded - Automated Installation for Ubuntu 22.04"
    echo "================================================================"
    echo
    echo "Repository: https://github.com/TalaveraSama/xuione-decoded"
    echo "Documentation: https://github.com/TalaveraSama/IUX-ZONE"
    echo "License: Apache 2.0"
    echo
    
    check_root
    check_ubuntu
    prompt_config
    
    log_info "Starting installation..."
    echo
    
    step_update_system
    step_install_nginx
    step_install_mariadb
    step_install_redis
    step_install_php
    step_install_ffmpeg
    step_create_database
    step_clone_repository
    step_configure_xui
    step_configure_nginx
    step_configure_ssl
    step_setup_cron
    step_finalize
    
    echo
    echo "================================================================"
    log_success "INSTALLATION COMPLETE!"
    echo "================================================================"
    echo
    echo "Admin Panel: https://$XUI_DOMAIN/admin/"
    echo "  Username: $XUI_ADMIN_USER"
    echo "  Password: $XUI_ADMIN_PASS"
    echo
    echo "Credentials saved to: $XUI_INSTALL_PATH/CREDENTIALS.txt"
    echo "Installation log: $LOG_FILE"
    echo
    echo "Next steps:"
    echo "1. Open https://$XUI_DOMAIN/admin/ in your browser"
    echo "2. Login with the credentials above"
    echo "3. Complete the setup wizard (license, server config)"
    echo "4. Add your streams, bouquets, and users"
    echo
    echo "Documentation: https://github.com/TalaveraSama/IUX-ZONE"
    echo
}

# Run main
main "$@"