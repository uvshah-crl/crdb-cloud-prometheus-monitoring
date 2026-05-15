# 06 — Verification

A structured end-to-end checklist to confirm every layer of the monitoring
stack is working correctly. Run these checks in order — each layer depends
on the one before it.

---

## The Stack in Order

```
Layer 1 — Processes running
Layer 2 — Prometheus scraping CockroachDB Cloud
Layer 3 — Metrics available in Prometheus
Layer 4 — Alert rules loaded and evaluating
Layer 5 — Prometheus connected to Alertmanager
Layer 6 — Alerts reaching Alertmanager
Layer 7 — Alertmanager delivering to receiver
```

Work top-down. If a layer fails, fix it before continuing to the next.

---

## Layer 1 — Processes Running

Confirm all three processes are active:

```bash
# Check Prometheus
curl -s http://localhost:9090/-/healthy
# Expected: Prometheus Server is Healthy.

# Check Alertmanager
curl -s http://localhost:9093/-/healthy
# Expected: OK

# Check webhook receiver
curl -s --max-time 2 http://localhost:5001/ || echo "receiver is listening"
# Expected: no connection refused error
```

If any process is not running, start it:

```bash
# Terminal 1 — Prometheus
./scripts/start-prometheus.sh

# Terminal 2 — Alertmanager
./scripts/start-alertmanager.sh

# Terminal 3 — Webhook receiver
python3 scripts/test-webhook.py
```

---

## Layer 2 — Prometheus Scraping CockroachDB Cloud

