#!/bin/bash
# Network Monitor Removal Script for Raspberry Pi
# This script completely removes the ccc-sip-trunk-monitor installation
set -e  # Exit on error

# Configuration
INSTALL_DIR="/opt/ccc-sip-monitor"
SERVICE_USER="pi"  # Change if using a different user
DESKTOP_DIR="/home/$SERVICE_USER/Desktop"

# Function to print colored messages
print_message() {
    echo -e "\e[1;31m>>> $1\e[0m"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)"
    exit 1
fi

# Confirm removal
echo "WARNING: This will completely remove the SIP Monitor application from your system."
read -p "Are you sure you want to continue? (y/N): " confirm
if [[ $confirm != [Yy]* ]]; then
    echo "Operation cancelled."
    exit 0
fi

# Step 1: Stop and disable services
print_message "Stopping and disabling services..."
systemctl stop ccc-sip-monitor-web.service ccc-sip-monitor-pinger.service 2>/dev/null || true
systemctl disable ccc-sip-monitor-web.service ccc-sip-monitor-pinger.service 2>/dev/null || true

# Step 2: Remove service files
print_message "Removing systemd service files..."
rm -f /etc/systemd/system/ccc-sip-monitor-web.service
rm -f /etc/systemd/system/ccc-sip-monitor-pinger.service
systemctl daemon-reload

# Step 3: Remove desktop shortcut
if [ -f "$DESKTOP_DIR/SIP-Monitor.desktop" ]; then
    print_message "Removing desktop shortcut..."
    rm -f "$DESKTOP_DIR/SIP-Monitor.desktop"
fi

# Step 4: Remove installation directory
if [ -d "$INSTALL_DIR" ]; then
    print_message "Removing installation directory..."
    rm -rf "$INSTALL_DIR"
fi

# Step 5: Clean up (optional, ask user)
read -p "Would you like to remove dependencies installed by the setup script? (y/N): " remove_deps
if [[ $remove_deps == [Yy]* ]]; then
    print_message "Removing dependencies..."
    # Note: This is a basic approach. Use with caution as it might affect other applications
    apt-get remove -y python3-venv sqlite3
else
    print_message "Skipping dependency removal."
fi

# Final message
print_message "Removal complete! The SIP Monitor has been completely uninstalled from your system."