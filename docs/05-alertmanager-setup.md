# 05 — Alertmanager Setup

Alertmanager receives firing alerts from Prometheus and handles routing,
grouping, deduplication, and delivery to notification receivers.

---

## Prerequisites

- Alertmanager and amtool installed ([01 — Prerequisites](01-prerequisites.md))
- Prometheus running and connected ([03 — Prometheus Setup](03-prometheus-setup.md))
- At least one alert rule loaded ([04 — Alert Rules](04-alert-rules.md))

---

## What Alertmanager Does

Prometheus decides **when** to fire an alert.  
Alertmanager decides **where** to send it and **how**.

```
┌─────────────────┐      ┌──────────────────┐      ┌──────────────┐
│   Prometheus    │      │  Alertmanager    │      │   Receiver   │
├─────────────────┤      ├──────────────────┤      ├──────────────┤
│ • Evaluates     │      │ • Groups related │      │ • Slack      │
│   rules         │      │   alerts         │      │ • Email      │
│ • Detects       │ ───► │ • Deduplicates   │ ───► │ • PagerDuty  │
│   thresholds    │      │   repeats        │      │ • Webhook    │
│ • Sends firing  │      │ • Routes by      │      │              │
│   alerts to     │      │   labels         │      │              │
│   port 9093     │      │ • Silences       │      │              │
│                 │      │ • Inhibits child │      │              │
│                 │      │   alerts         │      │              │
└─────────────────┘      └──────────────────┘      └──────────────┘
```

### Key Concepts

| Concept | What it does |
|---|---|
| **Grouping** | Bundles related alerts into one notification instead of many |
| **Deduplication** | Same alert firing repeatedly sends only one notification |
| **Routing** | Sends different alerts to different receivers based on labels |
| **Silencing** | Mutes alerts for a defined time window (e.g. planned maintenance) |
| **Inhibition** | Suppresses lower-severity alerts when a higher one is already firing |
| **Repeat interval** | Re-notifies if an alert is still firing after a defined time |
| **Resolve notification** | Notifies when an alert clears |

---

## Step 1 — Create Working Directory

```bash
mkdir -p ~/prometheus/alertmanager/data
```

---

## Step 2 — Configure alertmanager.yml

Copy the template from this repo:

```bash
cp config/alertmanager.yml ~/prometheus/alertmanager/alertmanager.yml
```

Open and review:

```bash
nano ~/prometheus/alertmanager/alertmanager.yml
```

### Configuration Walkthrough

**`global` block** — defaults applied to all receivers:

```yaml
global:
  resolve_timeout: 5m    # how long before Alertmanager marks an alert resolved
                         # if Prometheus stops sending it
```

**`route` block** — how alerts are directed to receivers:

```yaml
route:
  group_by: ['alertname', 'cluster']  # group alerts sharing these label values
  group_wait: 0s         # send immediately — no wait for grouping
  group_interval: 30s    # wait 30s before sending new alerts in an existing group
  repeat_interval: 4h    # resend if still firing after 4h
  receiver: 'default'    # fallback receiver for all alerts

  routes:
    # Critical alerts go to a separate receiver (e.g. PagerDuty)
    - matchers:
        - severity="critical"
      receiver: 'critical'
```

**`receivers` block** — where notifications are sent:

```yaml
receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://127.0.0.1:5001/'
        send_resolved: true    # also notify when alert clears
```

**`inhibit_rules` block** — suppress child alerts when parent is firing:

```yaml
inhibit_rules:
  - source_matchers: [severity="critical"]
    target_matchers: [severity="warning"]
    equal: ['cluster']
```

This prevents receiving a warning notification when a critical for the same cluster is already firing — reducing noise.

---

## Step 3 — Choose a Receiver

### Option A — Local Webhook (for testing)

No additional setup required. Uses `scripts/test-webhook.py` to receive and display alert payloads locally. See Step 5.

```yaml
receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://127.0.0.1:5001/'
        send_resolved: true
```

### Option B — Slack (for production)

