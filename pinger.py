import subprocess
import sqlite3
import platform
import logging
import json
import os
import sys
import traceback
import time
from datetime import datetime, timedelta
from typing import List, Dict, Optional
from pathlib import Path
from dataclasses import dataclass
from typing import Optional, Dict, Any


with open('config.json', 'r') as fh:
    config = json.load(fh)

conn_timeout = 5
conn = sqlite3.connect(config['database_path'], timeout=conn_timeout)


class Logger:
    def __init__(self):
        """
        Initialize the SQLite logger with a specific database path.
        """
        self.db_path = config['database_path']
        self._create_logs_table()

    def _create_logs_table(self):
        """
        Create logs table if it doesn't exist.
        """
        cursor = conn.cursor()
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                level TEXT,
                message TEXT,
                module TEXT,
                traceback TEXT
            )
        ''')
        conn.commit()

    def log(self, 
            message: str, 
            level: str = 'INFO', 
            module: Optional[str] = None, 
            tb: Optional[Any] = None):
        """
        Log a message to the SQLite database.
        
        Args:
            message (str): The log message to store.
            level (str): Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL). Defaults to 'INFO'.
            module (str, optional): Module or source of the log.
            extra_info (Any, optional): Additional context or information to log.
        """
        # Validate log level
        valid_levels = ['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL']
        if level.upper() not in valid_levels:
            raise ValueError(f"Invalid log level. Must be one of {valid_levels}")

        traceback_text = None
        if tb:
            traceback_text = ''.join(traceback.format_exception(*tb))

        # Insert log entry
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO logs 
            (level, message, module, traceback) 
            VALUES (?, ?, ?, ?)
        ''', (level.upper(), message, module, traceback_text))
        conn.commit()

    def get_logs(self, 
                 level: Optional[str] = None, 
                 module: Optional[str] = None, 
                 limit: int = 100):
        """
        Retrieve logs from the database with optional filtering.
        
        Args:
            level (str, optional): Filter by log level.
            module (str, optional): Filter by module.
            limit (int): Maximum number of logs to retrieve. Defaults to 100.
        
        Returns:
            list: List of log entries matching the filter.
        """
        cursor = conn.cursor()
        query = "SELECT * FROM logs WHERE 1=1"
        params = []

        if level:
            query += " AND level = ?"
            params.append(level.upper())
        
        if module:
            query += " AND module = ?"
            params.append(module)
        
        query += " ORDER BY timestamp DESC LIMIT ?"
        params.append(limit)

        cursor.execute(query, params)
        return cursor.fetchall()


logger = Logger()

