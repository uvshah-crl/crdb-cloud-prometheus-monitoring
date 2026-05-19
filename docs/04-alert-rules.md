# 04 — Alert Rules

This section explains how alert rules work, walks through the rules included
in this repo, and shows how to add your own.

---

## Prerequisites

- Prometheus running and scraping your cluster ([03 — Prometheus Setup](03-prometheus-setup.md))
- `crdb_cloud_*` metrics confirmed flowing

---

## How Alert Rules Work

Prometheus evaluates alert rules on the `evaluation_interval` (every 10 seconds
in our config). Each rule contains a PromQL expression. When that expression
returns a result, the alert becomes active.

### Alert States

```
Inactive ──────────► Pending ──────────► Firing
             │                     │
         threshold          for duration
         crossed               elapsed
                                  │
                         Prometheus sends
                         to Alertmanager
```

| State | Meaning | Visible in Alertmanager |
|---|---|---|
| **Inactive** | Expression returns no result — all is well | No |
| **Pending** | Threshold crossed but `for` duration not yet elapsed | No |
| **Firing** | Threshold held for the full `for` duration | ✅ Yes |

The `for` field prevents flapping — a brief CPU spike does not fire an alert
unless it persists for the full duration.

---

## Rule File Structure

All rule files follow this structure:

```yaml
groups:
  - name: <group_name>           # unique within the file
    rules:

      - alert: <AlertName>       # PascalCase, unique across all files
        expr: <PromQL>           # condition that triggers the alert
        for: <duration>          # how long condition must hold before firing
        labels:
          severity: warning      # warning or critical
          component: cockroachdb-cloud
        annotations:
          summary: "<short description>"
          description: "<detailed description with label templating>"
```

### Fields Explained

| Field | Required | Purpose |
|---|---|---|
| `alert` | ✅ | Alert name — appears in Prometheus UI and notifications |
| `expr` | ✅ | PromQL expression — alert fires when this returns a result |
| `for` | Recommended | Minimum duration the condition must hold before firing |
| `labels` | Recommended | Key-value tags used for routing in Alertmanager |
| `annotations` | Recommended | Human-readable context sent in notifications |

### Annotations Templating

Annotations support Go templating with access to alert labels and values:

```yaml
annotations:
  summary: "High CPU on {{ $labels.cluster }}"
  description: >
    Cluster {{ $labels.cluster }} in {{ $labels.region }}
    is using {{ printf "%.1f" $value }}% CPU.
```

| Template variable | Value |
|---|---|
| `{{ $labels.cluster }}` | The cluster label on the metric |
| `{{ $labels.region }}` | The region label on the metric |
| `{{ $value }}` | The numeric value that triggered the alert |
| `{{ printf "%.1f" $value }}` | Value formatted to 1 decimal place |

---

## Understanding the CPU Utilization Rule

This is the primary rule built for CockroachDB Cloud Standard clusters. Understanding it fully helps you write your own rules.

### The Two Metrics

**`crdb_cloud_tenant_sql_usage_estimated_cpu_seconds_total`**
- **Type:** Counter (always increasing, never resets)
- **What it measures:** Total CPU seconds consumed since the cluster started
- **Raw value is not useful** — it grows forever

**`crdb_cloud_tenant_sql_usage_provisioned_vcpus`**
- **Type:** Gauge (current snapshot)
- **What it measures:** How many vCPUs are currently provisioned
- **Raw value is directly useful**

### Why rate() Is Required

A counter's raw value is cumulative — dividing it by vCPUs gives an ever-growing number, not a percentage. `rate()` converts it to a per-second rate over a time window, which makes it meaningful:

```promql
rate(crdb_cloud_tenant_sql_usage_estimated_cpu_seconds_total[5m])
```

This returns: **CPU seconds consumed per second**, averaged over 5 minutes.

### The Full Formula

```promql
(
  rate(crdb_cloud_tenant_sql_usage_estimated_cpu_seconds_total[5m])
  / on(cluster, region, organization)
  (crdb_cloud_tenant_sql_usage_provisioned_vcpus > 0)
  * 100
)
```

Breaking it down:

| Part | Purpose |
|---|---|
| `rate(...[5m])` | Converts counter to per-second rate over 5 min window |
| `/ on(cluster, region, organization)` | Match the two metrics only on these shared labels |
| `(... > 0)` | Guard against division by zero if vCPUs is 0 |
| `* 100` | Convert to percentage |

**Result:** Current CPU utilization as a percentage of provisioned capacity.

### Label Matching with on()

PromQL requires both sides of a division to have identical labels to match. If the two metrics have different label sets, the result is empty.

The `on(cluster, region, organization)` clause tells Prometheus: "Only match on these three labels — ignore any others that differ."

To diagnose label mismatch, run each metric individually in the Prometheus query browser and compare the `{}` label sets they return.

---

## CPU Utilization Rules

Located in `config/rules/cpu_utilization.yml`.

### Warning — 70% for 2 minutes

```yaml
- alert: CRDBCloudHighCPUUtilization
  expr: >
    (
      rate(crdb_cloud_tenant_sql_usage_estimated_cpu_seconds_total[1m])
      / on(cluster, region, organization)
      (crdb_cloud_tenant_sql_usage_provisioned_vcpus > 0)
      * 100
    ) > 70
  for: 2m
  labels:
    severity: warning
```

