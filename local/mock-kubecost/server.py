"""
Mock Kubecost API (stdlib only, no dependencies).

Implements a trimmed-down /model/allocation endpoint that matches the
*real* Kubecost Allocation API response shape closely enough for
scripts/generate-report.sh to parse: cpuCost, ramCost, pvCost,
networkCost, loadBalancerCost, sharedCost, totalCost, cpuEfficiency,
ramEfficiency, and a `start` timestamp per team, per day.

Previously this file only returned a single hardcoded, incomplete
record for the "frontend" team (no "data" team, no cost breakdown
fields), which made scripts/generate-report.sh silently produce a
report with $0.00 line items. This version fixes that.
"""
import http.server
import json
import math
import socketserver
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse, parse_qs

PORT = 9090

TEAMS = {
    "frontend": {"cpu": 3.20, "ram": 1.80, "cpu_eff": 0.08, "ram_eff": 0.12},
    "data": {"cpu": 1.50, "ram": 0.90, "cpu_eff": 0.10, "ram_eff": 0.15},
}


def window(days_ago_start, days_ago_end):
    now = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    start = now - timedelta(days=days_ago_start)
    end = now - timedelta(days=days_ago_end)
    return start.strftime("%Y-%m-%dT%H:%M:%SZ"), end.strftime("%Y-%m-%dT%H:%M:%SZ")


def daily_allocation(team, day_offset):
    cfg = TEAMS[team]
    factor = 1 + 0.05 * math.sin(day_offset * 1.3)
    cpu_cost = round(cfg["cpu"] * factor, 4)
    ram_cost = round(cfg["ram"] * factor, 4)
    pv_cost = 0.10
    network_cost = 0.05
    lb_cost = 0.25 if team == "frontend" else 0.0
    shared_cost = round(0.30 * factor, 4)
    total = round(cpu_cost + ram_cost + pv_cost + network_cost + lb_cost + shared_cost, 4)
    start, end = window(day_offset + 1, day_offset)
    return {
        "name": team,
        "start": start,
        "end": end,
        "cpuCost": cpu_cost,
        "ramCost": ram_cost,
        "pvCost": pv_cost,
        "networkCost": network_cost,
        "loadBalancerCost": lb_cost,
        "sharedCost": shared_cost,
        "totalCost": total,
        "cpuEfficiency": cfg["cpu_eff"],
        "ramEfficiency": cfg["ram_eff"],
        "properties": {"cluster": "finops-platform", "labels": {"team": team}},
    }


def build_allocation_payload(window_param, accumulate):
    days = 30 if "30" in window_param else 1 if "yesterday" in window_param else 7

    if accumulate:
        agg = {}
        for team in TEAMS:
            entries = [daily_allocation(team, d) for d in range(days)]
            start, _ = window(days, 0)
            _, end = window(0, 0)
            agg[team] = {
                "name": team,
                "start": start,
                "end": end,
                "cpuCost": round(sum(e["cpuCost"] for e in entries), 4),
                "ramCost": round(sum(e["ramCost"] for e in entries), 4),
                "pvCost": round(sum(e["pvCost"] for e in entries), 4),
                "networkCost": round(sum(e["networkCost"] for e in entries), 4),
                "loadBalancerCost": round(sum(e["loadBalancerCost"] for e in entries), 4),
                "sharedCost": round(sum(e["sharedCost"] for e in entries), 4),
                "totalCost": round(sum(e["totalCost"] for e in entries), 4),
                "cpuEfficiency": round(sum(e["cpuEfficiency"] for e in entries) / days, 4),
                "ramEfficiency": round(sum(e["ramEfficiency"] for e in entries) / days, 4),
                "properties": entries[0]["properties"],
            }
        return {"code": 200, "data": [agg]}

    daily_data = []
    for day in range(days):
        daily_data.append({team: daily_allocation(team, day) for team in TEAMS})
    return {"code": 200, "data": daily_data}


class Handler(http.server.BaseHTTPRequestHandler):
    def _send_json(self, payload, status=200):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path in ("/healthz", "/health"):
            self._send_json({"status": "ok", "service": "mock-kubecost"})
            return

        if parsed.path == "/model/allocation":
            q = parse_qs(parsed.query)
            window_param = q.get("window", ["last7days"])[0]
            accumulate = q.get("accumulate", ["false"])[0].lower() == "true"
            fmt = q.get("format", ["json"])[0]
            payload = build_allocation_payload(window_param, accumulate)

            if fmt == "csv":
                rows = ["team,start,cpuCost,ramCost,pvCost,networkCost,loadBalancerCost,sharedCost,totalCost"]
                for day_entry in payload["data"]:
                    for team, v in day_entry.items():
                        rows.append(",".join(str(x) for x in [
                            team, v["start"][:10], v["cpuCost"], v["ramCost"], v["pvCost"],
                            v["networkCost"], v["loadBalancerCost"], v["sharedCost"], v["totalCost"],
                        ]))
                body = ("\n".join(rows) + "\n").encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/csv")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return

            self._send_json(payload)
            return

        if parsed.path == "/":
            self._send_json({"service": "mock-kubecost", "version": "1.108.0-mock"})
            return

        self.send_response(404)
        self.end_headers()

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    print(f"Mock Kubecost API running on :{PORT}")
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        httpd.serve_forever()