def init_database() -> None:
    """
    Initialize SQLite database with enhanced statistics table
    """
    try:
        cursor = conn.cursor()

        cursor.execute('''
            CREATE TABLE IF NOT EXISTS ping_results (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                server_ip TEXT NOT NULL,
                country TEXT NOT NULL,
                partner TEXT NOT NULL,
                dn_ext TEXT NOT NULL,
                timestamp DATETIME NOT NULL,
                packets_transmitted INTEGER NOT NULL,
                packets_received INTEGER NOT NULL,
                packets_lost INTEGER NOT NULL,
                loss_percentage REAL NOT NULL,
                min_time REAL,
                avg_time REAL,
                max_time REAL,
                mdev_time REAL,
                is_high_latency BOOLEAN NOT NULL,
                success BOOLEAN NOT NULL,
                concerns TEXT
            )
        ''')

        # Create indexes for better query performance
        cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_server_timestamp 
            ON ping_results(server_ip, timestamp)
        ''')

        conn.commit()
        logger.log("Database initialized successfully", 'INFO', 'DB_INIT')
        
    except Exception as e:
        logger.log(f"Database initialization error: {e}", "ERROR", "DB_INIT", sys.exc_info())
        raise

init_database()


@dataclass
class PingStats:
    packets_transmitted: int
    packets_received: int
    packets_lost: int
    loss_percentage: float
    min_time: Optional[float]
    avg_time: Optional[float]
    max_time: Optional[float]
    mdev_time: Optional[float]

class Server:
    def __init__(self, server_info: Dict) -> None:
        self.partner = server_info['partner']
        self.country = server_info['country']
        self.ip = server_info['ip']
        self.dn_ext = server_info['dn_ext']
        self.os_params = config['windows_params'] if platform.system().lower() == 'windows' else config['unix_params']
        self.thresholds = config['latency_thresholds']

    def run_ping_tests(self) -> None:
        """
        Run ping tests for configured servers
        """
        current_time = datetime.now()
        cursor = conn.cursor()

        try:
            stats = self.ping(self.ip)
            latency_stats = self.analyze_latency(stats)
            
            cursor.execute('''
                INSERT INTO ping_results (
                    server_ip, country, partner, dn_ext, timestamp, 
                    packets_transmitted, packets_received,
                    packets_lost, loss_percentage, min_time, avg_time,
                    max_time, mdev_time, is_high_latency, success, concerns
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                self.ip, self.country, self.partner, self.dn_ext,
                current_time, stats['packets_transmitted'],
                stats['packets_received'], stats['packets_lost'],
                stats['loss_percentage'], float(stats['min_time']),
                float(stats['avg_time']), float(stats['max_time']),
                float(stats['mdev_time']), latency_stats['is_high_latency'], 
                stats['success'], str(latency_stats['concerns'])
            ))

            # logger.log(f"Ping test completed for {self.ip}", "INFO", "PING")
        except Exception as e:
            logger.log(f"Error storing ping results for {self.ip}: {e}", "ERROR", "PING", sys.exc_info())

        conn.commit()

    def ping(self, host: str) -> Dict:
        """
        Ping a host and return comprehensive statistics
        Returns a dictionary with all ping statistics
        """
        count_param = self.os_params['count_param']
        count = str(config['ping_count'])
        
        timeout_param = self.os_params['timeout_param']
        timeout_value = str(config['ping_timeout'])
        if self.os_params['os'] == 'windows':
            timeout_value = str(int(timeout_value) * 1000)
        
        command = ['ping', count_param, count, timeout_param, timeout_value, host]
        
        try:
            output = subprocess.check_output(command, timeout=config['ping_timeout'] + 1).decode('utf-8')
            stats = self._parse_ping_output(output)
            logger.log(f"Ping statistics for {host}: {stats}", "INFO", "PING")
            return stats
        except Exception as e:
            logger.log(f"Error pinging {host}: {e}", "ERROR", "PING", sys.exc_info())
            return {
                'packets_transmitted': 0,
                'packets_received': 0,
                'packets_lost': 0,
                'loss_percentage': 100.0,
                'min_time': 0,
                'avg_time': 0,
                'max_time': 0,
                'mdev_time': 0,
                'success': False
            }

    def _parse_ping_output(self, output: str) -> Dict:
        """
        Parse ping command output and extract all statistics
        Handles both Windows and Unix-like systems
        """
        if self.os_params['os'] == 'windows':
            return self._parse_windows_ping(output)
        else:
            return self._parse_unix_ping(output)

    def _parse_windows_ping(self, output: str) -> Dict:
        """
        Parse Windows ping command output
        """
        stats = {}
        
        # Parse packets sent/received
        for line in output.splitlines():
            if "Packets: Sent =" in line:
                parts = line.split(",")
                stats['packets_transmitted'] = int(parts[0].split("=")[1].strip())
                stats['packets_received'] = int(parts[1].split("=")[1].strip())
                stats['packets_lost'] = stats['packets_transmitted'] - stats['packets_received']
                stats['loss_percentage'] = float(parts[2].split("(")[1].split("%")[0].strip())
                
            if "Minimum =" in line:
                parts = line.split(",")
                stats['min_time'] = float(parts[0].split("=")[1].strip())
                stats['avg_time'] = float(parts[2].split("=")[1].strip())
                stats['max_time'] = float(parts[1].split("=")[1].strip())
                stats['mdev_time'] = None  # Windows doesn't provide standard deviation
        
        stats['success'] = stats.get('packets_received', 0) > 0
        return stats

    def _parse_unix_ping(self, output: str) -> Dict:
        """
        Parse Unix-like ping command output
        """
        stats = {}
        
        # Parse packet statistics
        for line in output.splitlines():
            if "packets transmitted" in line:
                parts = line.split(",")
                stats['packets_transmitted'] = int(parts[0].split()[0])
                stats['packets_received'] = int(parts[1].split()[0])
                stats['loss_percentage'] = float(parts[2].split("%")[0])
                stats['packets_lost'] = stats['packets_transmitted'] - stats['packets_received']
                
            if "min/avg/max/mdev" in line:
                # Format: min/avg/max/mdev = 8.164/8.164/8.164/0.000 ms
                times = line.split("=")[1].strip().split("/")
                stats['min_time'] = float(times[0])
                stats['avg_time'] = float(times[1])
                stats['max_time'] = float(times[2])
                stats['mdev_time'] = float(times[3].split()[0])  # Remove 'ms' unit
        
        stats['success'] = stats.get('packets_received', 0) > 0
        return stats
        
    def analyze_latency(self, ping_stats: Dict) -> Dict:
        """
        Analyze latency and categorize it based on thresholds
        """
        avg_time = ping_stats['avg_time']
        if avg_time is None:
            return {
                'status': 'failed',
                'description': 'No latency data available'
            }
        
        if avg_time <= self.thresholds['excellent']:
            status = 'excellent'
        elif avg_time <= self.thresholds['good']:
            status = 'good'
        elif avg_time <= self.thresholds['fair']:
            status = 'fair'
        elif avg_time <= self.thresholds['poor']:
            status = 'poor'
        else:
            status = 'critical'

        if avg_time > self.thresholds['fair']:
            logger.log(f'{ping_stats["country"]}: High Latency ({avg_time})', 'WARNING', 'LATENCY_ANALYZER')

        result = {
            'status': status,
            'avg_latency': avg_time,
            'is_high_latency': avg_time > self.thresholds['fair'],
            'jitter': ping_stats['mdev_time'],  # Variation in latency
            'packet_loss': ping_stats['loss_percentage']
        }

        # Check for concerning conditions
        concerns = []
        if avg_time > self.thresholds['critical']:
            concerns.append(f'Very high latency: {avg_time}ms')
        if ping_stats['mdev_time'] and ping_stats['mdev_time'] > 50:
            concerns.append(f'High jitter: {ping_stats["mdev_time"]}ms')
        if ping_stats['loss_percentage'] > 1:
            concerns.append(f'Packet loss: {ping_stats["loss_percentage"]}%')

        result['concerns'] = concerns
        return result

def check_alert_conditions(self, stats: Dict) -> List[str]:
    """
    Check if current conditions warrant alerts
    """
    alerts = []
    config = config['alert_conditions']

    if stats['avg_time'] and stats['avg_time'] > config['max_latency']:
        alerts.append(f"High latency detected: {stats['avg_time']}ms (threshold: {config['max_latency']}ms)")
    
    if stats['loss_percentage'] > config['max_packet_loss']:
        alerts.append(f"High packet loss detected: {stats['loss_percentage']}% (threshold: {config['max_packet_loss']}%)")
    
    if stats['mdev_time'] and stats['mdev_time'] > config['max_jitter']:
        alerts.append(f"High jitter detected: {stats['mdev_time']}ms (threshold: {config['max_jitter']}ms)")

    return alerts


if __name__ == "__main__":
    server_instances = [Server(server) for server in config['servers']]
    
    while True:
        for server in server_instances:
            server.run_ping_tests()
        
        time.sleep(60)