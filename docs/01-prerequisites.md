# 01 — Prerequisites

Before starting, ensure you have everything below in place.
Setup time: approximately 15 minutes.

---

## CockroachDB Cloud

- [ ] A **CockroachDB Standard or Advanced** cluster already running
- [ ] Access to the **CockroachDB Cloud Console** at [cockroachlabs.cloud](https://cockroachlabs.cloud)
- [ ] Your account has **Organization Admin** or **Cluster Admin** role
      _(required to create service accounts and generate API keys)_

---

## Local Machine

### Operating System

| OS | Supported |
|---|---|
| macOS (Apple Silicon — arm64) | ✅ |
| macOS (Intel — x86_64) | ✅ |
| Linux (amd64) | ✅ |

> **Check your architecture:**
> ```bash
> uname -m
> # arm64  → Apple Silicon
> # x86_64 → Intel Mac or Linux
> ```

### Required Tools

| Tool | Purpose | Check |
|---|---|---|
| `curl` | Download binaries + test endpoints | `curl --version` |
| `python3` | Local webhook receiver for testing | `python3 --version` |
| `git` | Clone and version control this repo | `git --version` |
| `gh` | GitHub CLI for repo creation (optional) | `gh --version` |

### Ports Available

The following ports must be free on your machine:

| Port | Used by |
|---|---|
| `9090` | Prometheus UI and API |
| `9093` | Alertmanager UI and API |
| `5001` | Local webhook receiver (testing only) |

Check if a port is in use:
```bash
lsof -i :9090
lsof -i :9093
lsof -i :5001
```

---

## Install Prometheus

### macOS (Homebrew — recommended)

```bash
brew install prometheus
prometheus --version
promtool --version
```

### macOS / Linux (manual binary)

```bash
# Check your architecture first: uname -m
# Use darwin-arm64 for Apple Silicon, darwin-amd64 for Intel Mac, linux-amd64 for Linux

PROM_VERSION="2.52.0"
ARCH="darwin-arm64"   # change as needed

curl -LO https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.${ARCH}.tar.gz
tar xvf prometheus-${PROM_VERSION}.${ARCH}.tar.gz

# Verify architecture before installing
file prometheus-${PROM_VERSION}.${ARCH}/prometheus
# Must show: Mach-O 64-bit executable arm64  (or matching your arch)

sudo cp prometheus-${PROM_VERSION}.${ARCH}/prometheus /usr/local/bin/
sudo cp prometheus-${PROM_VERSION}.${ARCH}/promtool /usr/local/bin/
rm -rf prometheus-${PROM_VERSION}.${ARCH}*

prometheus --version
promtool --version
```

---

## Install Alertmanager

Alertmanager is not available via Homebrew. Install manually.

```bash
AM_VERSION="0.27.0"
ARCH="darwin-arm64"   # change as needed

curl -LO https://github.com/prometheus/alertmanager/releases/download/v${AM_VERSION}/alertmanager-${AM_VERSION}.${ARCH}.tar.gz
tar xvf alertmanager-${AM_VERSION}.${ARCH}.tar.gz

# Verify architecture before installing
file alertmanager-${AM_VERSION}.${ARCH}/alertmanager
# Must show: Mach-O 64-bit executable arm64  (or matching your arch)

sudo cp alertmanager-${AM_VERSION}.${ARCH}/alertmanager /usr/local/bin/
sudo cp alertmanager-${AM_VERSION}.${ARCH}/amtool /usr/local/bin/
rm -rf alertmanager-${AM_VERSION}.${ARCH}*

alertmanager --version
amtool --version
```

---

## Create Working Directories

```bash
mkdir -p ~/prometheus/data
mkdir -p ~/prometheus/alertmanager/data
mkdir -p ~/prometheus/secrets
```

**Security:** The `secrets/` directory will hold your API key. Never commit this directory — it is already in `.gitignore`
