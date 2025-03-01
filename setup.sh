#!/bin/bash
# Network Monitor Setup Script for Raspberry Pi
# This script automates the installation and setup of the ccc-sip-trunk-monitor
set -e  # Exit on error

# Configuration
REPO_URL="https://github.com/Asadgh/ccc-sip-trunk-monitor.git"
INSTALL_DIR="/opt/ccc-sip-monitor"
VENV_DIR="$INSTALL_DIR/venv"
if [ -n "$SUDO_USER" ]; then
    SERVICE_USER="$SUDO_USER"
else
    SERVICE_USER=$(whoami)
fi
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

# Step 1: Update system and install dependencies
print_message "Updating system and installing dependencies..."
apt-get update
apt-get install -y git curl python3 python3-pip python3-venv sqlite3

# Step 2: Create installation directory
print_message "Creating installation directory..."
mkdir -p $INSTALL_DIR
chown $SERVICE_USER:$SERVICE_USER $INSTALL_DIR

# Step 3: Clone repository
print_message "Cloning repository..."
if [ -d "$INSTALL_DIR/.git" ]; then
    print_message "Repository already exists, updating..."
    cd $INSTALL_DIR
    git pull
else
    git clone $REPO_URL $INSTALL_DIR
    chown -R $SERVICE_USER:$SERVICE_USER $INSTALL_DIR
fi

# Step 4: Create and activate virtual environment
print_message "Setting up virtual environment..."
if [ ! -d "$VENV_DIR" ]; then
    sudo -u $SERVICE_USER python3 -m venv $VENV_DIR
fi

# Step 5: Install requirements
print_message "Installing Python dependencies..."
sudo -u $SERVICE_USER $VENV_DIR/bin/pip install --upgrade pip

# Create requirements.txt if it doesn't exist
if [ ! -f "$INSTALL_DIR/requirements.txt" ]; then
    print_message "Creating requirements.txt..."
    cat > $INSTALL_DIR/requirements.txt << EOF
Flask==2.0.1
gunicorn==20.1.0
typing-extensions==4.0.1
dataclasses==0.8; python_version < "3.7"
EOF
    chown $SERVICE_USER:$SERVICE_USER $INSTALL_DIR/requirements.txt
fi

sudo -u $SERVICE_USER $VENV_DIR/bin/pip install -r $INSTALL_DIR/requirements.txt
sudo -u $SERVICE_USER $VENV_DIR/bin/pip install gunicorn  # For production Flask serving

# Step 6: Prompt for config file location and create symbolic link
print_message "Configuration setup..."
read -p "Enter the path to your config.json file: " CONFIG_PATH

if [ -f "$CONFIG_PATH" ]; then
    print_message "Creating symbolic link to config file..."
    ln -sf "$CONFIG_PATH" "$INSTALL_DIR/config.json"
    chown -h $SERVICE_USER:$SERVICE_USER "$INSTALL_DIR/config.json"
else
    print_message "Config file not found at $CONFIG_PATH. Please create one before starting the services."
    
    # Create a template config.json if it doesn't exist
    if [ ! -f "$INSTALL_DIR/config.json.template" ]; then
        cat > $INSTALL_DIR/config.json.template << EOF
{
  "database_path": "database.db",
  "servers": [
    {
      "partner": "Example",
      "country": "US",
      "ip": "example.com",
      "dn_ext": "com"
    }
  ],
  "ping_count": 4,
  "ping_timeout": 5,
  "windows_params": {
    "os": "windows",
    "count_param": "-n",
    "timeout_param": "-w"
  },
  "unix_params": {
    "os": "unix",
    "count_param": "-c",
    "timeout_param": "-W"
  },
  "latency_thresholds": {
    "excellent": 50,
    "good": 100,
    "fair": 150,
    "poor": 300,
    "critical": 500
  }
}
EOF
        chown $SERVICE_USER:$SERVICE_USER $INSTALL_DIR/config.json.template
        print_message "A template config file has been created at $INSTALL_DIR/config.json.template"
        print_message "Please copy and modify this template, then restart the services."
    fi
fi

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

# Step 7: Create systemd service files
print_message "Creating systemd service files..."
# Flask Server Service
cat > /etc/systemd/system/ccc-sip-monitor-web.service << EOF
[Unit]
Description=Network Monitor Web Service
After=network.target

[Service]
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$VENV_DIR/bin/gunicorn --workers 3 --bind 0.0.0.0:5000 app:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Pinger Service
cat > /etc/systemd/system/ccc-sip-monitor-pinger.service << EOF
[Unit]
Description=Network Monitor Pinger Service
After=network.target

[Service]
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$VENV_DIR/bin/python pinger.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Step 8: Enable and start services if config exists
if [ -f "$INSTALL_DIR/config.json" ]; then
    print_message "Enabling and starting services..."
    systemctl daemon-reload
    systemctl enable ccc-sip-monitor-web.service ccc-sip-monitor-pinger.service
    systemctl start ccc-sip-monitor-web.service ccc-sip-monitor-pinger.service
else
    print_message "Services have been created but not started due to missing config file."
    print_message "After setting up your config file, run: systemctl enable --now ccc-sip-monitor-web.service ccc-sip-monitor-pinger.service"
fi

# Final message
print_message "Installation complete!"
print_message "Web interface will be available at: http://$(hostname -I | awk '{print $1}'):5000"
print_message "Check status with: systemctl status ccc-sip-monitor-web.service ccc-sip-monitor-pinger.service"

if [ ! -f "$INSTALL_DIR/config.json" ]; then
    print_message "IMPORTANT: You need to set up your config file before the system will work!"
    print_message "Use the template at $INSTALL_DIR/config.json.template as a starting point."
fi