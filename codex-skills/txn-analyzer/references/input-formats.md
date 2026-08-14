# Input formats

## CSV files

Expect UTF-8 CSV with a header row.

Normalize these values:
- empty string -> missing
- `tba` -> missing
- case-insensitive matching for bindings and names

## Scenario YAML

Accept one or more `scenario.yaml` files. Parse them best-effort and preserve:
- file path
- YAML path
- scalar field names and values
- any request, transaction, script, service, binding, or step fields

If a scenario uses different field names, keep the raw YAML content and extract the closest matching values.
