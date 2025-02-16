# Network Monitoring System

A comprehensive solution for monitoring network latency and connectivity across multiple servers.

## Overview

This application provides real-time and historical monitoring of network performance across various global servers. It collects ping statistics, analyzes latency patterns, and presents the data through an interactive web dashboard.

## Features

- **Real-time Monitoring**: Continuously pings configured servers and collects performance metrics
- **Historical Data Analysis**: Store and visualize ping statistics over time
- **Interactive Dashboard**: Filter and view data by country, time range, and other parameters
- **Alert System**: Automatically detects and flags high latency, packet loss, and stale data
- **Cross-platform Support**: Works on both Windows and Unix-like systems
- **Comprehensive Logging**: Maintains detailed logs of system operations and network events

## Components

### 1. Backend Ping Service (`pinger.py`)

- Initializes SQLite database for storing ping results and logs
- Continuously pings configured servers at regular intervals
- Analyzes network performance based on configurable thresholds
- Detects and logs anomalies and concerning conditions
- Handles platform-specific ping command differences

### 2. Web Application (`app.py`)

- Flask-based web server providing both UI and API endpoints
- Serves the main dashboard interface
- Provides RESTful API endpoints for:
  - Ping data retrieval with flexible filtering
  - Server status information
  - System logs access
- Processes and formats data for visualization

### 3. Database

SQLite database with tables for:
- `ping_results`: Stores all ping statistics with server details
- `logs`: Maintains system events and warnings

## Setup and Installation

### Prerequisites

- Python 3.6 or higher
- Flask
- SQLite3
- Network access to target servers

### Configuration

1. Create a `config.json` file with the following structure:

```json
{
  "database_path": "database.db",
  "servers": [
    {
      "partner": "PartnerName",
      "country": "CountryName",
      "ip": "server.ip.address",
      "dn_ext": "domain.extension"
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
```

### Installation

## Alt 1: Using Curl
curl -sSL https://raw.githubusercontent.com/Asadgh/ccc-sip-trunk-monitor/main/setup.sh | sudo bash

# Alt 2
1. Clone the repository
2. Install dependencies: `pip install -r requirements.txt`
3. Configure your `config.json` with appropriate server details
4. Initialize the database: `python pinger.py --init-db` (this is handled automatically on first run)

## Usage

### Starting the Services

1. Start the ping service: `python pinger.py`
2. Start the web application: `python app.py`
3. Access the dashboard at: `http://localhost:5000`

### API Endpoints

#### 1. Ping Data: `/api/ping-data`
- Query parameters:
  - `country`: Filter by country (can be multiple)
  - `range`: Time range (`24h`, `7d`, `30d`, or `custom`)
  - `start` & `end`: ISO format dates for custom range

#### 2. Server Status: `/api/servers/status`
- Returns current status of all monitored servers

#### 3. System Logs: `/api/logs`
- Query parameters:
  - `limit`: Number of logs to return (default: 10)
  - `level`: Filter by log level

## Dashboard Features

- Real-time status indicators for all monitored servers
- Interactive charts for visualizing latency trends
- Filtering capabilities by country and time period
- Alerting for high latency or server connectivity issues
- Log viewer for system events

## Monitoring and Alerts

The system automatically detects:
- High latency conditions (configurable thresholds)
- Packet loss above acceptable levels
- Stale data (no updates from servers)
- Jitter and network instability

Warnings are logged and displayed on the dashboard when these conditions occur.

## Extending the System

### Adding New Servers

1. Add new server details to the `config.json` file
2. Restart the ping service

### Customizing Thresholds

Modify the `latency_thresholds` in `config.json` to adjust sensitivity to network conditions.

## Troubleshooting

### Common Issues

1. **Database Locks**: If you see database lock errors, ensure only one instance of the ping service is running
2. **Missing Data**: Check that the ping service is running and has network access to target servers
3. **High Latency Alerts**: Verify network conditions and adjust thresholds if necessary

### Logs

Check the system logs through the dashboard or query the `logs` table in the database for detailed error information.