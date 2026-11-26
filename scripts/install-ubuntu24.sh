#!/bin/bash
# =============================================================================
# XUI One Decoded - Modern Installation Script for Ubuntu 22.04/24.04
# =============================================================================
# Incorporates best practices from XC_VM (Vateron-Media/XC_VM)
# - PHP 8.3 with JIT, KeyDB, FFmpeg 7+, yt-dlp, Deno
# - Modern Nginx config, security hardening, monitoring
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration (can be overridden via environment)
XUI_DOMAIN="${XUI_DOMAIN:-your-domain.com}"
XUI_TYPE="${XUI_TYPE:-main}"                    # main|lb|proxy
XUI_DB_PASSWORD="${XUI_DB_PASSWORD:-$(openssl rand -base64 32)}"
XUI_DB_ROOT_PASSWORD="${XUI_DB_ROOT_PASSWORD:-$(openssl rand -base64 32)}"
XUI_KEYDB_PASSWORD="${XUI_KEYDB_PASSWORD:-$(openssl rand -base64 32)}"
XUI_ADMIN_USER="${XUI_ADMIN_USER:-admin}"
XUI_ADMIN_PASS="${XUI_ADMIN_PASS:-$(openssl rand -base64 16)}"
XUI_TIMEZONE="${XUI_TIMEZONE:-America/Managua}"
XUI_INSTALL_PATH="${XUI_INSTALL_PATH:-/var/www/xui}"
XUI_GITHUB_REPO="${XUI_GITHUB_REPO:-https://github.com/TalaveraSama/xuione-decoded.git}"
XUI_BRANCH="${XUI_BRANCH:-main}"
PHP_VERSION="${PHP_VERSION:-8.3}"
ENABLE_YTDLP="${ENABLE_YTDLP:-true}"
ENABLE_DENO="${ENABLE_DENO:-true}"
ENABLE_MONITORING="${ENABLE_MONITORING:-true}"
ENABLE_SSL="${ENABLE_SSL:-true}"

LOG_FILE="/var/log/xui-install.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# =============================================================================
# Helper Functions
# =============================================================================

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    [[ $EUID -eq 0 ]] || { log_error "Run as root"; exit 1; }
}

check_ubuntu() {
    if ! grep -qE "Ubuntu (22.04|24.04)" /etc/os-release; then
        log_warning "Designed for Ubuntu 22.04/24.04. Current: $(lsb_release -d | cut -f2)"
        read -p "Continue? (y/N): " -n 1 -r; echo
        [[ $REPLY =~ ^[Yy]$ ]] || exit 1
    fi
}

prompt_config() {
    echo; log_info "=== Configuration ==="
    read -p "Domain [$XUI_DOMAIN]: " i; XUI_DOMAIN="${i:-$XUI_DOMAIN}"
    read -p "Node type (main/lb/proxy) [$XUI_TYPE]: " i; XUI_TYPE="${i:-$XUI_TYPE}"
    read -p "Timezone [$XUI_TIMEZONE]: " i; XUI_TIMEZONE="${i:-$XUI_TIMEZONE}"
    read -p "Install path [$XUI_INSTALL_PATH]: " i; XUI_INSTALL_PATH="${i:-$XUI_INSTALL_PATH}"
    echo; log_info "Summary: Domain=$XUI_DOMAIN, Type=$XUI_TYPE, Path=$XUI_INSTALL_PATH"
    read -p "Proceed? (y/N): " -n 1 -r; echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 1
}

# =============================================================================
# Installation Steps
# =============================================================================

step_prepare() {
    log_info "Step 1: Preparing system..."
    apt update && apt full-upgrade -y
    apt install -y curl wget gnupg2 software-properties-common \
        apt-transport-https ca-certificates lsb-release unzip git \
        python3 python3-pip build-essential pkg-config
    timedatectl set-timezone "$XUI_TIMEZONE"
    log_success "System prepared"
}

