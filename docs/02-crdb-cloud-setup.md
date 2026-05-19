# 02 — CockroachDB Cloud Setup

This section configures CockroachDB Cloud to expose a Prometheus-compatible
scrape endpoint that your local Prometheus can pull metrics from.

---

## Overview

CockroachDB Cloud clusters expose metrics through the Cloud API via a managed
scrape endpoint. Access requires a **service account** with an **API key**.

**Note on Advanced clusters:** Advanced clusters with private network connectivity
(VPC peering, AWS PrivateLink, or GCP Private Service Connect) can also scrape
`/_status/vars` directly from individual nodes on port 8080. This provides 200+
raw CockroachDB metrics with lower latency. This setup is not covered in this
repo, which focuses on the `/metricexport/prometheus` API that works for both
Standard and Advanced clusters.

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

## Step 2 — Create Two Service Accounts

This setup uses two service accounts following the principle of least privilege:

- **Setup account** — used once to enable the Prometheus export pipeline.
  Requires Cluster Operator role. API key can be revoked after setup.
- **Scraping account** — used by Prometheus for ongoing metric collection.
  Requires only Metrics Viewer role. This is the key stored in `credentials_file`.

**Create the setup account:**

1. Go to [cockroachlabs.cloud](https://cockroachlabs.cloud) → **Access Management**
2. Click the **Service Accounts** tab
3. Click **Create service account**
4. Name it: `prometheus-setup`
5. Click **Create**

**Create the scraping account:**

1. Click **Create service account** again
2. Name it: `prometheus-scraper`
3. Click **Create**

---

## Step 3 — Assign the Correct Roles

⚠️ **This step is critical.** The wrong role will cause the metrics export enablement to return `unauthorized`.

| Role | Enable export (POST) | Scrape metrics (GET) | Used for |
|---|---|---|---|
| Metrics Viewer | ❌ | ✅ | `prometheus-scraper` (ongoing) |
| Cluster Operator | ✅ | ✅ | `prometheus-setup` (one-time) |

> **Note:** Cluster Admin can also enable export, but Cluster Operator follows least-privilege principles. Cluster Monitor can scrape but cannot enable export—we use Metrics Viewer as it provides the same scraping permissions with a clearer name.

**Assign Cluster Operator to `prometheus-setup`:**

1. On the **Service Accounts** page, click `prometheus-setup`
2. Click **Add role**
3. Set scope to your specific cluster (not organization-wide)
4. Select **Cluster Operator**
5. Click **Save**

**Assign Metrics Viewer to `prometheus-scraper`:**

1. On the **Service Accounts** page, click `prometheus-scraper`
2. Click **Add role**
3. Set scope to your specific cluster (not organization-wide)
4. Select **Metrics Viewer**
5. Click **Save**

---

## Step 4 — Generate API Keys

Generate one API key per service account.

**For `prometheus-setup` (used for one-time enable):**

1. Click `prometheus-setup` in the Service Accounts list
2. Click **Generate API key**, name it `setup-key`
3. Click **Create** — copy the key immediately

```bash
export SETUP_KEY="<YOUR_SETUP_API_KEY>"
```

**For `prometheus-scraper` (used by Prometheus permanently):**

1. Click `prometheus-scraper` in the Service Accounts list
2. Click **Generate API key**, name it `prometheus-local`
3. Click **Create** — copy the key immediately

```bash
# Store the scraper key — this is what Prometheus uses
echo -n "<YOUR_SCRAPER_API_KEY>" > ~/prometheus/secrets/crdb_api_key.txt
chmod 600 ~/prometheus/secrets/crdb_api_key.txt

export API_KEY=$(cat ~/prometheus/secrets/crdb_api_key.txt)
```

API keys follow the format: `CCDB1_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

---

## Step 5 — Enable Prometheus Metrics Export

Send a POST request to activate the metrics export pipeline:

```bash
# Use the SETUP_KEY (Cluster Operator) — not the scraper key
curl --request POST \
  --url "https://cockroachlabs.cloud/api/v1/clusters/${CLUSTER_ID}/metricexport/prometheus" \
  --header "Authorization: Bearer ${SETUP_KEY}"
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
# Either key works for GET — use SETUP_KEY while you still have it
curl --request GET \
  --url "https://cockroachlabs.cloud/api/v1/clusters/${CLUSTER_ID}/metricexport/prometheus" \
  --header "Authorization: Bearer ${SETUP_KEY}" \
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

# Verify with the SCRAPER key (Metrics Viewer) — this confirms the role works
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
| `SETUP_KEY` | Cluster Operator key — used only for the enable POST in Step 5 |
| `API_KEY` | Metrics Viewer key — stored in `~/prometheus/secrets/crdb_api_key.txt` — used by Prometheus |
| Scrape URL | From `targets` map in Step 6 response |

---

## Security Notes

- **Use two service accounts** — one with Cluster Operator for the one-time enable POST, one with Metrics Viewer for ongoing Prometheus scraping. This is the minimum privilege setup.
- **Revoke the setup key after use** — once the export pipeline is ENABLED, the Cluster Operator API key is no longer needed. Revoke it in the Cloud Console to reduce your attack surface.
- **Use `credentials_file`** in `prometheus.yml` instead of inline `credentials` to avoid secrets appearing in process lists or version control.
- **Limit service account scope** — assign roles at the individual cluster level, not organization-wide, unless multi-cluster access is explicitly needed.
- **Rotate the scraper key regularly** — generate a new Metrics Viewer key, update `crdb_api_key.txt`, reload Prometheus, then revoke the old key.
- **Never commit `~/prometheus/secrets/`** — it is already in `.gitignore`.

---

## Next Steps

Continue to **[03 — Prometheus Setup](03-prometheus-setup.md)** to configure Prometheus to scrape your cluster.
