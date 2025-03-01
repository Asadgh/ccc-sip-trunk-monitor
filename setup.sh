#!/bin/bash
# --------------------------------------------------------------------------
# ccc-sip-monitor Setup Script
# --------------------------------------------------------------------------
# This script installs and configures the ccc-sip-trunk-monitor application
# on a Raspberry Pi (or Debian-based system) with LXDE-pi desktop. It:
#  1) Installs required packages
#  2) Clones or updates the repository
#  3) Creates a Python virtual environment and installs Python dependencies
#  4) Prompts for config.json path and symlinks it
#  5) Creates systemd service units (bind to 0.0.0.0, restart on failure)
#     & logs to /var/log/ccc-sip-monitor/
#  6) Creates a desktop shortcut pointing to localhost
#  7) Updates PCManFM to "execute" text files without prompt
#  8) Optionally enables and starts those services
# --------------------------------------------------------------------------
set -e  # Exit on any error

# -------------------------- Configuration ---------------------------
REPO_URL="https://github.com/Asadgh/ccc-sip-trunk-monitor.git"
INSTALL_DIR="/opt/ccc-sip-monitor"
VENV_DIR="$INSTALL_DIR/venv"
LOG_DIR="/var/log/ccc-sip-monitor"

# Detect which user invoked sudo (or fallback to current user)
if [ -n "$SUDO_USER" ]; then
    SERVICE_USER="$SUDO_USER"
else
    SERVICE_USER="$(whoami)"
fi

# On Raspberry Pi OS with LXDE-pi, the desktop folder is typically:
DESKTOP_DIR="/home/$SERVICE_USER/Desktop"
PCMANFM_CONFIG="/home/$SERVICE_USER/.config/pcmanfm/LXDE-pi/pcmanfm.conf"

echo ">>> Running ccc-sip-monitor setup script as user: $SERVICE_USER"

# 1) Update system and install dependencies
echo ">>> Installing system dependencies..."
apt-get update -y
apt-get install -y git curl python3 python3-pip python3-venv sqlite3 chromium-browser

# 2) Create or update installation directory
echo ">>> Preparing installation directory at $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"

# 3) Clone or pull the latest repository
if [ -d "$INSTALL_DIR/.git" ]; then
    echo ">>> Repository exists, pulling latest changes..."
    cd "$INSTALL_DIR"
    git pull
else
    echo ">>> Cloning repository from $REPO_URL ..."
    git clone "$REPO_URL" "$INSTALL_DIR"
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
fi

# 4) Create and activate a Python virtual environment
echo ">>> Setting up Python virtual environment..."
if [ ! -d "$VENV_DIR" ]; then
    sudo -u "$SERVICE_USER" python3 -m venv "$VENV_DIR"
fi
sudo -u "$SERVICE_USER" "$VENV_DIR/bin/pip" install --upgrade pip

# 5) Install Python dependencies
echo ">>> Installing Python dependencies..."
if [ ! -f "$INSTALL_DIR/requirements.txt" ]; then
    echo ">>> requirements.txt not found, creating a basic one..."
    cat > "$INSTALL_DIR/requirements.txt" << EOF
Flask==2.0.1
gunicorn==20.1.0
typing-extensions==4.0.1
dataclasses==0.8; python_version < "3.7"
EOF
    chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/requirements.txt"
fi
sudo -u "$SERVICE_USER" "$VENV_DIR/bin/pip" install -r "$INSTALL_DIR/requirements.txt"
sudo -u "$SERVICE_USER" "$VENV_DIR/bin/pip" install gunicorn

# 6) Prompt for the config file location and symlink if valid
CONFIG_LINK="$INSTALL_DIR/config.json"

if [ ! -t 0 ]; then
    echo "Forcing interactive mode from /dev/tty..."
    exec < /dev/tty
    read -p "Enter the path to your config.json file: " CONFIG_PATH
fi

# Prompt for config file path

# Check if the file exists, then copy
if [ -f "$CONFIG_PATH" ]; then
    echo ">>> Copying config file to $CONFIG_TARGET ..."
    cp -f "$CONFIG_PATH" "$CONFIG_TARGET"
    chown "$SUDO_USER:$SUDO_USER" "$CONFIG_TARGET"
    echo "Copied: $CONFIG_PATH -> $CONFIG_TARGET"
