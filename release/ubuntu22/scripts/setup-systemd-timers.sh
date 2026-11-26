#!/bin/bash
# =============================================================================
# XUI One Decoded - Systemd Timers Setup Script
# =============================================================================
# Alternative to cron: uses systemd timers for better logging and management
# =============================================================================

set -euo pipefail

XUI_INSTALL_PATH="${XUI_INSTALL_PATH:-/var/www/xui}"

SYSTEMD_DIR="/etc/systemd/system"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;32m[OK]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

main() {
    log_info "Installing systemd service files..."
    
    # Copy service files
    for service in "$SCRIPT_DIR"/../systemd/*.service; do
        cp "$service" "$SYSTEMD_DIR/"
        log_success "Installed: $(basename "$service")"
    done
    
    # Copy timer files
    for timer in "$SCRIPT_DIR"/../systemd/*.timer; do
        cp "$timer" "$SYSTEMD_DIR/"
        log_success "Installed: $(basename "$timer")"
    done
    
    # Reload systemd
    systemctl daemon-reload
    log_success "Systemd daemon reloaded"
    
    # Enable and start timers
    systemctl enable --now xui-monitor.timer
    systemctl enable --now xui-queue.timer
    systemctl enable --now xui-epg.timer
    systemctl enable --now xui-cache.timer
    
    # Enable daemon services (if using load balancer)
    # systemctl enable --now xui-balancer.service
    # systemctl enable --now xui-loopback.service
    
    log_success "Systemd timers enabled and started"
    
    echo
    echo "Useful commands:"
    echo "  View timer status: systemctl list-timers --all | grep xui"
    echo "  View service logs: journalctl -u xui-monitor -f"
    echo "  Run manually: systemctl start xui-monitor"
    echo "  Disable timer: systemctl disable --now xui-monitor.timer"
    echo
}

main "$@"