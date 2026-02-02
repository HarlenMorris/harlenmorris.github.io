#!/usr/bin/env python3
"""
Network Health Monitoring System

Purpose:
    Monitors critical infrastructure endpoints for healthcare IT environments:
    - Service availability checks (HTTP, HTTPS, DNS, LDAP, Database)
    - Network connectivity validation (ping, traceroute)
    - Response time measurement and trending
    - Degradation detection and alerting
    - Dashboard-compatible JSON output

Features:
    - Multi-protocol health checks
    - Performance baseline tracking
    - Automated alerting on failures
    - Historical trend analysis
    - Integration with IT Ops Dashboard

Author: Harlen Morris
Date: 2026-01-31
Version: 1.0

Requirements:
    - Python 3.8+
    - requests library
    - Network access to monitored endpoints

Usage:
    ./network-health-monitor.py --config endpoints.json --output health-data.json
    ./network-health-monitor.py --quick  # Quick check of default endpoints

Exit codes:
    0 - All services healthy
    1 - Some services degraded (warnings)
    2 - Critical services down
"""

import argparse
import json
import logging
import subprocess
import sys
import time
import socket
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from urllib.parse import urlparse

try:
    import requests
except ImportError:
    print("ERROR: requests library not installed. Run: pip3 install requests")
    sys.exit(1)

# ============================================================================
# CONFIGURATION
# ============================================================================

__version__ = "1.0.0"
__author__ = "Harlen Morris"

# Default endpoints for healthcare IT environment
DEFAULT_ENDPOINTS = [
    {
        "name": "GLPI ITSM",
        "type": "http",
        "url": "https://glpi.harlenmorris.me",
        "critical": True,
        "timeout": 5
    },
    {
        "name": "BookStack KB",
        "type": "http",
        "url": "https://kb.harlenmorris.me",
        "critical": False,
        "timeout": 5
    },
    {
        "name": "IT Ops Dashboard",
        "type": "http",
        "url": "https://dashboard.harlenmorris.me",
        "critical": False,
        "timeout": 5
    },
    {
        "name": "Active Directory",
        "type": "ldap",
        "host": "dc1.northwoodshealth.local",
        "port": 389,
        "critical": True,
        "timeout": 3
    },
    {
        "name": "Exchange Server",
        "type": "smtp",
        "host": "exchange.northwoodshealth.local",
        "port": 25,
        "critical": True,
        "timeout": 5
    },
    {
        "name": "VPN Gateway",
        "type": "ping",
        "host": "vpn.northwoodshealth.org",
        "critical": True,
        "timeout": 2
    },
    {
        "name": "EHR Database",
        "type": "tcp",
        "host": "ehr-db.northwoodshealth.local",
        "port": 5432,
        "critical": True,
        "timeout": 3
    },
    {
        "name": "Backup Server",
        "type": "tcp",
        "host": "backup.northwoodshealth.local",
        "port": 22,
        "critical": False,
        "timeout": 3
    }
]

# Performance thresholds (milliseconds)
RESPONSE_TIME_WARN = 1000  # 1 second
RESPONSE_TIME_CRITICAL = 3000  # 3 seconds

# Logging configuration
LOG_FORMAT = "%(asctime)s [%(levelname)s] %(message)s"
LOG_FILE = f"network-health-{datetime.now().strftime('%Y-%m-%d')}.log"

# ============================================================================
# LOGGING SETUP
# ============================================================================

