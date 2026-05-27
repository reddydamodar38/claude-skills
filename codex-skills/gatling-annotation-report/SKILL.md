---
name: gatling-annotation-report
description: Generate annotation resolution reports from Gatling scenario-data.yaml and replies.yaml. Produces HTML with columns index, name, path, actual value, count; sorted by transaction number.
---

# Gatling Annotation Report

Use this skill to generate annotation reports for converted Gatling scenarios.

## Inputs
- `scenario-data.yaml`
- one or more `replies*.yaml`

## Output
- HTML report in reports directory with columns:
  - `index`
  - `name`
  - `path`
  - `actual value`
  - `count`
- ordered by transaction number parsed from annotation path prefix (e.g. `_40_1` => `40`).
- Additional final section:
  - `Annotations In scenario-data.yaml But Not Used In scenario.yaml`
  - compares annotation `name` entries in `scenario-data.yaml` against `${...}` references in sibling `scenario.yaml`
  - includes `index`, `name`, `path`, `count`

## Script
- `scripts/generate_annotation_report.ps1`

Example:
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/gatling-annotation-report/scripts/generate_annotation_report.ps1" -ScenarioDataPath ".../scenario-data.yaml" -RepliesYamlPaths ".../replies.yaml" -OutputHtmlPath ".../reports/annotation-values-report.html"`
