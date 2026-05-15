# CockroachDB Cloud — Prometheus Monitoring & Alerting

A replicable, extensible monitoring and alerting setup for **CockroachDB Standard and Advanced** clusters using Prometheus and Alertmanager.

Built and maintained by Cockroach Labs Enterprise Architecture.

---

## What This Repo Provides

- ✅ Prometheus configuration to scrape metrics from CockroachDB Cloud
- ✅ Alertmanager configuration with routing and receiver templates
- ✅ Modular alert rule files organized by category
- ✅ Step-by-step setup docs for macOS and Linux
- ✅ Scripts to start, validate, and test the stack locally
- ✅ CI validation of all configs on every commit

## Architecture

```
CockroachDB Cloud Cluster
         │
         │ HTTPS scrape via API key
         │ /metricexport/prometheus/{region}/scrape
         ▼
   Prometheus (localhost:9090)
         │
         │ evaluates alert rules every 10s
         │ forwards firing alerts
         ▼
  Alertmanager (localhost:9093)
         │
         │ routes, groups, deduplicates
         │ sends notifications
         ▼
    Receiver
  (Slack / Email / PagerDuty / Webhook)
```


## Quick Start

1. [Prerequisites](docs/01-prerequisites.md)
2. [CockroachDB Cloud Setup](docs/02-crdb-cloud-setup.md) — service account + API key + enable metrics export
3. [Prometheus Setup](docs/03-prometheus-setup.md)
4. [Alert Rules](docs/04-alert-rules.md)
5. [Alertmanager Setup](docs/05-alertmanager-setup.md)
6. [Verify Everything Works](docs/06-verification.md)
7. [Troubleshooting](docs/07-troubleshooting.md)

## Alert Rule Categories

| File | Coverage |
|---|---|
| [`config/rules/cpu_utilization.yml`](config/rules/cpu_utilization.yml) | CPU usage vs provisioned vCPUs |
| [`config/rules/sql_performance.yml`](config/rules/sql_performance.yml) | Query latency, error rate, active statements |
| [`config/rules/storage.yml`](config/rules/storage.yml) | Storage bytes, backup schedules |
| [`config/rules/changefeed.yml`](config/rules/changefeed.yml) | Changefeed lag, failures, retries |
| [`config/rules/connection.yml`](config/rules/connection.yml) | Connection counts, failure rates |

## Tested With

- CockroachDB Cloud Standard (GCP)
- Prometheus 2.52.0 (darwin/arm64, linux/amd64)
- Alertmanager 0.27.0

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md)

## License

Apache 2.0 — see [LICENSE](LICENSE)