**Fires when:** CPU utilization exceeds 70% continuously for 2 minutes. Using a 1m rate window for faster spike detection.

### Critical — 90% — fires immediately

```yaml
- alert: CRDBCloudCriticalCPUUtilization
  expr: >
    (
      rate(crdb_cloud_tenant_sql_usage_estimated_cpu_seconds_total[1m])
      / on(cluster, region, organization)
      (crdb_cloud_tenant_sql_usage_provisioned_vcpus > 0)
      * 100
    ) > 90
  for: 0m
  labels:
    severity: critical
```

**Fires when:** CPU utilization exceeds 90% on the first evaluation — no wait. `for: 0m` means Prometheus fires immediately without requiring the condition to hold for any duration. Used here because 90% CPU is severe enough that any occurrence warrants immediate action.

### Threshold Guidance

| Threshold | Rationale |
|---|---|
| 70% for 2m warning | Early signal — investigate before user impact |
| 90% immediate critical | Severe saturation — fire without delay |

CockroachDB Cloud's own built-in alerting fires at 80% sustained for 60 minutes. These rules are significantly more sensitive — 1m rate window, firing at 70%/2m and 90%/immediate.

---

## Other Rule Categories

### SQL Performance (`config/rules/sql_performance.yml`)

| Alert | Condition | Severity |
|---|---|---|
| `CRDBCloudHighSQLErrorRate` | Error rate > 5% for 5m | Warning |
| `CRDBCloudHighP99SQLLatency` | P99 latency > 1s for 5m | Warning |
| `CRDBCloudHighOpenTransactions` | Open transactions > 500 for 5m | Warning |
| `CRDBCloudHighFullScanRate` | Full scans > 10/sec for 10m | Warning |

### Storage (`config/rules/storage.yml`)

| Alert | Condition | Severity |
|---|---|---|
| `CRDBCloudBackupFailing` | Any backup failure in last 1h | Critical |
| `CRDBCloudBackupNotCompleting` | No successful backup in 25h | Warning |

### Changefeed (`config/rules/changefeed.yml`)

| Alert | Condition | Severity |
|---|---|---|
| `CRDBCloudChangefeedFailing` | Any failure in last 10m | Critical |
| `CRDBCloudChangefeedHighLag` | Lag > 10 minutes for 5m | Warning |
| `CRDBCloudChangefeedHighRetries` | Retry rate > 1/sec for 10m | Warning |

### Connection (`config/rules/connection.yml`)

| Alert | Condition | Severity |
|---|---|---|
| `CRDBCloudHighConnectionFailureRate` | Failures > 1/sec for 5m | Warning |
| `CRDBCloudHighActiveConnections` | Connections > 800 for 5m | Warning |

---

## Adding a New Alert Rule

1. **Identify the metric** — use the Prometheus query browser at [http://localhost:9090/query](http://localhost:9090/query) to explore available `crdb_cloud_*` metrics

2. **Build and test the expression** in the query browser first

3. **Add the rule** to the appropriate category file in `config/rules/`

4. **Follow the naming convention:** `CRDBCloud<Category><AlertName>`  
   Examples: `CRDBCloudSQLHighLatency`, `CRDBCloudStorageLow`

5. **Always include** both `summary` and `description` annotations

6. **Validate before reloading:**

   ```bash
   promtool check rules config/rules/*.yml
   ```

7. **Copy the updated file** to your working directory:

   ```bash
   cp config/rules/<category>.yml ~/prometheus/rules/
   ```

8. **Reload Prometheus** without restarting:

   ```bash
   kill -HUP $(pgrep prometheus)
   ```

---

## Validating Rule Files

```bash
# Validate a single file
promtool check rules ~/prometheus/rules/cpu_utilization.yml

# Validate all files at once
promtool check rules ~/prometheus/rules/*.yml
```

A valid file prints a summary of the rules and exits with code 0.

---

## Testing an Alert

To confirm an alert fires and reaches Alertmanager without waiting for a real threshold to be crossed:

1. **Temporarily lower the threshold to `> 0`** (any CPU activity will trigger it)

   ```yaml
   expr: >
     (
       rate(crdb_cloud_tenant_sql_usage_estimated_cpu_seconds_total[5m])
       / on(cluster, region, organization)
       (crdb_cloud_tenant_sql_usage_provisioned_vcpus > 0)
       * 100
     ) > 0
   ```

2. **Validate and reload:**

   ```bash
   promtool check rules ~/prometheus/rules/cpu_utilization.yml
   kill -HUP $(pgrep prometheus)
   ```

3. **Watch the state change** at [http://localhost:9090/alerts](http://localhost:9090/alerts):  
   `Inactive` → `Pending` → `Firing`

4. **Confirm the alert appears** in Alertmanager at [http://localhost:9093/#/alerts](http://localhost:9093/#/alerts)

5. **Revert the threshold** back to `> 70` and reload again

---

## Checking Alert Status

| URL | What to check |
|---|---|
| [http://localhost:9090/rules](http://localhost:9090/rules) | All loaded rules and their current state |
| [http://localhost:9090/alerts](http://localhost:9090/alerts) | Active alerts (Pending and Firing) |
| [http://localhost:9093/#/alerts](http://localhost:9093/#/alerts) | Alerts received by Alertmanager |

---

## Next Steps

Continue to **[05 — Alertmanager Setup](05-alertmanager-setup.md)** to configure notifications.
