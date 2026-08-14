# Back-End Report Canonical JSON

Use schema version 2.0 and validate it with `scripts/validate_report_data.ps1`. The machine-readable contract is `report-schema-v2.json`; default severity and comparability thresholds are in `default-thresholds.json`.

Every assessed row contains:

- `source_paths`: non-empty `baseline:`/`current:` provenance.
- `assessment`: severity, confidence, evidence, likely cause, and investigation route.

The report contains Executive Summary plus node, server, GC, smaps, configuration, database, SQL, AWR, instance, ndump, CMB, artifact coverage, errors/warnings, limitations, and detail collections.

Use null when evidence is unavailable. Calculate a delta only when both sides exist. Keep SQL rows distinct by database, SQL ID, and plan hash. Preserve AWR period, duration, workload, and qualification. Preserve source-relative paths; do not execute SQL or connect to a database.

Run files contain only the validated workbook-facing inventory fields. Parser-only SHA-256, duplicate, ZIP-member, and confidence metadata remains available from `parse_artifacts.ps1` inventory output.