1. Go to [api.slack.com/apps](https://api.slack.com/apps)
2. Create **New App** → **From Scratch**
3. Enable **Incoming Webhooks**
4. **Add to workspace** → choose a channel
5. Copy the webhook URL

```yaml
receivers:
  - name: 'default'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
        channel: '#crdb-alerts'
        title: '[{{ .Status | toUpper }}] {{ .CommonAnnotations.summary }}'
        text: '{{ .CommonAnnotations.description }}'
        send_resolved: true
```

### Option C — Email (for production)

For Gmail, use an **App Password** — not your account password. Google Account → Security → 2-Step Verification → App Passwords → Generate.

```yaml
global:
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: 'alerts@example.com'
  smtp_auth_username: 'alerts@example.com'
  smtp_auth_password: '<YOUR_APP_PASSWORD>'
  smtp_require_tls: true

receivers:
  - name: 'default'
    email_configs:
      - to: 'oncall@example.com'
        send_resolved: true
```

### Option D — PagerDuty (for production)

```yaml
receivers:
  - name: 'critical'
    pagerduty_configs:
      - routing_key: '<YOUR_PAGERDUTY_ROUTING_KEY>'
        send_resolved: true
```

---

## Step 4 — Validate Configuration

```bash
amtool check-config ~/prometheus/alertmanager/alertmanager.yml
```

Expected output:

```
Checking '~/prometheus/alertmanager/alertmanager.yml'  SUCCESS
Found:
 - global config
 - route
 - 2 inhibit rules
 - 2 receivers
 - 0 templates
```

---

## Step 5 — Run the Local Webhook Receiver

Before starting Alertmanager, open a dedicated terminal tab for the webhook receiver. This will display all incoming alert payloads:

```bash
python3 scripts/test-webhook.py
```

Expected output:

```
Webhook receiver listening on http://127.0.0.1:5001
Waiting for alerts from Alertmanager...
Press Ctrl+C to stop
```

Keep this terminal tab open.

---

## Step 6 — Start Alertmanager

Open another terminal tab and run:

Using the start script from this repo:

```bash
./scripts/start-alertmanager.sh
```

Or manually:

```bash
alertmanager \
  --config.file=$HOME/prometheus/alertmanager/alertmanager.yml \
  --storage.path=$HOME/prometheus/alertmanager/data
```

Expected startup output:

```
msg="Starting Alertmanager"
msg="Loading configuration file" file=alertmanager.yml
msg="Completed loading of configuration file"
msg="Listening on" address=[::]:9093
msg="gossip settled; proceeding"
```

⚠️ **Common mistake:** Running `alertmanager --config.file=alertmanager.yml` from the wrong directory causes `no such file or directory`. Always use the full path: `--config.file=$HOME/prometheus/alertmanager/alertmanager.yml`

---

## Step 7 — Verify Alertmanager is Connected to Prometheus

```bash
curl -s http://localhost:9090/api/v1/alertmanagers \
  | python3 -m json.tool
```

Expected output:

```json
{
  "status": "success",
  "data": {
    "activeAlertmanagers": [
      { "url": "http://localhost:9093/api/v2/alerts" }
    ],
    "droppedAlertmanagers": []
  }
}
```

⚠️ The URL must be `http://localhost:9093/api/v2/alerts` with **no `/alertmanager/` prefix**. If you see `/alertmanager/api/v2/alerts`, remove `path_prefix` from the `alerting` block in `prometheus.yml`. See **03 — Prometheus Setup** for details.

Also check the Alertmanager UI at [http://localhost:9093](http://localhost:9093) and the Prometheus status page at [http://localhost:9090/status](http://localhost:9090/status) — scroll to the **Alertmanagers** section.

---

## Step 8 — Send a Test Alert

Manually inject a test alert directly to Alertmanager to confirm the full delivery pipeline works before relying on real alerts:

```bash
curl --request POST http://localhost:9093/api/v2/alerts \
  --header "Content-Type: application/json" \
  --data '[{
    "labels": {
      "alertname": "TestAlert",
      "severity": "warning",
      "cluster": "my-cluster"
    },
    "annotations": {
      "summary": "This is a test alert",
      "description": "Confirming Alertmanager to webhook delivery works."
    },
    "generatorURL": "http://localhost:9090"
  }]'
```

Check for delivery:

- [http://localhost:9093/#/alerts](http://localhost:9093/#/alerts) — `TestAlert` should appear
- Terminal running `test-webhook.py` — payload should print within 30 seconds

---

## Step 9 — Terminal Layout

You will need three terminal tabs running simultaneously:

```
Tab 1                          Tab 2                    Tab 3
─────────────────────────────  ───────────────────────  ─────────────────────
prometheus \                   alertmanager \           python3 scripts/
  --config.file=...              --config.file=...        test-webhook.py
  --storage.tsdb.path=...        --storage.path=...
                                                         (prints alert payloads)
Prometheus UI: :9090           Alertmanager UI: :9093   Webhook receiver: :5001
```

---

## Reloading Alertmanager Configuration

After any change to `alertmanager.yml`, reload without restarting:

```bash
curl --request POST http://localhost:9093/-/reload
```

Or restart the process. Alertmanager does not support SIGHUP reload.

---

## Next Steps

Continue to **[06 — Verification](06-verification.md)** to confirm the entire monitoring stack is working end-to-end.
