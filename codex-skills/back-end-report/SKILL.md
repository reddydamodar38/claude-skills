---
name: back-end-report
description: Use when comparing baseline and current ABLCAPUTIL back-end runs, investigating JVM/GC, database, SQL, AWR, ndump, CMB, memory, instance, configuration, or artifact-coverage changes, or producing a consolidated Excel back-end comparison report.
---

# Back-End Report

## Workflow

Read `references/report-data-contract.md` and `references/report-schema.md`. Run the end-to-end orchestrator:

```powershell
scripts/build_report.ps1 -BaselinePath <baseline-run> -CurrentPath <current-run> -OutputDirectory <output-folder>
```

The orchestrator inventories and hashes artifacts, parses supported evidence, builds schema-v2 JSON, assesses findings, validates the contract, renders Excel, and validates the workbook. A failed validation gate fails the run.

Use `-JsonOnly` when Excel COM is unavailable. Use `-InventoryOnly` to classify evidence without comparing it. Use `-ValidateOnly` as a CI-oriented alias that builds and validates JSON without rendering. Pass `-ThresholdsPath` to override `references/default-thresholds.json` consistently for assessment and validation.

## Evidence handling

- Summarize unknown and archive evidence in Artifact Coverage. Use `-InventoryOnly` when SHA-256, duplicate, and ZIP-member detail must be retained.
- Treat unsupported formats as limitations; never fabricate a metric.
- Keep unavailable metrics null. Do not substitute zero or sentinel identifiers.
- Preserve `baseline:` and `current:` source provenance and parser limitations.
- Join servers by node and server ID, never PID.
- Join SQL by database and SQL ID, retain separate plan-hash rows, and compare per-execution metrics.
- Qualify AWR comparisons when duration or workload differs.
- Aggregate instance samples before comparing; use the final after-GC sample for retained-heap evidence.
- Treat PSS/Private Dirty growth without proportional after-GC growth as native/off-heap evidence.
- Map `cmb_<server>` from its filename and group ndump evidence by node/server when supported.
- Never execute SQL or connect to a database.

## Outputs

`back-end-report.json` is always the canonical output. Normal mode also creates `back-end-report.xlsx` with the six original sheets, Executive Summary, extended evidence sheets, and High-server detail tabs. Missing categories remain visible as headers-only sheets and limitations/coverage entries.

The parser intentionally supports documented common text/CSV formats. Review `report.limitations` before treating a missing metric as evidence of no change.

