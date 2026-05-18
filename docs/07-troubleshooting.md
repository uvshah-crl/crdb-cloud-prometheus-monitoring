# 07 — Troubleshooting

A reference guide for the most common issues encountered when setting up
Prometheus monitoring for CockroachDB Cloud. Organized by symptom.

---

## Quick Diagnostic Commands

Run these first to get a picture of what is and is not working:

```bash
# Is Prometheus running?
curl -s http://localhost:9090/-/healthy

# Is Alertmanager running?
curl -s http://localhost:9093/-/healthy

# Are targets UP?
curl -s http://localhost:9090/api/v1/targets \
  | python3 -m json.tool | grep -E '"health"|"lastError"'

# Is Alertmanager connected?
curl -s http://localhost:9090/api/v1/alertmanagers \
  | python3 -m json.tool

# Are metrics flowing?
curl -s http://localhost:9090/api/v1/label/__name__/values \
  | python3 -m json.tool | grep crdb_cloud | wc -l

# Are rules loaded?
curl -s http://localhost:9090/api/v1/rules \
  | python3 -m json.tool | grep '"name"'
```

---

## Installation Issues

### `exec format error` when running prometheus or alertmanager

**Symptom:**

```
zsh: exec format error: prometheus
```

**Cause:** You downloaded the Linux binary (linux-amd64) and are running on macOS, or downloaded the wrong architecture for your machine.

**Fix:**

```bash
# Check your architecture
uname -m
# arm64  → need darwin-arm64
# x86_64 → need darwin-amd64

# Check what the binary actually is
file $(which prometheus)
# Must show: Mach-O 64-bit executable arm64 (or amd64)
# If it shows: ELF 64-bit — it is a Linux binary

# Remove the wrong binary and reinstall
sudo rm /usr/local/bin/prometheus
sudo rm /usr/local/bin/promtool

# macOS — use Homebrew (handles architecture automatically)
brew install prometheus

# Or download the correct binary manually
ARCH="darwin-arm64"   # or darwin-amd64
curl -LO https://github.com/prometheus/prometheus/releases/download/v2.52.0/prometheus-2.52.0.${ARCH}.tar.gz
```

### `illegal group name` when running chown

**Symptom:**

```
chown: prometheus: illegal group name
```

**Cause:** Following Linux-specific setup instructions on macOS. Commands like `useradd`, `addgroup`, and `chown prometheus:prometheus` do not work on macOS.

**Fix:** On macOS, run Prometheus as your own user. No dedicated system user is needed for a local development setup. Skip all `useradd` and `chown` commands. Use `~/prometheus/` as your working directory instead of `/etc/prometheus/`.

### `brew install alertmanager` — formula not found

**Symptom:**

```
Warning: No available formula with the name "alertmanager"
```

**Cause:** Alertmanager is not packaged in Homebrew.

**Fix:** Install manually from the GitHub releases page:

```bash
AM_VERSION="0.27.0"
ARCH="darwin-arm64"   # or darwin-amd64

curl -LO https://github.com/prometheus/alertmanager/releases/download/v${AM_VERSION}/alertmanager-${AM_VERSION}.${ARCH}.tar.gz
tar xvf alertmanager-${AM_VERSION}.${ARCH}.tar.gz
file alertmanager-${AM_VERSION}.${ARCH}/alertmanager   # verify architecture
sudo cp alertmanager-${AM_VERSION}.${ARCH}/alertmanager /usr/local/bin/
sudo cp alertmanager-${AM_VERSION}.${ARCH}/amtool /usr/local/bin/
rm -rf alertmanager-${AM_VERSION}.${ARCH}*
```

---

## Prometheus Issues

### Prometheus won't start — config file not found

**Symptom:**

```
open alertmanager.yml: no such file or directory
```

**Cause:** Running with a relative path (`--config.file=prometheus.yml`) from the wrong directory.

**Fix:** Always use the full path:

```bash
prometheus \
  --config.file=$HOME/prometheus/prometheus.yml \
  --storage.tsdb.path=$HOME/prometheus/data \
  --storage.tsdb.retention.time=15d
```

### Prometheus fails to start — config validation error

**Symptom:**

```
msg="Error loading config" err="..."
```

**Fix:**

```bash
# Identify the exact error before starting
promtool check config ~/prometheus/prometheus.yml
promtool check rules ~/prometheus/rules/*.yml
```

Fix the reported error and retry.

### CockroachDB target shows DOWN

