"""
Mock Cloud Billing API (stdlib only, no dependencies).

Previously this service was started as `python -m http.server --directory /app`,
which only serves static files. index.html *described* /health and
/billing/costs endpoints with "Try it" links, but neither route actually
existed, so both 404'd. This server implements them for real, and still
serves the dashboard at "/".
"""
import http.server
import json
import os
import socketserver

PORT = 9091
DASHBOARD_PATH = os.path.join(os.path.dirname(__file__), "index.html")

BILLING_RESPONSE = {
    "ResultsByTime": [{
        "TimePeriod": {"Start": "2026-07-04", "End": "2026-07-11"},
        "Total": {"UnblendedCost": {"Amount": "124.58", "Unit": "USD"}},
        "Groups": [
            {"Keys": ["team$frontend"], "Amount": "71.40"},
            {"Keys": ["team$data"], "Amount": "53.18"},
        ],
    }]
}


class Handler(http.server.BaseHTTPRequestHandler):
    def _send_json(self, payload, status=200):
        body = json.dumps(payload, indent=2).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._send_json({"status": "ok"})
            return

        if self.path == "/billing/costs":
            self._send_json(BILLING_RESPONSE)
            return

        if self.path in ("/", "/index.html"):
            with open(DASHBOARD_PATH, "rb") as f:
                body = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        self.send_response(404)
        self.end_headers()

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    print(f"Mock Cloud Billing API running on :{PORT}")
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        httpd.serve_forever()