step_php() {
    log_info "Step 2: Installing PHP $PHP_VERSION with JIT..."
    add-apt-repository -y ppa:ondrej/php
    apt update
    apt install -y php${PHP_VERSION}-cli php${PHP_VERSION}-fpm php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-redis php${PHP_VERSION}-igbinary php${PHP_VERSION}-curl \
        php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml php${PHP_VERSION}-zip \
        php${PHP_VERSION}-gd php${PHP_VERSION}-bcmath php${PHP_VERSION}-intl \
        php${PHP_VERSION}-opcache php${PHP_VERSION}-readline php${PHP_VERSION}-sodium \
        php${PHP_VERSION}-imagick php${PHP_VERSION}-msgpack

    # PHP-FPM Pool
    cat > /etc/php/${PHP_VERSION}/fpm/pool.d/xui.conf <<EOF
[xui]
user = www-data
group = www-data
listen = /run/php/php${PHP_VERSION}-fpm-xui.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 100
pm.start_servers = 10
pm.min_spare_servers = 10
pm.max_spare_servers = 50
pm.max_requests = 1000
pm.status_path = /status
php_admin_value[memory_limit] = 1024M
php_admin_value[max_execution_time] = 600
php_admin_value[date.timezone] = $XUI_TIMEZONE
php_admin_value[opcache.enable] = 1
php_admin_value[opcache.enable_cli] = 1
php_admin_value[opcache.jit] = 1235
php_admin_value[opcache.jit_buffer_size] = 256M
php_admin_value[opcache.memory_consumption] = 512M
php_admin_value[opcache.max_accelerated_files] = 50000
php_admin_value[opcache.validate_timestamps] = 0
php_admin_value[expose_php] = Off
php_admin_flag[display_errors] = Off
php_admin_value[error_log] = /var/log/php${PHP_VERSION}-fpm-xui.log
EOF

    # Security hardening
    cat > /etc/php/${PHP_VERSION}/fpm/conf.d/99-security.ini <<'EOF'
disable_functions = exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source,pcntl_exec,pcntl_fork,pcntl_signal
expose_php = Off
display_errors = Off
log_errors = On
session.cookie_httponly = 1
session.cookie_secure = 1
session.use_strict_mode = 1
EOF

    systemctl enable --now php${PHP_VERSION}-fpm
    log_success "PHP ${PHP_VERSION} installed"
}

step_keydb() {
    log_info "Step 3: Installing KeyDB (multi-threaded Redis)..."
    apt install -y keydb
    cat > /etc/keydb/keydb.conf <<EOF
bind 127.0.0.1
port 6379
requirepass $XUI_KEYDB_PASSWORD
maxmemory 2gb
maxmemory-policy allkeys-lru
save 900 1
save 300 10
save 60 10000
dir /var/lib/keydb
appendonly yes
appendfsync everysec
activerehashing yes
databases 16
thread_count 4
EOF
    systemctl enable --now keydb
    keydb-cli -a "$XUI_KEYDB_PASSWORD" ping | grep -q PONG && log_success "KeyDB installed" || { log_error "KeyDB failed"; exit 1; }
}

step_mariadb() {
    log_info "Step 4: Installing MariaDB 10.11+..."
    curl -LsS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash -s -- --mariadb-server-version=10.11
    apt update && apt install -y mariadb-server mariadb-client
    systemctl enable --now mariadb

    # Secure install
    mysql -e "DELETE FROM mysql.user WHERE User='';"
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');"
    mysql -e "DROP DATABASE IF EXISTS test;"
    mysql -e "FLUSH PRIVILEGES;"
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$XUI_DB_ROOT_PASSWORD';"

    # Create XUI database
    mysql -u root -p"$XUI_DB_ROOT_PASSWORD" <<EOF
CREATE DATABASE IF NOT EXISTS xui CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'xui'@'localhost' IDENTIFIED BY '$XUI_DB_PASSWORD';
GRANT ALL PRIVILEGES ON xui.* TO 'xui'@'localhost';
FLUSH PRIVILEGES;
EOF

    # Optimizations
    cat > /etc/mysql/mariadb.conf.d/99-xui.cnf <<'EOF'
[mysqld]
innodb_buffer_pool_size = 2G
innodb_log_file_size = 256M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
max_connections = 500
innodb_file_per_table = 1
innodb_read_io_threads = 8
innodb_write_io_threads = 8
query_cache_type = 0
query_cache_size = 0
tmp_table_size = 64M
max_heap_table_size = 64M
EOF
    systemctl restart mariadb
    log_success "MariaDB installed"
}

