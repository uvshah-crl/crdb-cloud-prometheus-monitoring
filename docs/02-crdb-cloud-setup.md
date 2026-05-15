# 02 — CockroachDB Cloud Setup

This section configures CockroachDB Cloud to expose a Prometheus-compatible
scrape endpoint that your local Prometheus can pull metrics from.

---

## Overview

CockroachDB Cloud Standard and Advanced clusters do not expose `/_status/vars`
directly. Instead, metrics are accessed through the Cloud API via a managed
scrape endpoint. Access requires a **service account** with an **API key**.

The setup follows these steps:

1. Get your cluster ID
2. Create a service account in the Cloud Console
3. Assign the **Cluster Operator** role to the service account
4. Generate an API key
5. Enable Prometheus metrics export via the Cloud API
6. Confirm the scrape endpoint is returning metrics

---

## Step 1 — Get Your Cluster ID

You will need your cluster ID (a UUID) for all API calls.

**Option A — From the Cloud Console URL:**

1. Go to [cockroachlabs.cloud](https://cockroachlabs.cloud)
2. Click your cluster
3. The URL will contain your cluster ID: `https://cockroachlabs.cloud/cluster/<YOUR_CLUSTER_ID>/...`
4. Copy the UUID — it looks like: `f78b7feb-b6cf-4396-9d7f-494982d7d81e`

**Option B — From the Cloud API:**

```bash
curl --request GET \
  --url https://cockroachlabs.cloud/api/v1/clusters \
  --header "Authorization: Bearer <YOUR_EXISTING_API_KEY>" \
  | python3 -m json.tool | grep -E '"id"|"name"'
```

Store it as an environment variable for use in subsequent steps:

```bash
export CLUSTER_ID="<YOUR_CLUSTER_ID>"
```

---

## Step 2 — Create a Service Account

A service account is a non-human identity used for programmatic API access. It authenticates via an API key instead of a username and password.

1. Go to [cockroachlabs.cloud](https://cockroachlabs.cloud) → **Access Management**
2. Click the **Service Accounts** tab
3. Click **Create service account**
4. Name it something descriptive: e.g. `prometheus-metrics-reader`
5. Click **Create**

---

## Step 3 — Assign the Correct Role

⚠️ **This step is critical.** The wrong role will cause the metrics export enablement to return `unauthorized`.

| Role | Can read metrics | Can enable export (POST) |
|---|---|---|
| Metrics Viewer | ✅ | ❌ |
| Cluster Monitor | ✅ | ❌ |
| Cluster Operator | ✅ | ✅ ← minimum required |
| Cluster Admin | ✅ | ✅ |

Steps to assign **Cluster Operator**:

1. On the **Service Accounts** page, click your new service account
2. Click **Add role**
3. Set scope to **your specific cluster** (not organization-wide)
4. Select **Cluster Operator**
5. Click **Save**

---

## Step 4 — Generate an API Key

1. On your service account page, click **Generate API key**
2. Give the key a name: e.g. `prometheus-local`
3. Click **Create**
4. **Copy the key immediately** — it is only shown once

Store it securely:

```bash
# Store in your local secrets directory (never commit this)
echo -n "<YOUR_API_KEY>" > ~/prometheus/secrets/crdb_api_key.txt
chmod 600 ~/prometheus/secrets/crdb_api_key.txt

# Export for use in subsequent steps
export API_KEY=$(cat ~/prometheus/secrets/crdb_api_key.txt)
```

API keys follow the format: `CCDB1_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

---

## Step 5 — Enable Prometheus Metrics Export

Send a POST request to activate the metrics export pipeline:

```bash
curl --request POST \
  --url "https://cockroachlabs.cloud/api/v1/clusters/${CLUSTER_ID}/metricexport/prometheus" \
  --header "Authorization: Bearer ${API_KEY}"
```

Expected response:

```json
{
  "cluster_id": "f78b7feb-b6cf-4396-9d7f-494982d7d81e",
  "user_message": "This integration is being enabled.",
  "status": "ENABLING",
  "targets": {
    "us-central1": "https://cockroachlabs.cloud/api/v1/clusters/.../metricexport/prometheus/us-central1/scrape"
  }
}
```

If you receive `{"code": 7, "message": "unauthorized"}` — the service account does not have **Cluster Operator** role. Go back to Step 3.

---

## Step 6 — Wait for ENABLED Status

Enabling takes 1–3 minutes. Poll until status is `ENABLED`:

```bash
curl --request GET \
  --url "https://cockroachlabs.cloud/api/v1/clusters/${CLUSTER_ID}/metricexport/prometheus" \
  --header "Authorization: Bearer ${API_KEY}" \
  | python3 -m json.tool
```

Expected final response:

```json
{
  "cluster_id": "f78b7feb-b6cf-4396-9d7f-494982d7d81e",
  "user_message": "This integration is active.",
  "status": "ENABLED",
  "targets": {
    "us-central1": "https://cockroachlabs.cloud/api/v1/clusters/f78b7feb-b6cf-4396-9d7f-494982d7d81e/metricexport/prometheus/us-central1/scrape"
  }
}
```

Note the scrape URL from `targets` — you will need it in the next step.

> **For multi-region clusters,** `targets` will contain one entry per region. Configure a separate Prometheus scrape job for each region.

---

## Step 7 — Confirm the Scrape Endpoint Returns Metrics

```bash
export REGION="us-central1"   # change to match your cluster region

curl --request GET \
  --url "https://cockroachlabs.cloud/api/v1/clusters/${CLUSTER_ID}/metricexport/prometheus/${REGION}/scrape" \
  --header "Authorization: Bearer ${API_KEY}" \
  | head -20
```

Expected output:

```
# HELP crdb_cloud_sql_query_count_total Number of SQL queries
# TYPE crdb_cloud_sql_query_count_total counter
crdb_cloud_sql_query_count_total{cluster="my-cluster",region="us-central1",...} 12345
# HELP crdb_cloud_sql_conns Current number of open SQL connections
...
```

If you see Prometheus-formatted metrics — the endpoint is working. ✅

---

## Step 8 — Note Your Values for prometheus.yml

You will need these in **03 — Prometheus Setup**:

| Value | Where to find it |
|---|---|
| `CLUSTER_ID` | Cloud Console URL or API response |
| `REGION` | From `targets` map in Step 6 response |
| `API_KEY` | Generated in Step 4, stored in `~/prometheus/secrets/crdb_api_key.txt` |
| Scrape URL | From `targets` map in Step 6 response |

---

## Security Notes

- **Rotate API keys regularly** — generate a new key, update `crdb_api_key.txt`, reload Prometheus. Revoke old keys in the Cloud Console.
- **Use `credentials_file`** in `prometheus.yml` instead of inline `credentials` to avoid secrets appearing in process lists or version control.
- **Limit the service account scope** — assign **Cluster Operator** at the individual cluster level, not organization-wide.
- **Never commit `~/prometheus/secrets/`** — it is already in `.gitignore`.
