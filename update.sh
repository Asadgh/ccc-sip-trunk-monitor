#!/bin/bash
# -------------------------------------------------------------------------
# ccc-sip-monitor Update Script
# -------------------------------------------------------------------------
# This script updates the ccc-sip-trunk-monitor installation by:
#   1) Checking that the install directory exists
#   2) Stopping the systemd services
#   3) Pulling the latest changes from the repository
#   4) Updating Python dependencies
#   5) Recreating a desktop shortcut if needed
#   6) Restarting the services
# -------------------------------------------------------------------------
set -e  # Exit on error

# -------------------------- Configuration ---------------------------
INSTALL_DIR="/opt/ccc-sip-monitor"
VENV_DIR="$INSTALL_DIR/venv"
LOG_COLOR_BLUE="\e[1;34m"
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
    echo -e "${LOG_COLOR_BLUE}>>> $1${LOG_COLOR_RESET}"
}

# --- Ensure the script is run as root (sudo) ---
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)."
    exit 1
fi

# 1) Check if installed
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Error: Installation directory ($INSTALL_DIR) not found."
    echo "Please run the main setup script first."
    exit 1
fi

# 2) Stop services
print_message "Stopping services..."
systemctl stop ccc-sip-monitor-web.service 2>/dev/null || true
systemctl stop ccc-sip-monitor-pinger.service 2>/dev/null || true

# 3) Update repository
print_message "Updating repository..."
cd "$INSTALL_DIR"
git fetch
if git diff --quiet HEAD origin/main; then
    print_message "Already at the latest version. No update needed."
else
    # If you have local changes, this will overwrite them!
    # For safer updating, consider `git stash --include-untracked && git pull --rebase`.
    git reset --hard origin/main
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
    print_message "Repository updated to latest commit on 'main'."
fi

# 4) Update dependencies
print_message "Updating Python dependencies..."
sudo -u "$SERVICE_USER" "$VENV_DIR/bin/pip" install --upgrade pip
if [ -f "$INSTALL_DIR/requirements.txt" ]; then
    sudo -u "$SERVICE_USER" "$VENV_DIR/bin/pip" install -r "$INSTALL_DIR/requirements.txt" --upgrade
fi
sudo -u "$SERVICE_USER" "$VENV_DIR/bin/pip" install gunicorn --upgrade

# 5) Create desktop shortcut if it doesn't exist
print_message "Checking desktop shortcut..."
if [ ! -f "$DESKTOP_DIR/SIP-Monitor.desktop" ]; then
    print_message "Creating desktop shortcut..."
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    
    mkdir -p "$DESKTOP_DIR"
    cat > "$DESKTOP_DIR/SIP-Monitor.desktop" << EOF
[Desktop Entry]
Type=Application
Name=SIP Monitor
Comment=Launch SIP Monitor Web Interface
Exec=chromium-browser http://$IP_ADDRESS:5000
Icon=web-browser
Terminal=false
Categories=Network;
EOF
    
    chmod +x "$DESKTOP_DIR/SIP-Monitor.desktop"
    chown "$SERVICE_USER:$SERVICE_USER" "$DESKTOP_DIR/SIP-Monitor.desktop"
fi

# 6) Restart services
print_message "Restarting services..."
systemctl daemon-reload
systemctl restart ccc-sip-monitor-web.service ccc-sip-monitor-pinger.service

# Final message
print_message "Update complete!"
echo "Web interface is available at: http://$(hostname -I | awk '{print $1}'):5000"
echo "Check status with: systemctl status ccc-sip-monitor-web.service ccc-sip-monitor-pinger.service"
echo "Desktop shortcut: $DESKTOP_DIR/SIP-Monitor.desktop"