**Symptom:** [http://localhost:9090/targets](http://localhost:9090/targets) shows the CockroachDB job as DOWN.

**Diagnosis:**

```bash
curl -s http://localhost:9090/api/v1/targets \
  | python3 -m json.tool | grep "lastError"
```

| Error message | Cause | Fix |
|---|---|---|
| `401 Unauthorized` | API key invalid or expired | Regenerate key in Cloud Console, update `crdb_api_key.txt` |
| `no such file or directory` | `credentials_file` path wrong | Check the path in `prometheus.yml` matches the actual file |
| `connection refused` | Wrong host or port in targets | Target must be `cockroachlabs.cloud`, not the SQL endpoint |
| `context deadline exceeded` | Scrape timeout too short | Add `scrape_timeout: 30s` to the scrape job |
| `x509: certificate` | TLS issue | Ensure `scheme: 'https'` is set |

### No `crdb_cloud_*` metrics in Prometheus

**Symptom:** Targets show UP but no `crdb_cloud_*` metrics appear.

Possible causes and fixes:

1. **Metrics export not enabled on the cluster:**

   ```bash
   curl --request GET \
     --url "https://cockroachlabs.cloud/api/v1/clusters/${CLUSTER_ID}/metricexport/prometheus" \
     --header "Authorization: Bearer ${API_KEY}"
   # status must be "ENABLED" — if "NOT_DEPLOYED", run the POST request
   ```

2. **Wrong `metrics_path` in prometheus.yml:**

   ```yaml
   # Path must be exactly:
   /api/v1/clusters/<CLUSTER_ID>/metricexport/prometheus/<REGION>/scrape
   ```

3. **First scrape hasn't happened yet:** Wait 15–30 seconds after Prometheus starts, then recheck.

### Rules not visible at /rules or /alerts

**Symptom:** [http://localhost:9090/rules](http://localhost:9090/rules) shows no rule groups.

**Fix:**

```bash
# Check rule_files block in prometheus.yml
cat ~/prometheus/prometheus.yml | grep -A 10 "rule_files"

# Verify files exist at the listed paths
ls ~/prometheus/rules/

# Validate rule file syntax
promtool check rules ~/prometheus/rules/*.yml

# Reload Prometheus
kill -HUP $(pgrep prometheus)
```

---

## Alertmanager Issues

### Alerts fire in Prometheus but never appear in Alertmanager

**Symptom:** [http://localhost:9090/alerts](http://localhost:9090/alerts) shows alerts as **Firing** but [http://localhost:9093/#/alerts](http://localhost:9093/#/alerts) is empty.

**Most common cause — `path_prefix` mismatch:**

```bash
curl -s http://localhost:9090/api/v1/alertmanagers \
  | python3 -m json.tool | grep url
```

If the URL contains `/alertmanager/`:

```json
"url": "http://localhost:9093/alertmanager/api/v2/alerts"
```

You have `path_prefix: "/alertmanager/"` in the `alerting` block of `prometheus.yml`. This is copied from the official CockroachDB GitHub `prometheus.yml` which targets a Kubernetes/proxy deployment. In a standalone setup it routes alerts to a path that does not exist on Alertmanager — they are silently dropped.

**Fix:**

```yaml
# prometheus.yml — remove path_prefix
alerting:
  alertmanagers:
    - static_configs:         # ← no path_prefix line
        - targets:
            - localhost:9093
```

```bash
kill -HUP $(pgrep prometheus)

# Confirm the URL is now correct
curl -s http://localhost:9090/api/v1/alertmanagers | python3 -m json.tool
# Must show: "url": "http://localhost:9093/api/v2/alerts"
```

**Second most common cause — missing `alerting` block entirely:**

If the `alerting` block is absent from `prometheus.yml`, Prometheus evaluates rules but has no Alertmanager to send firing alerts to. Add it:

```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - localhost:9093
```

### Alertmanager starts but shows no active alertmanager in Prometheus

**Symptom:**

```json
"activeAlertmanagers": []
```

Causes and fixes:

| Cause | Fix |
|---|---|
| Alertmanager not running | Start Alertmanager on port 9093 |
| Wrong port in `alerting` block | Confirm Alertmanager is on 9093, not another port |
| `alerting` block missing from `prometheus.yml` | Add the block and reload |

### Alertmanager config fails to load

**Symptom:**

```
msg="Loading configuration file failed" err="..."
```

**Fix:**

```bash
amtool check-config ~/prometheus/alertmanager/alertmanager.yml
```

Fix the reported error. Common issues:

| Error | Fix |
|---|---|
| `yaml: line X: mapping values are not allowed` | Indentation error in yml |
| `unknown field` | Typo in a config key |
| `no receivers defined` | Add at least one receiver |

### Webhook receiver not getting alerts

**Symptom:** Alert is **Firing** in Prometheus and visible in Alertmanager but `test-webhook.py` prints nothing.

**Checklist:**

```bash
# 1. Is the webhook receiver running?
curl -s --max-time 2 http://127.0.0.1:5001/

# 2. Is the URL correct in alertmanager.yml?
grep url ~/prometheus/alertmanager/alertmanager.yml
# Must be: url: 'http://127.0.0.1:5001/'

# 3. Has group_wait elapsed?
# Default is 30s — Alertmanager batches alerts before sending
# Check your alertmanager.yml for group_wait value

# 4. Check Alertmanager logs for delivery errors
# Look for lines containing "notify" or "error" in Alertmanager terminal output
```

---

## CockroachDB Cloud API Issues

### POST to enable metrics export returns `unauthorized`

**Symptom:**

```json
{"code": 7, "message": "unauthorized"}
```

**Cause:** The service account used for the POST does not have sufficient permissions. The following roles are **not enough** for the enable operation (POST):

- Metrics Viewer
- Cluster Monitor

**Fix:** Use a service account with **Cluster Operator** (minimum) or **Cluster Admin** role for the one-time POST to enable the pipeline.

**Note:** Metrics Viewer is sufficient for the ongoing scrape endpoint (`GET /metricexport/prometheus/{region}/scrape`). Use a separate Metrics Viewer service account for Prometheus's `credentials_file`. See the two-service-account pattern in **[02 — CockroachDB Cloud Setup](02-crdb-cloud-setup.md)**.

### Metric name not found — `estimated_cpu_seconds`

**Symptom:** Searching for `estimated_cpu_seconds` in Prometheus returns no results.

**Cause:** CockroachDB Cloud metrics use a longer prefixed name with the metric export group included.

**Fix:** The correct metric name is:

```
crdb_cloud_tenant_sql_usage_estimated_cpu_seconds_total
```

To discover all available metric names:

```bash
curl -s http://localhost:9090/api/v1/label/__name__/values \
  | python3 -m json.tool | grep crdb_cloud
```

### PromQL division returns empty result

**Symptom:** The CPU utilization expression returns no data.

**Cause:** Label mismatch between the two metrics being divided.

**Diagnosis:**

```promql
# Run each metric individually and compare label sets
# In the Prometheus query browser (http://localhost:9090/query):

rate(crdb_cloud_tenant_sql_usage_estimated_cpu_seconds_total[5m])
# Note the labels: {cluster="...", region="...", organization="..."}

crdb_cloud_tenant_sql_usage_provisioned_vcpus
# Note the labels: {cluster="...", region="...", organization="..."}
```

If the label sets differ, the `on()` clause needs to list only the labels that match on both sides.

**Fix:**

```promql
rate(crdb_cloud_tenant_sql_usage_estimated_cpu_seconds_total[5m])
/ on(cluster, region, organization)
(crdb_cloud_tenant_sql_usage_provisioned_vcpus > 0)
* 100
```

---

## Summary Reference Table

| Symptom | Most Likely Cause | Quick Fix |
|---|---|---|
| `exec format error` | Wrong OS binary | Download correct arch binary |
| `illegal group name` | Linux command on macOS | Skip system user commands |
| Alertmanager not in Homebrew | Not packaged | Install binary from GitHub |
| Config file not found | Relative path | Use `$HOME/prometheus/...` full path |
| Target DOWN — 401 | API key invalid | Regenerate and update key file |
| No `crdb_cloud_*` metrics | Export not enabled | POST to metricexport API |
| Alerts firing but not in Alertmanager | `path_prefix` mismatch | Remove `path_prefix` from `alerting` block |
| `activeAlertmanagers` empty | Missing `alerting` block | Add `alerting` block to `prometheus.yml` |
| Webhook not receiving | `group_wait` not elapsed | Wait 30s after alert fires |
| `unauthorized` on metrics export POST | Service account lacks Cluster Operator role | Use Cluster Operator for POST; Metrics Viewer is sufficient for GET scrape |
| PromQL division empty | Label mismatch | Add `on(cluster, region, organization)` |
| Metric not found | Wrong metric name | Use `crdb_cloud_tenant_sql_usage_estimated_cpu_seconds_total` |