Open [http://localhost:9090/targets](http://localhost:9090/targets)

Or check via API:

```bash
curl -s http://localhost:9090/api/v1/targets \
  | python3 -m json.tool \
  | grep -A 3 '"health"'
```

Expected — all targets UP:

| Job | State | Notes |
|---|---|---|
| `prometheus` | UP ✅ | Prometheus self-monitoring |
| `<your_crdb_job>` | UP ✅ | CockroachDB Cloud scrape |

If the CockroachDB job is DOWN:

```bash
# Check the exact error
curl -s http://localhost:9090/api/v1/targets \
  | python3 -m json.tool \
  | grep "lastError"
```

Common errors and fixes:

| Error | Fix |
|---|---|
| `connection refused` | Check `targets` host in `prometheus.yml` |
| `401 Unauthorized` | API key wrong or expired — check `credentials_file` |
| `no such file` | `credentials_file` path wrong |
| `context deadline exceeded` | Increase `scrape_timeout` in `prometheus.yml` |

---

## Layer 3 — Metrics Available in Prometheus

Confirm `crdb_cloud_*` metrics are being stored:

```bash
curl -s http://localhost:9090/api/v1/label/__name__/values \
  | python3 -m json.tool \
  | grep crdb_cloud \
  | wc -l
```

A healthy scrape returns **100+ metrics**.

Spot-check specific metrics used in alert rules:

```bash
# CPU utilization metrics
curl -s 'http://localhost:9090/api/v1/query?query=crdb_cloud_tenant_sql_usage_provisioned_vcpus' \
  | python3 -m json.tool | grep value

# Active SQL connections
curl -s 'http://localhost:9090/api/v1/query?query=crdb_cloud_sql_conns' \
  | python3 -m json.tool | grep value

# Query count rate
curl -s 'http://localhost:9090/api/v1/query?query=rate(crdb_cloud_sql_query_count_total[5m])' \
  | python3 -m json.tool | grep value
```

Each should return a numeric value — not an empty result set.

---

## Layer 4 — Alert Rules Loaded and Evaluating

Check rules are loaded:

Open [http://localhost:9090/rules](http://localhost:9090/rules)

Or via API:

```bash
curl -s http://localhost:9090/api/v1/rules \
  | python3 -m json.tool \
  | grep '"name"'
```

Expected — all rule files and rule names visible:

```
"name": "crdb_cloud_cpu"
"name": "crdb_cloud_sql_performance"
"name": "crdb_cloud_storage"
"name": "crdb_cloud_changefeed"
"name": "crdb_cloud_connections"
```

Check alert states:

Open [http://localhost:9090/alerts](http://localhost:9090/alerts)

Under normal conditions all alerts should be **Inactive** (green). If an alert is **Pending** or **Firing**, that indicates a real condition is being detected — investigate the cluster.

If rules are not visible:

```bash
# Validate rule files
promtool check rules ~/prometheus/rules/*.yml

# Check rule_files paths in prometheus.yml are correct
cat ~/prometheus/prometheus.yml | grep -A 10 "rule_files"

# Reload Prometheus
kill -HUP $(pgrep prometheus)
```

---

## Layer 5 — Prometheus Connected to Alertmanager

```bash
curl -s http://localhost:9090/api/v1/alertmanagers \
  | python3 -m json.tool
```

Expected:

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

Two things to confirm:

1. `activeAlertmanagers` is not empty
2. The URL is `http://localhost:9093/api/v2/alerts` — **no `/alertmanager/` prefix**

If `activeAlertmanagers` is empty:

- Alertmanager is not running — start it
- Or the `alerting` block is missing from `prometheus.yml` — add it

If the URL contains `/alertmanager/`:

- Remove `path_prefix: "/alertmanager/"` from the `alerting` block in `prometheus.yml` and reload Prometheus

---

## Layer 6 — Alerts Reaching Alertmanager

### Test with a manually injected alert

```bash
curl --request POST http://localhost:9093/api/v2/alerts \
  --header "Content-Type: application/json" \
  --data '[{
    "labels": {
      "alertname": "VerificationTest",
      "severity": "warning",
      "cluster": "verification"
    },
    "annotations": {
      "summary": "Verification test alert",
      "description": "Confirming alerts reach Alertmanager."
    },
    "generatorURL": "http://localhost:9090"
  }]'
```

Check [http://localhost:9093/#/alerts](http://localhost:9093/#/alerts) — `VerificationTest` should appear.

### Test with a real rule

Temporarily lower a CPU alert threshold to fire immediately:

```bash
# Edit the rule file
nano ~/prometheus/rules/cpu_utilization.yml
# Change: ) > 70  to  ) > 0

# Reload Prometheus
kill -HUP $(pgrep prometheus)
```

Watch [http://localhost:9090/alerts](http://localhost:9090/alerts) — within two evaluation cycles (20 seconds) the alert should move:

```
Inactive → Pending → Firing
```

Once **Firing**, check [http://localhost:9093/#/alerts](http://localhost:9093/#/alerts) — the alert should appear within `group_wait` (30 seconds by default).

Revert after testing:

```bash
# Restore the real threshold
nano ~/prometheus/rules/cpu_utilization.yml
# Change: ) > 0  back to  ) > 70

kill -HUP $(pgrep prometheus)
```

---

## Layer 7 — Alertmanager Delivering to Receiver

With the test alert injected in Layer 6, check the terminal running `test-webhook.py`:

```
============================================================
Alert received at 14:32:07
============================================================
Status   : FIRING
Receiver : default
Alerts   : 1

  [1] CRDBCloudHighCPUUtilization
      Severity : warning
      Cluster  : ondo-uvshah-marc-15768
      Status   : firing
      Summary  : High CPU utilization on ondo-uvshah-marc-15768
```

If the webhook is not receiving:

- Confirm `test-webhook.py` is running in its terminal tab
- Confirm `alertmanager.yml` receiver URL is `http://127.0.0.1:5001/`
- Check Alertmanager logs for delivery errors
- Confirm `group_wait` has elapsed (default 30s) — Alertmanager batches alerts and waits before sending the first notification

---

## Full End-to-End Verification Summary

```
□ Layer 1 — All three processes healthy
           prometheus: Prometheus Server is Healthy
           alertmanager: OK
           test-webhook.py: listening on :5001

□ Layer 2 — All Prometheus targets UP
           http://localhost:9090/targets
           prometheus job: UP
           crdb cloud job: UP

□ Layer 3 — crdb_cloud_* metrics available
           100+ metrics returned
           crdb_cloud_tenant_sql_usage_provisioned_vcpus has a value
           crdb_cloud_sql_conns has a value

□ Layer 4 — Alert rules loaded and evaluating
           http://localhost:9090/rules — all 5 groups visible
           http://localhost:9090/alerts — all Inactive under normal conditions

□ Layer 5 — Alertmanager connected
           activeAlertmanagers not empty
           URL is /api/v2/alerts (no /alertmanager/ prefix)

□ Layer 6 — Alerts reach Alertmanager
           Test alert visible at http://localhost:9093/#/alerts
           Real rule moved Inactive → Pending → Firing

□ Layer 7 — Receiver delivers notifications
           test-webhook.py printed alert payload
           Payload contains correct alertname, cluster, severity
```

**All layers confirmed?** Your monitoring stack is fully operational.

Move on to **[07 — Troubleshooting](07-troubleshooting.md)** for reference when issues arise in production.

---

## Quick Reference Commands

```bash
# Health checks
curl -s http://localhost:9090/-/healthy
curl -s http://localhost:9093/-/healthy

# Target status
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep health

# Metric count
curl -s http://localhost:9090/api/v1/label/__name__/values | python3 -m json.tool | grep crdb_cloud | wc -l

# Alertmanager connection
curl -s http://localhost:9090/api/v1/alertmanagers | python3 -m json.tool

# Inject test alert
curl --request POST http://localhost:9093/api/v2/alerts \
  --header "Content-Type: application/json" \
  --data '[{"labels":{"alertname":"Test","severity":"warning"},"annotations":{"summary":"test"}}]'

# Reload Prometheus after config changes
kill -HUP $(pgrep prometheus)

# Reload Alertmanager after config changes
curl --request POST http://localhost:9093/-/reload
```
