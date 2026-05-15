#!/bin/bash
# Start Prometheus with the repo config
# Usage: ./scripts/start-prometheus.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG="$REPO_ROOT/config/prometheus.yml"
DATA_DIR="$HOME/prometheus/data"

# Validate first
echo "Validating Prometheus config..."
promtool check config "$CONFIG"
promtool check rules "$REPO_ROOT"/config/rules/*.yml
echo "✅ Config valid"

mkdir -p "$DATA_DIR"

echo "Starting Prometheus on http://localhost:9090"
prometheus \
  --config.file="$CONFIG" \
  --storage.tsdb.path="$DATA_DIR" \
  --storage.tsdb.retention.time=15d
