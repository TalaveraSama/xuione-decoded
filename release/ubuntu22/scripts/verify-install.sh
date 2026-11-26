#!/bin/bash
# =============================================================================
# XUI One Decoded - Installation Verification Script
# =============================================================================
# Run this after installation to verify everything is working correctly
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

XUI_INSTALL_PATH="${XUI_INSTALL_PATH:-/var/www/xui}"
XUI_DOMAIN="${XUI_DOMAIN:-your-domain.com}"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }

check_command() {
    if command -v "$1" >/dev/null 2>&1; then
        log_success "$1: $(command -v $1)"
        return 0
    else
        log_error "$1: NOT FOUND"
        return 1
    fi
}

check_service() {
    if systemctl is-active --quiet "$1"; then
        log_success "Service $1: RUNNING"
        return 0
    else
        log_error "Service $1: NOT RUNNING"
        return 1
    fi
}

check_port() {
    if ss -ltn | grep -q ":$1 "; then
        log_success "Port $1: LISTENING"
        return 0
    else
        log_error "Port $1: NOT LISTENING"
        return 1
    fi
}

check_file() {
    if [[ -f "$1" ]]; then
        log_success "File exists: $1"
        return 0
    else
        log_error "File missing: $1"
        return 1
    fi
}

check_dir() {
    if [[ -d "$1" ]]; then
        log_success "Directory exists: $1"
        return 0
    else
        log_error "Directory missing: $1"
        return 1
    fi
}

# Test database connection
test_db() {
    if mysql -u xui -p"${DB_PASSWORD}" -e "USE xui; SELECT 1;" >/dev/null 2>&1; then
        log_success "Database connection: OK"
        return 0
    else
        log_error "Database connection: FAILED"
        return 1
    fi
}

# Test Redis connection
test_redis() {
    if redis-cli -a "${REDIS_PASSWORD}" ping | grep -q PONG; then
        log_success "Redis connection: OK"
        return 0
    else
        log_error "Redis connection: FAILED"
        return 1
    fi
}

# Test PHP-FPM socket
test_php_fpm() {
    if [[ -S /run/php/php8.1-fpm-xui.sock ]]; then
        log_success "PHP-FPM socket: EXISTS"
        return 0
    else
        log_error "PHP-FPM socket: MISSING"
        return 1
    fi
}

# Test web endpoint
test_web() {
    if curl -sf -o /dev/null -w "%{http_code}" "http://localhost" | grep -q "200\|301\|302"; then
        log_success "Web endpoint (HTTP): RESPONDING"
        return 0
    else
        log_error "Web endpoint (HTTP): NOT RESPONDING"
        return 1
    fi
}

# Test HTTPS if SSL configured
test_https() {
    if curl -sfk -o /dev/null -w "%{http_code}" "https://$XUI_DOMAIN" | grep -q "200\|301\|302"; then
        log_success "Web endpoint (HTTPS): RESPONDING"
        return 0
    else
        log_warning "Web endpoint (HTTPS): NOT RESPONDING (may need DNS/SSL setup)"
        return 1
    fi
}

# Test API endpoint
test_api() {
    if curl -sf "http://localhost/player_api.php?username=test&password=test&action=get_user_info" | grep -q "error\|auth"; then
        log_success "Player API: RESPONDING (expected auth error for test creds)"
        return 0
    else
        log_error "Player API: NOT RESPONDING"
        return 1
    fi
}