else
    echo ">>> WARNING: Config file not found at '$CONFIG_PATH'."
    echo ">>> You can place a valid config.json at $CONFIG_TARGET later."
fi

# 7) Create a directory for logs and adjust permissions
echo ">>> Setting up log directory at $LOG_DIR ..."
mkdir -p "$LOG_DIR"
chown "$SERVICE_USER:$SERVICE_USER" "$LOG_DIR"
chmod 755 "$LOG_DIR"

# 8) Create systemd service files with restart-on-failure and logging
echo ">>> Creating systemd service files..."

# ccc-sip-monitor-web.service
cat > /etc/systemd/system/ccc-sip-monitor-web.service << EOF
[Unit]
Description=CCC SIP Monitor - Web Service
After=network.target

[Service]
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$VENV_DIR/bin/gunicorn --workers 3 --bind 0.0.0.0:5000 app:app
Restart=on-failure
RestartSec=10
StandardOutput=append:$LOG_DIR/web.log
StandardError=append:$LOG_DIR/web.log

[Install]
WantedBy=multi-user.target
EOF

# ccc-sip-monitor-pinger.service
cat > /etc/systemd/system/ccc-sip-monitor-pinger.service << EOF
[Unit]
Description=CCC SIP Monitor - Pinger Service
After=network.target

[Service]
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$VENV_DIR/bin/python pinger.py
Restart=on-failure
RestartSec=10
StandardOutput=append:$LOG_DIR/pinger.log
StandardError=append:$LOG_DIR/pinger.log

[Install]
WantedBy=multi-user.target
EOF

# 9) Create a desktop shortcut to open the web interface on localhost
echo ">>> Creating desktop shortcut for the SIP Monitor..."
mkdir -p "$DESKTOP_DIR"

cat <<EOF > "$DESKTOP_DIR/SIP-Monitor.desktop"
[Desktop Entry]
Type=Application
Name=SIP Monitor
Comment=Launch SIP Monitor Web Interface (Localhost)
Exec=chromium-browser http://localhost:5000
Icon=web-browser
Terminal=false
Categories=Network;
EOF

chmod +x "$DESKTOP_DIR/SIP-Monitor.desktop"
chown "$SERVICE_USER:$SERVICE_USER" "$DESKTOP_DIR/SIP-Monitor.desktop"

# 10) Configure PCManFM to execute text files without prompting
#     0=Ask, 1=Execute, 2=Open in text editor
echo ">>> Configuring PCManFM to execute scripts without prompt..."
mkdir -p "$(dirname "$PCMANFM_CONFIG")"
if [ -f "$PCMANFM_CONFIG" ]; then
    sed -i 's/^\(exec_cmd\s*=\s*\).*/\11/' "$PCMANFM_CONFIG" || true
    if ! grep -q "^exec_cmd=" "$PCMANFM_CONFIG"; then
        echo "exec_cmd=1" >> "$PCMANFM_CONFIG"
    fi
else
    cat <<EOF > "$PCMANFM_CONFIG"
[ui]
exec_cmd=1
EOF
fi
chown "$SERVICE_USER:$SERVICE_USER" "$PCMANFM_CONFIG"
echo ">>> PCManFM set to automatically execute scripts."

# 11) Enable and start services only if we have a config.json
if [ -f "$CONFIG_LINK" ]; then
    echo ">>> Enabling and starting services..."
    systemctl daemon-reload
    systemctl enable ccc-sip-monitor-web.service ccc-sip-monitor-pinger.service
    systemctl start ccc-sip-monitor-web.service ccc-sip-monitor-pinger.service
    echo ">>> Services are now active. Check logs in $LOG_DIR/ or use 'journalctl -u ccc-sip-monitor-...'."
else
    echo ">>> Config file not found. Services have been created but NOT started."
    echo ">>> Once you have a valid config.json, run:
  sudo systemctl daemon-reload
  sudo systemctl enable --now ccc-sip-monitor-web.service ccc-sip-monitor-pinger.service
"
fi

echo ">>> Setup complete!"
echo "You can check service status with:
  systemctl status ccc-sip-monitor-web.service
  systemctl status ccc-sip-monitor-pinger.service
Logs are stored in: $LOG_DIR/
Desktop shortcut: $DESKTOP_DIR/SIP-Monitor.desktop
"
echo ">>> Note: If you still see a prompt when clicking the desktop shortcut,
log out and log back in or restart your system for PCManFM changes to fully apply."
