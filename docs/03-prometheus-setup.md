# 03 — Prometheus Setup

This section installs and configures Prometheus to scrape metrics from your
CockroachDB Cloud cluster and evaluate alert rules.

---

## Prerequisites

- Prometheus and promtool installed ([01 — Prerequisites](01-prerequisites.md))
- CockroachDB Cloud metrics export enabled ([02 — CockroachDB Cloud Setup](02-crdb-cloud-setup.md))
- Your cluster ID, region, and API key ready

---

## Step 1 — Create Working Directories

```bash
mkdir -p ~/prometheus/data
mkdir -p ~/prometheus/secrets
```

---

## Step 2 — Store Your API Key

Store the API key in a file rather than inline in config. This keeps secrets out of config files and process lists.

```bash
echo -n "<YOUR_API_KEY>" > ~/prometheus/secrets/crdb_api_key.txt
chmod 600 ~/prometheus/secrets/crdb_api_key.txt
```

---

## Step 3 — Configure prometheus.yml

Copy the template from this repo and fill in your values:

```bash
cp config/prometheus.yml ~/prometheus/prometheus.yml
```

Open and edit:

```bash
nano ~/prometheus/prometheus.yml
```

The full configuration with all sections explained:

```yaml
# ~/prometheus/prometheus.yml

global:
  # How often Prometheus scrapes each target
  scrape_interval: 10s
  # How often Prometheus evaluates alert rules
  evaluation_interval: 10s

# Tells Prometheus where Alertmanager is running.
# IMPORTANT: Do not add path_prefix here for standalone Alertmanager.
# path_prefix is only for reverse proxy or Kubernetes deployments.
# Without this block, firing alerts are never sent to Alertmanager.
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - localhost:9093

# Alert rule files to load.
# Add new category files here as you expand coverage.
rule_files:
  - "rules/cpu_utilization.yml"
  - "rules/sql_performance.yml"
  - "rules/storage.yml"
  - "rules/changefeed.yml"
  - "rules/connection.yml"

scrape_configs:

  # Prometheus self-monitoring.
  # Scrapes Prometheus's own /metrics endpoint so you can monitor
  # the health of the monitoring stack itself.
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # CockroachDB Cloud — one job per region.
  # Duplicate this block for each additional region your cluster spans.
  - job_name: '<YOUR_JOB_NAME>'
    metrics_path: '/api/v1/clusters/<YOUR_CLUSTER_ID>/metricexport/prometheus/<YOUR_REGION>/scrape'
    scheme: 'https'
    static_configs:
      - targets: ['cockroachlabs.cloud']
        labels:
          crdb_cluster: '<YOUR_CLUSTER_NAME>'
          env: '<YOUR_ENV>'
    authorization:
      # Metrics Viewer role is sufficient for ongoing scraping.
      # See docs/02-crdb-cloud-setup.md for the two-service-account setup.
      credentials_file: '/Users/<YOUR_USERNAME>/prometheus/secrets/crdb_api_key.txt'
```

Fill in these values:

| Placeholder | Your value | Example |
|---|---|---|
| `<YOUR_JOB_NAME>` | Descriptive name for this scrape job | `crdb-cloud-prod-us-central1` |
| `<YOUR_CLUSTER_ID>` | UUID from Step 1 of doc 02 | `f78b7feb-b6cf-4396-9d7f-494982d7d81e` |
| `<YOUR_REGION>` | Region from the scrape URL in doc 02 | `us-central1` |
| `<YOUR_CLUSTER_NAME>` | Human-readable cluster name | `my-cluster-1234` |
| `<YOUR_ENV>` | Environment label | `production` |
| `<YOUR_USERNAME>` | Your macOS/Linux username | `jsmith` |

---

## Step 4 — Copy Rule Files

Copy the alert rule files from this repo to your working directory:

```bash
mkdir -p ~/prometheus/rules

cp config/rules/cpu_utilization.yml ~/prometheus/rules/
cp config/rules/sql_performance.yml ~/prometheus/rules/
cp config/rules/storage.yml         ~/prometheus/rules/
cp config/rules/changefeed.yml      ~/prometheus/rules/
cp config/rules/connection.yml      ~/prometheus/rules/
```

---

## Step 5 — Validate Configuration

Always validate before starting Prometheus:

```bash
# Validate the main config file
promtool check config ~/prometheus/prometheus.yml

# Validate all rule files
promtool check rules ~/prometheus/rules/*.yml
```

Both commands should return `SUCCESS` with no errors.

Common validation errors:

| Error | Cause | Fix |
|---|---|---|
| `no such file or directory` | Rule file path wrong | Check `rule_files` paths match actual file locations |
| `unknown fields` | Typo in a config key | Check indentation and field names |
| `invalid duration` | Wrong time format | Use `10s`, `5m`, `1h` — not `10`, `5mins` |

---

## Step 6 — Start Prometheus

Using the start script from this repo:

```bash
./scripts/start-prometheus.sh
```

Or manually:

```bash
prometheus \
  --config.file=$HOME/prometheus/prometheus.yml \
  --storage.tsdb.path=$HOME/prometheus/data \
  --storage.tsdb.retention.time=15d
```

Expected startup output:

```
ts=... msg="Starting Prometheus"
ts=... msg="Loading configuration file" filename=...prometheus.yml
ts=... msg="Completed loading of configuration file"
ts=... msg="Server is ready to receive web requests."
```

If you see `Completed loading of configuration file` — Prometheus started successfully.

---

## Step 7 — Verify Targets Are Being Scraped

Open [http://localhost:9090/targets](http://localhost:9090/targets)

You should see two jobs:

| Job | State | What it monitors |
|---|---|---|
| `prometheus` | UP ✅ | Prometheus itself |
| `<YOUR_JOB_NAME>` | UP ✅ | CockroachDB Cloud cluster |

If the CockroachDB job shows `DOWN`, check the **Error** column for the exact reason. Common causes are documented in **07 — Troubleshooting**.

---

## Step 8 — Verify Metrics Are Flowing

Confirm `crdb_cloud_*` metrics are available:

```bash
curl -s http://localhost:9090/api/v1/label/__name__/values \
  | python3 -m json.tool \
  | grep crdb_cloud \
  | head -20
```

You should see a list of metric names beginning with `crdb_cloud_`.

To see the full list of available metrics:

```bash
curl -s http://localhost:9090/api/v1/label/__name__/values \
  | python3 -m json.tool \
  | grep crdb_cloud \
  | wc -l
```

A healthy Standard cluster scrape returns approximately **100+ metrics**.

---

## Step 9 — Verify Alertmanager Connection

Confirm Prometheus knows where Alertmanager is:

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

⚠️ **Important:** The URL must be `http://localhost:9093/api/v2/alerts` with **no `/alertmanager/` path prefix**.

If you see `/alertmanager/api/v2/alerts` in the URL, you have a `path_prefix: "/alertmanager/"` in your `prometheus.yml` alerting block. **Remove it.** This is a common copy-paste issue from the official CockroachDB GitHub `prometheus.yml`, which targets a Kubernetes/proxy deployment. In a standalone setup it causes alerts to be sent to a path that does not exist on Alertmanager, so they are silently dropped.

---

## Reloading Configuration

After any change to `prometheus.yml` or rule files, reload without restarting:

```bash
kill -HUP $(pgrep prometheus)
```

Prometheus will log:

```
msg="Loading configuration file"
msg="Completed loading of configuration file"
```

---

## Next Steps

Continue to **[04 — Alert Rules](04-alert-rules.md)** to understand how the alert rules work.