# Main verification
main() {
    echo "================================================================"
    echo "  XUI One Decoded - Installation Verification"
    echo "================================================================"
    echo
    
    FAILED=0
    
    log_info "=== Checking Required Commands ==="
    check_command nginx || ((FAILED++))
    check_command php8.1 || ((FAILED++))
    check_command mysql || ((FAILED++))
    check_command redis-cli || ((FAILED++))
    check_command ffmpeg || ((FAILED++))
    check_command git || ((FAILED++))
    check_command certbot || ((FAILED++))
    
    echo
    log_info "=== Checking Services ==="
    check_service nginx || ((FAILED++))
    check_service php8.1-fpm || ((FAILED++))
    check_service mariadb || ((FAILED++))
    check_service redis-server || ((FAILED++))
    
    echo
    log_info "=== Checking Ports ==="
    check_port 80 || ((FAILED++))
    check_port 443 || ((FAILED++))
    check_port 3306 || ((FAILED++))
    check_port 6379 || ((FAILED++))
    
    echo
    log_info "=== Checking Files & Directories ==="
    check_dir "$XUI_INSTALL_PATH" || ((FAILED++))
    check_dir "$XUI_INSTALL_PATH/decoded" || ((FAILED++))
    check_dir "$XUI_INSTALL_PATH/decoded/www" || ((FAILED++))
    check_dir "$XUI_INSTALL_PATH/decoded/includes" || ((FAILED++))
    check_dir "$XUI_INSTALL_PATH/decoded/admin" || ((FAILED++))
    check_dir "$XUI_INSTALL_PATH/decoded/includes/cli" || ((FAILED++))
    check_dir "$XUI_INSTALL_PATH/config" || ((FAILED++))
    check_dir "$XUI_INSTALL_PATH/tmp" || ((FAILED++))
    check_dir "$XUI_INSTALL_PATH/tmp/cache" || ((FAILED++))
    check_dir "$XUI_INSTALL_PATH/tmp/flood" || ((FAILED++))
    check_dir "$XUI_INSTALL_PATH/tmp/logs" || ((FAILED++))
    check_dir "$XUI_INSTALL_PATH/tmp/records" || ((FAILED++))
    check_dir "$XUI_INSTALL_PATH/tmp/thumbnails" || ((FAILED++))
    check_file "$XUI_INSTALL_PATH/config/config.ini" || ((FAILED++))
    check_file "$XUI_INSTALL_PATH/decoded/www/constants.php" || ((FAILED++))
    check_file "$XUI_INSTALL_PATH/decoded/www/init.php" || ((FAILED++))
    check_file "$XUI_INSTALL_PATH/decoded/includes/xui.php" || ((FAILED++))
    check_file "$XUI_INSTALL_PATH/decoded/includes/pdo.php" || ((FAILED++))
    check_file "/etc/nginx/sites-enabled/xui" || ((FAILED++))
    check_file "/etc/php/8.1/fpm/pool.d/xui.conf" || ((FAILED++))
    
    echo
    log_info "=== Testing Connections ==="
    test_db || ((FAILED++))
    test_redis || ((FAILED++))
    test_php_fpm || ((FAILED++))
    test_web || ((FAILED++))
    test_https || ((FAILED++))
    test_api || ((FAILED++))
    
    echo
    log_info "=== Checking Permissions ==="
    if [[ -w "$XUI_INSTALL_PATH/tmp/cache" ]]; then
        log_success "Cache directory writable"
    else
        log_error "Cache directory NOT writable"
        ((FAILED++))
    fi
    
    if [[ -r "$XUI_INSTALL_PATH/config/config.ini" ]]; then
        log_success "Config file readable"
    else
        log_error "Config file NOT readable"
        ((FAILED++))
    fi
    
    echo
    echo "================================================================"
    if [[ $FAILED -eq 0 ]]; then
        log_success "ALL CHECKS PASSED! Installation verified successfully."
    else
        log_error "$FAILED check(s) failed. Please review the errors above."
    fi
    echo "================================================================"
    echo
    echo "Useful commands:"
    echo "  View logs: tail -f /var/log/nginx/xui_error.log"
    echo "  PHP logs: tail -f /var/log/php8.1-fpm-xui.log"
    echo "  XUI logs: tail -f $XUI_INSTALL_PATH/tmp/logs/*.log"
    echo "  Restart services: systemctl restart nginx php8.1-fpm"
    echo "  Check status: systemctl status nginx php8.1-fpm mariadb redis-server"
    echo
    
    exit $FAILED
}

main "$@"