#!/bin/bash
# =============================================================================
# Quick Fix Script for Current Server Issues (192.168.1.34)
# =============================================================================
# Run this on the server to fix: 403 Forbidden, goto label errors, symlinks
# =============================================================================

set -euo pipefail

XUI_PATH="/var/www/xui"

log_info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;32m[OK]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

main() {
    log_info "Fixing XUI One Decoded on $(hostname)..."
    
    # 1. Restore player/functions.php from git
    log_info "1. Restoring player/functions.php from git..."
    cd "$XUI_PATH"
    git checkout -- decoded/player/functions.php
    php -l decoded/player/functions.php && log_success "player/functions.php syntax OK" || log_error "Syntax error remains"
    
    # 2. Fix admin symlink
    log_info "2. Fixing admin symlink..."
    rm -rf "$XUI_PATH/decoded/www/admin"
    ln -sf ../admin "$XUI_PATH/decoded/www/admin"
    ls -la "$XUI_PATH/decoded/www/admin" | grep -q "^l" && log_success "admin symlink OK" || log_error "admin symlink failed"
    
    # 3. Fix player symlink
    log_info "3. Fixing player symlink..."
    rm -rf "$XUI_PATH/decoded/www/player"
    ln -sf ../player "$XUI_PATH/decoded/www/player"
    ls -la "$XUI_PATH/decoded/www/player" | grep -q "^l" && log_success "player symlink OK" || log_error "player symlink failed"
    
    # 4. Fix reseller symlink
    log_info "4. Fixing reseller symlink..."
    rm -rf "$XUI_PATH/decoded/www/reseller"
    ln -sf ../reseller "$XUI_PATH/decoded/www/reseller"
    ls -la "$XUI_PATH/decoded/www/reseller" | grep -q "^l" && log_success "reseller symlink OK" || log_error "reseller symlink failed"
    
    # 5. Verify all symlinks
    log_info "5. Verifying symlinks..."
    ls -la "$XUI_PATH/decoded/www/" | grep -E "^l.*(admin|player|reseller)"
    
    # 6. Fix permissions
    log_info "6. Fixing permissions..."
    chown -R www-data:www-data "$XUI_PATH"
    find "$XUI_PATH" -type f -name "*.php" -exec chmod 644 {} \;
    find "$XUI_PATH" -type d -exec chmod 755 {} \;
    chmod -R 777 "$XUI_PATH/tmp"
    chmod 640 "$XUI_PATH/config/config.ini"
    chown www-data:www-data "$XUI_PATH/config/config.ini"
    log_success "Permissions fixed"
    
    # 7. Restart services
    log_info "7. Restarting services..."
    systemctl restart php8.3-fpm nginx 2>/dev/null || systemctl restart php8.1-fpm nginx
    log_success "Services restarted"
    
    # 8. Test endpoints
    log_info "8. Testing endpoints..."
    echo "=== ROOT ==="
    curl -s http://localhost/ | head -5
    echo ""
    echo "=== ADMIN ==="
    curl -s http://localhost/admin/login.php | head -5
    echo ""
    echo "=== PLAYER ==="
    curl -s http://localhost/player/ | head -5
    echo ""
    
    log_success "Fix complete! Check output above for HTML content (not 403)."
    echo ""
    echo "If still seeing 403, check:"
    echo "  - Nginx config has 'index init.php;' and correct try_files"
    echo "  - Nginx config uses 'alias' with '\$request_filename' for admin/player/reseller"
    echo "  - PHP-FPM socket matches nginx config: /run/php/php8.3-fpm-xui.sock"
}

main "$@"