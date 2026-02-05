#!/usr/bin/env python3
"""
Ticket Report Generator (GLPI)

Purpose:
    Connects to a GLPI ticketing system and generates a weekly report
    for MSP/healthcare operations teams. The report includes:
      - Weekly ticket summary (opened, closed, pending, SLA compliance)
      - Technician performance metrics
      - Client satisfaction trends
      - HTML executive report + CSV export for BI tools

Features:
    - Read-only GLPI REST API integration
    - HIPAA-conscious reporting (no patient identifiers)
    - Strong error handling and audit-friendly logging
    - Output suitable for MSP status meetings and QBRs

Author: Harlen Morris
Date: 2026-02-05
Version: 1.0

Requirements:
    - Python 3.8+
    - requests library
    - GLPI REST API access (read-only is sufficient)

Usage:
    ./ticket-report-generator.py --url https://glpi.example.com/apirest.php --username guest --password guest
    ./ticket-report-generator.py --config glpi-config.json --output-dir ./reports
    ./ticket-report-generator.py --start 2026-02-01 --end 2026-02-07

Exit codes:
    0 - Report generated successfully
    1 - API connection or authentication error
    2 - Report generation failure

Sample Output:
    2026-02-05 15:10:12 [INFO] Ticket Report Generator v1.0.0
    2026-02-05 15:10:12 [INFO] ✓ GLPI session initialized successfully
    2026-02-05 15:10:13 [INFO] ✓ Tickets retrieved: 56
    2026-02-05 15:10:13 [INFO] ✓ Report generated: ticket-report-2026-02-05.html
    2026-02-05 15:10:13 [INFO] ✓ CSV export saved: ticket-report-2026-02-05.csv
"""

import argparse
import csv
import json
import logging
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Any

import requests

# ============================================================================
# CONFIGURATION
# ============================================================================

__version__ = "1.0.0"
__author__ = "Harlen Morris"

DEFAULT_GLPI_URL = "https://glpi.harlenmorris.me/apirest.php"
DEFAULT_USERNAME = "guest"
DEFAULT_PASSWORD = "guest"

LOG_FORMAT = "%(asctime)s [%(levelname)s] %(message)s"
LOG_FILE = f"ticket-report-{datetime.now().strftime('%Y-%m-%d')}.log"

STATUS_MAP = {
    1: "New",
    2: "Assigned",
    3: "Planned",
    4: "Pending",
    5: "Solved",
    6: "Closed"
}

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
# GLPI API CLIENT
# ============================================================================

class GLPIClient:
    """GLPI REST API client with session management"""

    def __init__(self, base_url: str, username: str, password: str):
        self.base_url = base_url.rstrip('/')
        self.username = username
        self.password = password
        self.session_token = None
        self.session = requests.Session()

    def init_session(self) -> bool:
        """Initialize GLPI API session"""
        try:
            response = self.session.get(
                f"{self.base_url}/initSession",
                auth=(self.username, self.password),
                headers={'Content-Type': 'application/json'}
            )

            if response.status_code == 200:
                data = response.json()
                self.session_token = data.get('session_token')
                logger.info("✓ GLPI session initialized successfully")
                return True

            logger.error(f"Session init failed: {response.status_code} - {response.text}")
            return False

        except requests.RequestException as exc:
            logger.error(f"Failed to connect to GLPI: {exc}")
            return False

    def get(self, endpoint: str, params: Optional[Dict] = None) -> Optional[Any]:
        """Make GET request to GLPI API"""
        if not self.session_token:
            logger.error("No active session - call init_session() first")
            return None

        try:
            url = f"{self.base_url}/{endpoint}"
            headers = {
                'Session-Token': self.session_token,
                'Content-Type': 'application/json'
            }

            response = self.session.get(url, headers=headers, params=params)

            if response.status_code == 200:
                return response.json()

            logger.warning(f"GET {endpoint} returned {response.status_code}")
            return None

        except requests.RequestException as exc:
            logger.error(f"API request failed: {exc}")
            return None

    def kill_session(self):
        """Close GLPI API session"""
        if self.session_token:
            try:
                self.session.get(
                    f"{self.base_url}/killSession",
                    headers={'Session-Token': self.session_token}
                )
            except requests.RequestException:
                pass

