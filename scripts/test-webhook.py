#!/usr/bin/env python3
"""
Local webhook receiver for testing Alertmanager notifications.
Listens on localhost:5001, prints all incoming alert payloads.

Usage:
    python3 scripts/test-webhook.py

Then in your alertmanager.yml:
    url: 'http://127.0.0.1:5001/'
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
from datetime import datetime

PORT = 5001

class AlertHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length)

        print(f"\n{'='*60}")
        print(f"Alert received at {datetime.now().strftime('%H:%M:%S')}")
        print('='*60)

        try:
            payload = json.loads(body)
            print(f"Status   : {payload.get('status', 'unknown').upper()}")
            print(f"Receiver : {payload.get('receiver', 'unknown')}")
            print(f"Alerts   : {len(payload.get('alerts', []))}")
            print()
            for i, alert in enumerate(payload.get('alerts', []), 1):
                labels = alert.get('labels', {})
                annotations = alert.get('annotations', {})
                print(f"  [{i}] {labels.get('alertname', 'unknown')}")
                print(f"      Severity : {labels.get('severity', '-')}")
                print(f"      Cluster  : {labels.get('cluster', '-')}")
                print(f"      Status   : {alert.get('status', '-')}")
                print(f"      Summary  : {annotations.get('summary', '-')}")
                print()
            print("Full payload:")
            print(json.dumps(payload, indent=2))
        except Exception:
            print("Raw body:")
            print(body.decode())

        self.send_response(200)
        self.end_headers()

    def log_message(self, format, *args):
        pass  # suppress default access log

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', PORT), AlertHandler)
    print(f"Webhook receiver listening on http://127.0.0.1:{PORT}")
    print("Waiting for alerts from Alertmanager...")
    print("Press Ctrl+C to stop\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