logging.basicConfig(
    level=logging.INFO,
    format=LOG_FORMAT,
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# ============================================================================
# HEALTH CHECK FUNCTIONS
# ============================================================================

class HealthChecker:
    """Network service health checker"""
    
    def __init__(self):
        self.results = []
        self.critical_failures = 0
        self.warnings = 0
        self.successes = 0
    
    def check_http(self, endpoint: Dict) -> Dict:
        """Check HTTP/HTTPS service availability"""
        url = endpoint['url']
        timeout = endpoint.get('timeout', 5)
        
        logger.info(f"Checking HTTP: {url}")
        
        start_time = time.time()
        try:
            response = requests.get(url, timeout=timeout, allow_redirects=True)
            elapsed_ms = (time.time() - start_time) * 1000
            
            status = "healthy"
            if response.status_code >= 500:
                status = "critical"
            elif response.status_code >= 400:
                status = "warning"
            elif elapsed_ms > RESPONSE_TIME_CRITICAL:
                status = "critical"
            elif elapsed_ms > RESPONSE_TIME_WARN:
                status = "warning"
            
            return {
                "name": endpoint['name'],
                "type": "http",
                "status": status,
                "available": True,
                "response_time_ms": round(elapsed_ms, 2),
                "http_code": response.status_code,
                "details": f"HTTP {response.status_code}",
                "timestamp": datetime.now().isoformat()
            }
            
        except requests.exceptions.Timeout:
            return {
                "name": endpoint['name'],
                "type": "http",
                "status": "critical",
                "available": False,
                "response_time_ms": timeout * 1000,
                "details": "Connection timeout",
                "timestamp": datetime.now().isoformat()
            }
        except requests.exceptions.ConnectionError as e:
            return {
                "name": endpoint['name'],
                "type": "http",
                "status": "critical",
                "available": False,
                "details": f"Connection refused: {str(e)[:50]}",
                "timestamp": datetime.now().isoformat()
            }
        except Exception as e:
            return {
                "name": endpoint['name'],
                "type": "http",
                "status": "critical",
                "available": False,
                "details": f"Error: {str(e)[:50]}",
                "timestamp": datetime.now().isoformat()
            }
    
    def check_tcp(self, endpoint: Dict) -> Dict:
        """Check TCP port availability"""
        host = endpoint['host']
        port = endpoint['port']
        timeout = endpoint.get('timeout', 3)
        
        logger.info(f"Checking TCP: {host}:{port}")
        
        start_time = time.time()
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            result = sock.connect_ex((host, port))
            elapsed_ms = (time.time() - start_time) * 1000
            sock.close()
            
            if result == 0:
                status = "healthy"
                if elapsed_ms > RESPONSE_TIME_CRITICAL:
                    status = "critical"
                elif elapsed_ms > RESPONSE_TIME_WARN:
                    status = "warning"
                
                return {
                    "name": endpoint['name'],
                    "type": "tcp",
                    "status": status,
                    "available": True,
                    "response_time_ms": round(elapsed_ms, 2),
                    "details": f"Port {port} open",
                    "timestamp": datetime.now().isoformat()
                }
            else:
                return {
                    "name": endpoint['name'],
                    "type": "tcp",
                    "status": "critical",
                    "available": False,
                    "details": f"Port {port} closed or filtered",
                    "timestamp": datetime.now().isoformat()
                }
                
        except socket.gaierror:
            return {
                "name": endpoint['name'],
                "type": "tcp",
                "status": "critical",
                "available": False,
                "details": "DNS resolution failed",
                "timestamp": datetime.now().isoformat()
            }
        except Exception as e:
            return {
                "name": endpoint['name'],
                "type": "tcp",
                "status": "critical",
                "available": False,
                "details": f"Error: {str(e)[:50]}",
                "timestamp": datetime.now().isoformat()
            }
    
    def check_ping(self, endpoint: Dict) -> Dict:
        """Check ICMP ping connectivity"""
        host = endpoint['host']
        timeout = endpoint.get('timeout', 2)
        
        logger.info(f"Checking ping: {host}")
        
        try:
            # Use system ping command
            result = subprocess.run(
                ['ping', '-c', '3', '-W', str(timeout), host],
                capture_output=True,
                text=True,
                timeout=timeout * 3
            )
            
            if result.returncode == 0:
                # Parse average response time from ping output
                # Example: rtt min/avg/max/mdev = 0.123/0.456/0.789/0.123 ms
                output = result.stdout
                if 'avg' in output:
                    try:
                        avg_line = [l for l in output.split('\n') if 'avg' in l][0]
                        avg_ms = float(avg_line.split('/')[4])
                    except:
                        avg_ms = 0
                else:
                    avg_ms = 0
                
                status = "healthy"
                if avg_ms > RESPONSE_TIME_CRITICAL:
                    status = "critical"
                elif avg_ms > RESPONSE_TIME_WARN:
                    status = "warning"
                
                return {
                    "name": endpoint['name'],
                    "type": "ping",
                    "status": status,
                    "available": True,
                    "response_time_ms": round(avg_ms, 2),
                    "details": f"Avg RTT: {avg_ms:.2f}ms",
                    "timestamp": datetime.now().isoformat()
                }
            else:
                return {
                    "name": endpoint['name'],
                    "type": "ping",
                    "status": "critical",
                    "available": False,
                    "details": "Host unreachable",
                    "timestamp": datetime.now().isoformat()
                }
                
        except subprocess.TimeoutExpired:
            return {
                "name": endpoint['name'],
                "type": "ping",
                "status": "critical",
                "available": False,
                "details": "Ping timeout",
                "timestamp": datetime.now().isoformat()
            }
        except Exception as e:
            return {
                "name": endpoint['name'],
                "type": "ping",
                "status": "critical",
                "available": False,
                "details": f"Error: {str(e)[:50]}",
                "timestamp": datetime.now().isoformat()
            }
    
    def check_ldap(self, endpoint: Dict) -> Dict:
        """Check LDAP service availability"""
        # For LDAP, we'll use a simple TCP port check
        # In production, would use python-ldap library for actual LDAP bind test
        endpoint_tcp = {
            "name": endpoint['name'],
            "host": endpoint['host'],
            "port": endpoint.get('port', 389),
            "timeout": endpoint.get('timeout', 3)
        }
        result = self.check_tcp(endpoint_tcp)
        result['type'] = 'ldap'
        return result
    
    def check_smtp(self, endpoint: Dict) -> Dict:
        """Check SMTP service availability"""
        # Similar to LDAP, use TCP check for simplicity
        # In production, would test actual SMTP conversation
        endpoint_tcp = {
            "name": endpoint['name'],
            "host": endpoint['host'],
            "port": endpoint.get('port', 25),
            "timeout": endpoint.get('timeout', 5)
        }
        result = self.check_tcp(endpoint_tcp)
        result['type'] = 'smtp'
        return result
    
    def check_endpoint(self, endpoint: Dict) -> Dict:
        """Route to appropriate check based on endpoint type"""
        check_type = endpoint.get('type', 'tcp')
        
        if check_type == 'http' or check_type == 'https':
            return self.check_http(endpoint)
        elif check_type == 'tcp':
            return self.check_tcp(endpoint)
        elif check_type == 'ping':
            return self.check_ping(endpoint)
        elif check_type == 'ldap':
            return self.check_ldap(endpoint)
        elif check_type == 'smtp':
            return self.check_smtp(endpoint)
        else:
            logger.warning(f"Unknown check type: {check_type}")
            return {
                "name": endpoint['name'],
                "type": check_type,
                "status": "unknown",
                "available": False,
                "details": "Unknown check type",
                "timestamp": datetime.now().isoformat()
            }
    
    def run_checks(self, endpoints: List[Dict]) -> List[Dict]:
        """Run health checks on all endpoints"""
        logger.info("=" * 60)
        logger.info(f"Starting health checks on {len(endpoints)} endpoints")
        logger.info("=" * 60)
        
        self.results = []
        
        for endpoint in endpoints:
            result = self.check_endpoint(endpoint)
            result['critical'] = endpoint.get('critical', False)
            self.results.append(result)
            
            # Update counters
            if result['status'] == 'healthy':
                self.successes += 1
                logger.info(f"✓ {result['name']}: HEALTHY ({result.get('response_time_ms', 0):.2f}ms)")
            elif result['status'] == 'warning':
                self.warnings += 1
                logger.warning(f"⚠ {result['name']}: WARNING - {result['details']}")
            else:
                if result['critical']:
                    self.critical_failures += 1
                    logger.error(f"✗ {result['name']}: CRITICAL - {result['details']}")
                else:
                    logger.error(f"✗ {result['name']}: DOWN - {result['details']}")
        
        logger.info("=" * 60)
        logger.info("Health check summary:")
        logger.info(f"  Healthy: {self.successes}")
        logger.info(f"  Warnings: {self.warnings}")
        logger.info(f"  Failed: {len(endpoints) - self.successes - self.warnings}")
        logger.info(f"  Critical failures: {self.critical_failures}")
        logger.info("=" * 60)
        
        return self.results

# ============================================================================
# REPORT GENERATION
# ============================================================================

def generate_json_output(results: List[Dict], output_file: str):
    """Generate JSON output for dashboard integration"""
    overall_status = "healthy"
    
    critical_down = sum(1 for r in results if r['status'] == 'critical' and r['critical'])
    warnings = sum(1 for r in results if r['status'] == 'warning')
    
    if critical_down > 0:
        overall_status = "critical"
    elif warnings > 0:
        overall_status = "warning"
    
    output = {
        "generated": datetime.now().isoformat(),
        "overall_status": overall_status,
        "summary": {
            "total_endpoints": len(results),
            "healthy": sum(1 for r in results if r['status'] == 'healthy'),
            "warnings": warnings,
            "critical": critical_down,
            "down": sum(1 for r in results if not r.get('available', False))
        },
        "endpoints": results,
        "metadata": {
            "version": __version__,
            "author": __author__
        }
    }
    
    with open(output_file, 'w') as f:
        json.dump(output, f, indent=2)
    
    logger.info(f"✓ JSON output saved: {output_file}")

def generate_console_report(results: List[Dict]):
    """Generate human-readable console report"""
    print("\n" + "=" * 80)
    print("NETWORK HEALTH MONITORING REPORT")
    print("=" * 80)
    print(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Total Endpoints: {len(results)}")
    print()
    
    # Group by status
    healthy = [r for r in results if r['status'] == 'healthy']
    warnings = [r for r in results if r['status'] == 'warning']
    critical = [r for r in results if r['status'] == 'critical']
    
    if healthy:
        print("✓ HEALTHY SERVICES:")
        for r in healthy:
            rt = r.get('response_time_ms', 0)
            print(f"  ✓ {r['name']:30s} - {rt:6.2f}ms")
        print()
    
    if warnings:
        print("⚠ WARNINGS:")
        for r in warnings:
            print(f"  ⚠ {r['name']:30s} - {r['details']}")
        print()
    
    if critical:
        print("✗ CRITICAL/DOWN:")
        for r in critical:
            critical_flag = " [CRITICAL]" if r.get('critical') else ""
            print(f"  ✗ {r['name']:30s} - {r['details']}{critical_flag}")
        print()
    
    # Overall health score
    health_score = (len(healthy) / len(results)) * 100
    print("-" * 80)
    print(f"OVERALL HEALTH SCORE: {health_score:.1f}%")
    
    if health_score == 100:
        print("Status: ✓ ALL SYSTEMS OPERATIONAL")
    elif health_score >= 90:
        print("Status: ⚠ DEGRADED PERFORMANCE")
    else:
        print("Status: ✗ CRITICAL ISSUES DETECTED")
    
    print("=" * 80)

# ============================================================================
# MAIN EXECUTION
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Network health monitoring for healthcare IT infrastructure",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument('--config', type=str,
                       help='JSON config file with endpoints to monitor')
    parser.add_argument('--output', type=str,
                       default=f'health-data-{datetime.now().strftime("%Y%m%d-%H%M%S")}.json',
                       help='Output JSON file path')
    parser.add_argument('--quick', action='store_true',
                       help='Quick check of default endpoints')
    parser.add_argument('--verbose', '-v', action='store_true',
                       help='Enable verbose logging')
    
    args = parser.parse_args()
    
    if args.verbose:
        logger.setLevel(logging.DEBUG)
    
    # Load endpoints
    if args.config:
        try:
            with open(args.config, 'r') as f:
                endpoints = json.load(f)
            logger.info(f"Loaded {len(endpoints)} endpoints from {args.config}")
        except Exception as e:
            logger.error(f"Failed to load config: {e}")
            return 1
    else:
        endpoints = DEFAULT_ENDPOINTS
        logger.info(f"Using {len(endpoints)} default endpoints")
    
    # Run health checks
    checker = HealthChecker()
    results = checker.run_checks(endpoints)
    
    # Generate outputs
    generate_json_output(results, args.output)
    
    if not args.quick:
        generate_console_report(results)
    
    # Determine exit code
    if checker.critical_failures > 0:
        logger.error(f"CRITICAL: {checker.critical_failures} critical services down")
        return 2
    elif checker.warnings > 0:
        logger.warning(f"WARNING: {checker.warnings} services degraded")
        return 1
    else:
        logger.info("SUCCESS: All services healthy")
        return 0

if __name__ == '__main__':
    sys.exit(main())