# ============================================================================
# DATA COLLECTION
# ============================================================================

def fetch_tickets(client: GLPIClient) -> List[Dict]:
    """Fetch ticket list from GLPI"""
    logger.info("Fetching ticket data...")
    tickets = client.get("Ticket", params={"range": "0-999"})
    return tickets if tickets else []


def fetch_user_name(client: GLPIClient, user_id: Optional[int], cache: Dict[int, str]) -> str:
    """Lookup user name by ID with caching"""
    if not user_id:
        return "Unassigned"
    if user_id in cache:
        return cache[user_id]

    user = client.get(f"User/{user_id}")
    if isinstance(user, dict):
        name = user.get("realname") or user.get("name") or f"User {user_id}"
        cache[user_id] = name
        return name

    return f"User {user_id}"

# ============================================================================
# ANALYSIS FUNCTIONS
# ============================================================================

def parse_date(date_value: Optional[str]) -> Optional[datetime]:
    if not date_value:
        return None
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(date_value, fmt)
        except ValueError:
            continue
    return None


def is_within_range(date_value: Optional[datetime], start: datetime, end: datetime) -> bool:
    return bool(date_value and start <= date_value <= end)


def calculate_sla_compliance(tickets: List[Dict], end: datetime) -> Dict[str, int]:
    """Calculate SLA compliance based on due date vs solved date"""
    compliant = 0
    non_compliant = 0
    unknown = 0

    for ticket in tickets:
        due_date = parse_date(ticket.get("due_date"))
        solved_date = parse_date(ticket.get("solvedate"))

        if due_date and solved_date:
            if solved_date <= due_date:
                compliant += 1
            else:
                non_compliant += 1
        elif due_date and ticket.get("status") in (1, 2, 3, 4):
            # Open ticket - compare with current end date
            if end <= due_date:
                compliant += 1
            else:
                non_compliant += 1
        else:
            unknown += 1

    total = compliant + non_compliant + unknown
    compliance_rate = round((compliant / total) * 100, 2) if total else 0

    return {
        "compliant": compliant,
        "non_compliant": non_compliant,
        "unknown": unknown,
        "rate": compliance_rate
    }


def build_technician_metrics(tickets: List[Dict], client: GLPIClient) -> List[Dict]:
    """Aggregate ticket metrics per technician"""
    tech_cache: Dict[int, str] = {}
    metrics: Dict[str, Dict[str, float]] = {}

    for ticket in tickets:
        technician_id = ticket.get("users_id_assign")
        technician = fetch_user_name(client, technician_id, tech_cache)
        metrics.setdefault(technician, {"total": 0, "resolved": 0, "resolution_hours": []})

        metrics[technician]["total"] += 1

        if ticket.get("status") in (5, 6):
            metrics[technician]["resolved"] += 1
            opened = parse_date(ticket.get("date"))
            solved = parse_date(ticket.get("solvedate"))
            if opened and solved:
                delta = (solved - opened).total_seconds() / 3600
                metrics[technician]["resolution_hours"].append(delta)

    results = []
    for technician, data in metrics.items():
        avg_resolution = (
            round(sum(data["resolution_hours"]) / len(data["resolution_hours"]), 2)
            if data["resolution_hours"]
            else 0
        )
        results.append({
            "technician": technician,
            "total": int(data["total"]),
            "resolved": int(data["resolved"]),
            "avg_resolution_hours": avg_resolution
        })

    return sorted(results, key=lambda item: item["resolved"], reverse=True)


def build_satisfaction_trends(tickets: List[Dict]) -> Dict[str, Any]:
    """Analyze satisfaction ratings if available"""
    ratings = []
    for ticket in tickets:
        rating = ticket.get("satisfaction")
        if isinstance(rating, (int, float)) and rating > 0:
            ratings.append(rating)

    if not ratings:
        return {
            "count": 0,
            "average": 0,
            "trend": "No surveys completed this period",
            "distribution": {}
        }

    average = round(sum(ratings) / len(ratings), 2)
    distribution = {str(score): ratings.count(score) for score in sorted(set(ratings))}

    return {
        "count": len(ratings),
        "average": average,
        "trend": "Positive" if average >= 4 else "Needs Attention",
        "distribution": distribution
    }

