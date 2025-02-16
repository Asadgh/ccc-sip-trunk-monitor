#!/bin/bash
# Network Monitor Update Script for Raspberry Pi
# This script updates the ccc-sip-trunk-monitor installation
set -e  # Exit on error

# Configuration
INSTALL_DIR="/opt/ccc-sip-monitor"
VENV_DIR="$INSTALL_DIR/venv"
SERVICE_USER="pi"  # Change if using a different user
DESKTOP_DIR="/home/$SERVICE_USER/Desktop"

# Function to print colored messages
print_message() {
    echo -e "\e[1;34m>>> $1\e[0m"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)"
    exit 1
fi

# Step 1: Check if installed
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Error: Installation directory not found. Please run the installation script first."
    exit 1
fi

# Step 2: Stop services
print_message "Stopping services..."
systemctl stop ccc-sip-monitor-web.service ccc-sip-monitor-pinger.service

# Step 3: Update repository
print_message "Updating repository..."
cd $INSTALL_DIR
git fetch
if git diff --quiet HEAD origin/main; then
    print_message "Already at the latest version. No update needed."
else
    git reset --hard origin/main  # Replace with your main branch if different
    chown -R $SERVICE_USER:$SERVICE_USER $INSTALL_DIR
fi

# Step 4: Update dependencies
print_message "Updating Python dependencies..."
sudo -u $SERVICE_USER $VENV_DIR/bin/pip install --upgrade pip
sudo -u $SERVICE_USER $VENV_DIR/bin/pip install -r $INSTALL_DIR/requirements.txt --upgrade
sudo -u $SERVICE_USER $VENV_DIR/bin/pip install gunicorn --upgrade

# Step 5: Create desktop shortcut if it doesn't exist
print_message "Checking desktop shortcut..."
if [ ! -f "$DESKTOP_DIR/SIP-Monitor.desktop" ]; then
    print_message "Creating desktop shortcut..."
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    
    mkdir -p $DESKTOP_DIR
    cat > $DESKTOP_DIR/SIP-Monitor.desktop << EOF
[Desktop Entry]
Type=Application
Name=SIP Monitor
Comment=Launch SIP Monitor Web Interface
Exec=chromium-browser http://$IP_ADDRESS:5000
Icon=web-browser
Terminal=false
Categories=Network;
EOF
    
    chmod +x $DESKTOP_DIR/SIP-Monitor.desktop
    chown $SERVICE_USER:$SERVICE_USER $DESKTOP_DIR/SIP-Monitor.desktop
fi

# Step 6: Restart services
print_message "Restarting services..."
systemctl daemon-reload
systemctl restart ccc-sip-monitor-web.service ccc-sip-monitor-pinger.service

# Final message
print_message "Update complete!"
print_message "Web interface is available at: http://$(hostname -I | awk '{print $1}'):5000"
print_message "Check status with: systemctl status ccc-sip-monitor-web.service ccc-sip-monitor-pinger.service"
print_message "A desktop shortcut has been created for easy access."