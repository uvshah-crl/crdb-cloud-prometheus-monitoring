#!/bin/bash
# Start Alertmanager with the repo config
# Usage: ./scripts/start-alertmanager.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG="$REPO_ROOT/config/alertmanager.yml"
DATA_DIR="$HOME/prometheus/alertmanager/data"

# Validate first
echo "Validating Alertmanager config..."
amtool check-config "$CONFIG"
echo "✅ Config valid"

mkdir -p "$DATA_DIR"

echo "Starting Alertmanager on http://localhost:9093"
alertmanager \
  --config.file="$CONFIG" \
  --storage.path="$DATA_DIR"
