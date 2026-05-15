#!/bin/bash
# Validate all Prometheus and Alertmanager configs
# Used locally and in CI
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Validating prometheus.yml ==="
promtool check config "$REPO_ROOT/config/prometheus.yml"

echo ""
echo "=== Validating rule files ==="
for f in "$REPO_ROOT"/config/rules/*.yml; do
  echo "Checking $f..."
  promtool check rules "$f"
done

echo ""
echo "=== Validating alertmanager.yml ==="
amtool check-config "$REPO_ROOT/config/alertmanager.yml"

echo ""
echo "✅ All configs valid"