step_ffmpeg() {
    log_info "Step 5: Installing FFmpeg 7+..."
    apt install -y ffmpeg
    ffmpeg -version | head -1 | grep -q ffmpeg && log_success "FFmpeg: $(ffmpeg -version | head -1)" || { log_error "FFmpeg failed"; exit 1; }
}

step_ytdlp_deno() {
    if [[ "$ENABLE_DENO" == "true" ]]; then
        log_info "Step 6a: Installing Deno..."
        curl -fsSL https://deno.land/install.sh | sh -s -- -y
        export PATH="$HOME/.deno/bin:$PATH"
        echo 'export PATH="$HOME/.deno/bin:$PATH"' >> /etc/profile.d/deno.sh
    fi
    if [[ "$ENABLE_YTDLP" == "true" ]]; then
        log_info "Step 6b: Installing yt-dlp..."
        curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
        chmod +x /usr/local/bin/yt-dlp
    fi
    log_success "yt-dlp + Deno installed"
}

step_nginx() {
    log_info "Step 7: Installing and configuring Nginx..."
    apt install -y nginx

    # Main nginx.conf
    cat > /etc/nginx/nginx.conf <<'EOF'
user www-data;
worker_processes auto;
worker_rlimit_nofile 65535;
pid /run/nginx.pid;
events { worker_connections 4096; multi_accept on; use epoll; }
http {
    sendfile on; tcp_nopush on; tcp_nodelay on; keepalive_timeout 65;
    types_hash_max_size 2048; server_tokens off;
    include /etc/nginx/mime.types; default_type application/octet-stream;
    access_log /var/log/nginx/access.log combined buffer=32k flush=5s;
    error_log /var/log/nginx/error.log warn;
    gzip on; gzip_vary on; gzip_proxied any; gzip_comp_level 6; gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/json application/xml application/rss+xml image/svg+xml font/woff font/woff2;
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=100r/s;
    limit_req_zone $binary_remote_addr zone=login_limit:10m rate=5r/s;
    limit_req_zone $binary_remote_addr zone=stream_limit:10m rate=50r/s;
    upstream php_xui { server unix:/run/php/php8.3-fpm-xui.sock; keepalive 64; }
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off; ssl_session_cache shared:SSL:10m; ssl_session_timeout 10m;
    include /etc/nginx/sites-enabled/*;
}
EOF

    # Site config based on type
    if [[ "$XUI_TYPE" == "lb" ]]; then
        cat > /etc/nginx/sites-available/xui <<'EOF'
server { listen 80; listen [::]:80; server_name _; root /var/www/xui/decoded/www; index init.php;
    add_header X-Frame-Options "SAMEORIGIN" always; add_header X-Content-Type-Options "nosniff" always;
    location ~ ^/(player_api|api|playlist|epg|enigma2|xplugin|live|vod|timeshift|series)\.php { fastcgi_pass php_xui; fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name; include fastcgi_params; fastcgi_read_timeout 300; limit_req zone=stream_limit burst=100 nodelay; }
    location ~* \.(m3u8|ts|mpd|m4s)$ { add_header Cache-Control "no-cache, no-store, must-revalidate"; add_header Access-Control-Allow-Origin "*"; access_log off; try_files $uri =404; }
    location /admin/ { deny all; return 404; } location /player/ { deny all; return 404; } location /reseller/ { deny all; return 404; }
    location ~ \.php$ { fastcgi_pass php_xui; fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name; include fastcgi_params; fastcgi_read_timeout 300; }
    location ~ /\.(git|env|htaccess) { deny all; return 404; } location ~ /(config|tmp|includes|cli)/ { deny all; return 404; }
}
EOF
    else
        cat > /etc/nginx/sites-available/xui <<'EOF'
server { listen 80; listen [::]:80; server_name _; root /var/www/xui/decoded/www; index init.php;
    add_header X-Frame-Options "SAMEORIGIN" always; add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always; add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    gzip on; gzip_vary on; gzip_min_length 1024; gzip_comp_level 6; gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml application/json;
    client_max_body_size 100M; limit_req zone=api_limit burst=200 nodelay; limit_req zone=login_limit burst=10 nodelay;
    location / { try_files $uri $uri/ /init.php?$query_string; }
    location /admin/ { alias /var/www/xui/decoded/admin/; try_files $uri $uri/ /admin/index.php?$query_string; location ~ \.php$ { fastcgi_pass php_xui; fastcgi_param SCRIPT_FILENAME $request_filename; include fastcgi_params; fastcgi_read_timeout 600; } }
    location /player/ { alias /var/www/xui/decoded/player/; try_files $uri $uri/ /player/index.php?$query_string; location ~ \.php$ { fastcgi_pass php_xui; fastcgi_param SCRIPT_FILENAME $request_filename; include fastcgi_params; fastcgi_read_timeout 600; } }
    location /reseller/ { alias /var/www/xui/decoded/reseller/; try_files $uri $uri/ /reseller/index.php?$query_string; location ~ \.php$ { fastcgi_pass php_xui; fastcgi_param SCRIPT_FILENAME $request_filename; include fastcgi_params; fastcgi_read_timeout 600; } }
    location ~ ^/(player_api|api|playlist|epg|enigma2|xplugin)\.php { fastcgi_pass php_xui; fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name; include fastcgi_params; fastcgi_read_timeout 300; limit_req zone=api_limit burst=50 nodelay; }
    location ~* \.(m3u8|ts|mpd|m4s)$ { add_header Cache-Control "no-cache, no-store, must-revalidate"; add_header Access-Control-Allow-Origin "*"; access_log off; try_files $uri =404; }
    location ~ \.php$ { fastcgi_pass php_xui; fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name; fastcgi_param PATH_INFO $fastcgi_path_info; include fastcgi_params; fastcgi_read_timeout 600; }
    location ~ /\.(git|env|htaccess) { deny all; return 404; } location ~ /(config|tmp|includes|cli)/ { deny all; return 404; }
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ { expires 1y; add_header Cache-Control "public, immutable"; access_log off; }
    access_log /var/log/nginx/xui_access.log; error_log /var/log/nginx/xui_error.log;
}
EOF

    ln -sf /etc/nginx/sites-available/xui /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    nginx -t && systemctl reload nginx
    systemctl enable --now nginx
    log_success "Nginx configured for $XUI_TYPE"
}

step_repo() {
    log_info "Step 8: Cloning XUI One Decoded..."
    mkdir -p "$XUI_INSTALL_PATH"
    cd "$XUI_INSTALL_PATH"
    if [[ -d .git ]]; then git pull origin "$XUI_BRANCH"; else git clone -b "$XUI_BRANCH" "$XUI_GITHUB_REPO" .; fi
    # Symlinks for admin/player/reseller
    cd "$XUI_INSTALL_PATH/decoded/www"
    ln -sf ../admin admin; ln -sf ../player player; ln -sf ../reseller reseller
    log_success "Repository cloned"
}

step_config() {
    log_info "Step 9: Configuring XUI..."
    mkdir -p "$XUI_INSTALL_PATH/config"
    SECURITY_KEY=$(openssl rand -hex 32)

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
password = $XUI_KEYDB_PASSWORD
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
ffmpeg_cpu = 7.0
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

[server]
type = $([[ "$XUI_TYPE" == "lb" ]] && echo 2 || echo 1)

[cluster]
enabled = 1
EOF

    # Update constants.php
    sed -i "s|define('XUI_HOME',.*|define('XUI_HOME', '$XUI_INSTALL_PATH/');|" "$XUI_INSTALL_PATH/decoded/www/constants.php"

    # Temp dirs
    mkdir -p "$XUI_INSTALL_PATH/tmp"/{cache,flood,logs,records,thumbnails}
    chown -R www-data:www-data "$XUI_INSTALL_PATH/tmp"
    chmod -R 777 "$XUI_INSTALL_PATH/tmp"

    # Secure config
    chmod 640 "$XUI_INSTALL_PATH/config/config.ini"
    chown www-data:www-data "$XUI_INSTALL_PATH/config/config.ini"
    log_success "XUI configured"
}

step_ssl() {
    if [[ "$ENABLE_SSL" == "true" && "$XUI_DOMAIN" != "your-domain.com" && "$XUI_DOMAIN" != "_" ]]; then
        log_info "Step 10: Setting up SSL with Let's Encrypt..."
        apt install -y certbot python3-certbot-nginx
        if certbot --nginx -d "$XUI_DOMAIN" --non-interactive --agree-tos --email "admin@$XUI_DOMAIN" --redirect --hsts --staple-ocsp; then
            systemctl enable --now certbot.timer
            log_success "SSL configured"
        else
            log_warning "SSL setup failed. Run manually: certbot --nginx -d $XUI_DOMAIN"
        fi
    else
        log_warning "Skipping SSL (ENABLE_SSL=$ENABLE_SSL or default domain)"
    fi
}

step_cron() {
    log_info "Step 11: Setting up cron jobs..."
    cat > /etc/cron.d/xui <<EOF
# XUI One Decoded Cron Jobs
* * * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/monitor.php > /dev/null 2>&1
* * * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/queue.php > /dev/null 2>&1
* * * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/delay.php > /dev/null 2>&1
* * * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/record.php start > /dev/null 2>&1
* * * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/record.php stop > /dev/null 2>&1
*/5 * * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/watchdog.php > /dev/null 2>&1
*/30 * * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/proxy.php test > /dev/null 2>&1
0 */6 * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/epg.php > /dev/null 2>&1
0 3 * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/cache_handler.php clean > /dev/null 2>&1
0 2 * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/backup.php > /dev/null 2>&1
0 4 * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/scanner.php > /dev/null 2>&1
0 1 * * * www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/record.php cleanup > /dev/null 2>&1
0 3 * * 0 www-data /usr/bin/php $XUI_INSTALL_PATH/decoded/includes/cli/archive.php logs 30 > /dev/null 2>&1
EOF
    log_success "Cron jobs configured"
}

step_firewall() {
    log_info "Step 12: Configuring firewall and fail2ban..."
    apt install -y ufw fail2ban
    ufw default deny incoming; ufw default allow outgoing
    ufw allow 22/tcp comment 'SSH'; ufw allow 80/tcp comment 'HTTP'; ufw allow 443/tcp comment 'HTTPS'
    ufw --force enable

    cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 3600; findtime = 600; maxretry = 5; backend = systemd
ignoreip = 127.0.0.1/8 10.0.0.0/8 192.168.0.0/16
[nginx-http-auth] enabled = true; port = http,https; logpath = /var/log/nginx/error.log
[nginx-limit-req] enabled = true; port = http,https; logpath = /var/log/nginx/*error.log; maxretry = 10
[nginx-badbots] enabled = true; port = http,https; logpath = /var/log/nginx/*access.log; maxretry = 2
[xui-login] enabled = true; port = http,https; logpath = /var/log/nginx/xui_access.log; maxretry = 5; filter = xui-login
EOF
    cat > /etc/fail2ban/filter.d/xui-login.conf <<'EOF'
[Definition]
failregex = ^.*"POST /admin/login.php HTTP.*" 200.*$ ^.*"POST /admin/ HTTP.*" 200.*$
ignoreregex =
EOF
    systemctl enable --now fail2ban
    log_success "Firewall + Fail2Ban configured"
}

step_monitoring() {
    if [[ "$ENABLE_MONITORING" == "true" ]]; then
        log_info "Step 13: Setting up monitoring..."
        # Health check
        cat > /usr/local/bin/xui-health.sh <<'EOF'
#!/bin/bash
DOMAIN="your-domain.com"; ALERT_EMAIL="admin@your-domain.com"
check() { systemctl is-active --quiet "$1" || return 1; }
check_port() { ss -ltn | grep -q ":$1 "; }
check_disk() { [[ $(df /var/www/xui | tail -1 | awk '{print $5}' | sed 's/%//') -lt 90 ]]; }
check_db() { mysql -u xui -pDB_PASSWORD -e "USE xui; SELECT 1;" >/dev/null 2>&1; }
check_redis() { keydb-cli -a REDIS_PASSWORD ping | grep -q PONG; }
check_web() { curl -sf -o /dev/null -w "%{http_code}" "https://$DOMAIN/" | grep -q "200\|301\|302"; }
FAILED=0
for svc in nginx php8.3-fpm mariadb keydb; do check "$svc" || { echo "$svc DOWN"; ((FAILED++)); }; done
for port in 80 443; do check_port "$port" || { echo "PORT $port DOWN"; ((FAILED++)); }; done
check_disk || { echo "DISK > 90%"; ((FAILED++)); }
check_db || { echo "DB FAILED"; ((FAILED++)); }
check_redis || { echo "REDIS FAILED"; ((FAILED++)); }
check_web || { echo "WEB DOWN"; ((FAILED++)); }
exit $FAILED
EOF
        chmod +x /usr/local/bin/xui-health.sh
        echo "*/5 * * * * root /usr/local/bin/xui-health.sh" > /etc/cron.d/xui-health

        # Node Exporter
        useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true
        wget -q https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz -O /tmp/node_exporter.tgz
        tar xzf /tmp/node_exporter.tgz -C /tmp && cp /tmp/node_exporter-*/node_exporter /usr/local/bin/
        cat > /etc/systemd/system/node_exporter.service <<'EOF'
[Unit] Description=Node Exporter; After=network.target
[Service] User=node_exporter; Group=node_exporter; Type=simple; ExecStart=/usr/local/bin/node_exporter --collector.systemd --collector.processes
[Install] WantedBy=multi-user.target
EOF
        systemctl enable --now node_exporter
        log_success "Monitoring configured"
    fi
}

step_finalize() {
    log_info "Step 14: Finalizing..."
    chown -R www-data:www-data "$XUI_INSTALL_PATH"
    find "$XUI_INSTALL_PATH" -type f -name "*.php" -exec chmod 644 {} \;
    find "$XUI_INSTALL_PATH" -type d -exec chmod 755 {} \;
    chmod -R 777 "$XUI_INSTALL_PATH/tmp"
    systemctl restart php8.3-fpm nginx

    # Save credentials
    cat > "$XUI_INSTALL_PATH/CREDENTIALS.txt" <<EOF
====================================================
XUI One Decoded - Installation Credentials
====================================================
Date: $(date)
Domain: https://$XUI_DOMAIN
Type: $XUI_TYPE
Path: $XUI_INSTALL_PATH

Admin Panel: https://$XUI_DOMAIN/admin/
Username: $XUI_ADMIN_USER
Password: $XUI_ADMIN_PASS

Database:
  Host: localhost | Database: xui | User: xui | Pass: $XUI_DB_PASSWORD
  Root Pass: $XUI_DB_ROOT_PASSWORD

KeyDB:
  Host: 127.0.0.1:6379 | Pass: $XUI_KEYDB_PASSWORD

Player API: https://$XUI_DOMAIN/player_api.php
M3U: https://$XUI_DOMAIN/playlist.php?username=USER&password=PASS
EPG: https://$XUI_DOMAIN/epg.php?username=USER&password=PASS

Logs: /var/log/nginx/xui_*.log | /var/log/php8.3-fpm-xui.log | $XUI_INSTALL_PATH/tmp/logs/

Documentation: https://github.com/TalaveraSama/IUX-ZONE
Repository: https://github.com/TalaveraSama/xuione-decoded
====================================================
EOF
    chmod 600 "$XUI_INSTALL_PATH/CREDENTIALS.txt"; chown root:root "$XUI_INSTALL_PATH/CREDENTIALS.txt"
    log_success "Installation complete!"
}

# =============================================================================
# Main
# =============================================================================

main() {
    clear
    echo "================================================================"
    echo "  XUI One Decoded - Modern Installer (Ubuntu 22.04/24.04)"
    echo "  Based on XC_VM best practices: PHP 8.3, KeyDB, FFmpeg 7, yt-dlp"
    echo "================================================================"
    check_root; check_ubuntu; prompt_config
    log_info "Starting installation..."
    step_prepare; step_php; step_keydb; step_mariadb; step_ffmpeg
    step_ytdlp_deno; step_nginx; step_repo; step_config; step_ssl
    step_cron; step_firewall; step_monitoring; step_finalize
    echo; echo "================================================================"
    log_success "INSTALLATION COMPLETE!"
    echo "================================================================"
    echo "Admin: https://$XUI_DOMAIN/admin/ | User: $XUI_ADMIN_USER | Pass: $XUI_ADMIN_PASS"
    echo "Credentials: $XUI_INSTALL_PATH/CREDENTIALS.txt | Log: $LOG_FILE"
    echo "Documentation: https://github.com/TalaveraSama/IUX-ZONE"
}

main "$@"