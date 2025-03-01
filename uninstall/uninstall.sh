#!/bin/bash
# -------------------------------------------------------------------------
# ccc-sip-monitor Removal Script
# -------------------------------------------------------------------------
# This script completely removes the ccc-sip-trunk-monitor installation by:
#   1) Stopping and disabling the services
#   2) Removing the systemd service files
#   3) Removing the desktop shortcut
#   4) Deleting the installation directory
#   5) Optionally removing dependencies
# -------------------------------------------------------------------------
set -e  # Exit on error

# -------------------------- Configuration ---------------------------
INSTALL_DIR="/opt/ccc-sip-monitor"
LOG_COLOR_RED="\e[1;31m"
LOG_COLOR_RESET="\e[0m"
# --------------------------------------------------------------------

# --- Detect the user who invoked sudo (or fallback to current user) ---
if [ -n "$SUDO_USER" ]; then
    SERVICE_USER="$SUDO_USER"
else
    SERVICE_USER="$(whoami)"
fi

DESKTOP_DIR="/home/$SERVICE_USER/Desktop"

# --- Logging function for consistent colored output ---
print_message() {
    echo -e "${LOG_COLOR_RED}>>> $1${LOG_COLOR_RESET}"
}

# --- Ensure the script is run as root (sudo) ---
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)."
    exit 1
fi

# Confirm removal
echo "WARNING: This will completely remove the SIP Monitor application from your system."
read -p "Are you sure you want to continue? (y/N): " confirm
if [[ $confirm != [Yy]* ]]; then
    echo "Operation cancelled."
    exit 0
fi

# 1) Stop and disable services
print_message "Stopping and disabling services..."
systemctl stop ccc-sip-monitor-web.service ccc-sip-monitor-pinger.service 2>/dev/null || true
systemctl disable ccc-sip-monitor-web.service ccc-sip-monitor-pinger.service 2>/dev/null || true

# 2) Remove systemd service files
print_message "Removing systemd service files..."
rm -f /etc/systemd/system/ccc-sip-monitor-web.service
rm -f /etc/systemd/system/ccc-sip-monitor-pinger.service
systemctl daemon-reload

# 3) Remove desktop shortcut
if [ -f "$DESKTOP_DIR/SIP-Monitor.desktop" ]; then
    print_message "Removing desktop shortcut..."
    rm -f "$DESKTOP_DIR/SIP-Monitor.desktop"
fi

# 4) Remove installation directory
if [ -d "$INSTALL_DIR" ]; then
    print_message "Removing installation directory..."
    rm -rf "$INSTALL_DIR"
fi

# (Optional) Remove log directory if you created one in /var/log/ccc-sip-monitor
LOG_DIR="/var/log/ccc-sip-monitor"
if [ -d "$LOG_DIR" ]; then
    read -p "Would you like to remove the log directory at $LOG_DIR? (y/N): " remove_logs
    if [[ $remove_logs == [Yy]* ]]; then
        print_message "Removing log directory..."
        rm -rf "$LOG_DIR"
    else
        echo "Skipping log directory removal."
    fi
fi

# 5) Optionally remove dependencies
read -p "Would you like to remove dependencies installed by the setup script? (y/N): " remove_deps
if [[ $remove_deps == [Yy]* ]]; then
    print_message "Removing dependencies..."
    # Use with caution—removing these might affect other applications
    apt-get remove -y python3-venv sqlite3 chromium-browser
else
    print_message "Skipping dependency removal."
fi

# Final message
print_message "Removal complete!"
echo "The SIP Monitor has been completely uninstalled from your system."
