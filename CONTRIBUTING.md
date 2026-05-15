# Contributing

## Adding New Alert Rules

1. Identify the metric from the available `crdb_cloud_*` metric list
2. Add rules to the appropriate file under `config/rules/`
3. Follow the naming convention: `CRDBCloud<Category><AlertName>`
4. Always include `summary` and `description` annotations
5. Always include `severity` label (`warning` or `critical`)
6. Validate before submitting: `promtool check rules config/rules/*.yml`

## Testing Changes

```bash
./scripts/validate-configs.sh