# ============================================================================
# REPORT GENERATION
# ============================================================================

def generate_html_report(
    start: datetime,
    end: datetime,
    summary: Dict[str, Any],
    sla: Dict[str, Any],
    technicians: List[Dict],
    satisfaction: Dict[str, Any],
    output_path: Path
) -> None:
    """Generate HTML report for management"""

    html = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Weekly Ticket Report</title>
    <style>
        body {{ font-family: 'Segoe UI', Tahoma, sans-serif; background: #f5f7fb; margin: 0; padding: 0; }}
        .container {{ max-width: 1100px; margin: 30px auto; background: white; padding: 30px; border-radius: 8px; }}
        h1 {{ color: #1f3b6d; margin-bottom: 0; }}
        h2 {{ color: #1f3b6d; margin-top: 30px; }}
        .subtitle {{ color: #5b6b80; margin-top: 5px; }}
        .summary-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-top: 20px; }}
        .summary-card {{ background: #f0f4ff; padding: 15px; border-radius: 8px; }}
        .summary-card h3 {{ margin: 0; font-size: 1rem; color: #2c3e50; }}
        .summary-card p {{ margin: 5px 0 0; font-size: 1.6rem; font-weight: 700; color: #1f3b6d; }}
        table {{ width: 100%; border-collapse: collapse; margin-top: 15px; }}
        th, td {{ border-bottom: 1px solid #e0e6ed; text-align: left; padding: 10px; }}
        th {{ background: #f8f9fb; }}
        .badge {{ display: inline-block; padding: 4px 10px; border-radius: 12px; font-size: 0.85rem; }}
        .badge-good {{ background: #e6f4ea; color: #1e7e34; }}
        .badge-warn {{ background: #fff4e5; color: #ad5e00; }}
        .badge-bad {{ background: #fdecea; color: #b02a37; }}
        .note {{ margin-top: 25px; font-size: 0.9rem; color: #6c7a89; }}
    </style>
</head>
<body>
    <div class="container">
        <h1>Weekly Ticket Operations Report</h1>
        <div class="subtitle">Northwoods Health System | {start.strftime('%b %d, %Y')} – {end.strftime('%b %d, %Y')}</div>

        <h2>Executive Summary</h2>
        <div class="summary-grid">
            <div class="summary-card">
                <h3>Tickets Opened</h3>
                <p>{summary['opened']}</p>
            </div>
            <div class="summary-card">
                <h3>Tickets Closed</h3>
                <p>{summary['closed']}</p>
            </div>
            <div class="summary-card">
                <h3>Pending</h3>
                <p>{summary['pending']}</p>
            </div>
            <div class="summary-card">
                <h3>SLA Compliance</h3>
                <p>{sla['rate']}%</p>
            </div>
        </div>

        <h2>SLA Compliance</h2>
        <table>
            <tr><th>Compliant</th><th>Non-Compliant</th><th>Unknown</th></tr>
            <tr>
                <td>{sla['compliant']}</td>
                <td>{sla['non_compliant']}</td>
                <td>{sla['unknown']}</td>
            </tr>
        </table>

        <h2>Technician Performance</h2>
        <table>
            <tr><th>Technician</th><th>Total Tickets</th><th>Resolved</th><th>Avg Resolution (hrs)</th></tr>
            {''.join([f"<tr><td>{t['technician']}</td><td>{t['total']}</td><td>{t['resolved']}</td><td>{t['avg_resolution_hours']}</td></tr>" for t in technicians])}
        </table>

        <h2>Client Satisfaction</h2>
        <table>
            <tr><th>Surveys Completed</th><th>Average Score (1-5)</th><th>Trend</th></tr>
            <tr>
                <td>{satisfaction['count']}</td>
                <td>{satisfaction['average']}</td>
                <td>{satisfaction['trend']}</td>
            </tr>
        </table>

        <p class="note">
            Note: Report excludes patient-identifying data to maintain HIPAA confidentiality.\
            SLA compliance is based on GLPI due dates and resolution timestamps.
        </p>
    </div>
</body>
</html>
"""

    output_path.write_text(html, encoding="utf-8")


def write_csv_report(tickets: List[Dict], output_path: Path, client: GLPIClient) -> None:
    """Export ticket data to CSV"""
    tech_cache: Dict[int, str] = {}

    with output_path.open("w", newline="", encoding="utf-8") as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow([
            "Ticket ID",
            "Title",
            "Status",
            "Opened",
            "Closed",
            "Assigned Technician",
            "SLA Due Date"
        ])

        for ticket in tickets:
            status = STATUS_MAP.get(ticket.get("status"), "Unknown")
            tech_name = fetch_user_name(client, ticket.get("users_id_assign"), tech_cache)
            writer.writerow([
                ticket.get("id"),
                ticket.get("name"),
                status,
                ticket.get("date"),
                ticket.get("closedate") or ticket.get("solvedate"),
                tech_name,
                ticket.get("due_date")
            ])

# ============================================================================
# MAIN
# ============================================================================

def load_config(path: Optional[str]) -> Dict[str, str]:
    if not path:
        return {}

    config_path = Path(path)
    if not config_path.exists():
        raise FileNotFoundError(f"Config file not found: {path}")

    return json.loads(config_path.read_text(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate weekly GLPI ticket reports")
    parser.add_argument("--url", default=DEFAULT_GLPI_URL, help="GLPI API base URL")
    parser.add_argument("--username", default=DEFAULT_USERNAME, help="GLPI username")
    parser.add_argument("--password", default=DEFAULT_PASSWORD, help="GLPI password")
    parser.add_argument("--config", help="JSON config file with URL and credentials")
    parser.add_argument("--start", help="Report start date (YYYY-MM-DD)")
    parser.add_argument("--end", help="Report end date (YYYY-MM-DD)")
    parser.add_argument("--output-dir", default=".", help="Directory to write reports")

    args = parser.parse_args()

    try:
        config = load_config(args.config)
    except Exception as exc:
        logger.error(f"Failed to load config: {exc}")
        return 1

    url = config.get("url", args.url)
    username = config.get("username", args.username)
    password = config.get("password", args.password)

    end = datetime.strptime(args.end, "%Y-%m-%d") if args.end else datetime.now()
    start = datetime.strptime(args.start, "%Y-%m-%d") if args.start else end - timedelta(days=7)

    logger.info(f"Ticket Report Generator v{__version__}")
    logger.info(f"Report range: {start.strftime('%Y-%m-%d')} to {end.strftime('%Y-%m-%d')}")

    client = GLPIClient(url, username, password)
    if not client.init_session():
        return 1

    try:
        tickets = fetch_tickets(client)
        logger.info(f"✓ Tickets retrieved: {len(tickets)}")

        # Filter tickets within range based on creation date
        weekly_tickets = [
            ticket for ticket in tickets
            if is_within_range(parse_date(ticket.get("date")), start, end)
        ]

        summary = {
            "opened": len(weekly_tickets),
            "closed": len([
                t for t in tickets
                if is_within_range(parse_date(t.get("closedate") or t.get("solvedate")), start, end)
            ]),
            "pending": len([t for t in tickets if t.get("status") == 4])
        }

        sla = calculate_sla_compliance(weekly_tickets, end)
        technicians = build_technician_metrics(weekly_tickets, client)
        satisfaction = build_satisfaction_trends(weekly_tickets)

        output_dir = Path(args.output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        html_path = output_dir / f"ticket-report-{end.strftime('%Y-%m-%d')}.html"
        csv_path = output_dir / f"ticket-report-{end.strftime('%Y-%m-%d')}.csv"

        generate_html_report(start, end, summary, sla, technicians, satisfaction, html_path)
        write_csv_report(weekly_tickets, csv_path, client)

        logger.info(f"✓ Report generated: {html_path}")
        logger.info(f"✓ CSV export saved: {csv_path}")

    except Exception as exc:
        logger.error(f"Report generation failed: {exc}")
        return 2
    finally:
        client.kill_session()

    return 0


if __name__ == "__main__":
    sys.exit(main())
