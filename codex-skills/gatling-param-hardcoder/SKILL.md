---
name: gatling-param-hardcoder
description: Build or update a parameter CSV for Gatling scenario data and resolve hardcoded values from replies.yaml. Use when the user asks to extract param name/value pairs, add a value1 column, or replace ${transaction.path} placeholders with actual values from replies.yaml.
---

# Gatling Param Hardcoder

## Workflow
1. Read `scenario-data.yaml` and collect `params` entries (`name`, `value`).
2. Create or update CSV with columns:
   - `name`
   - `value`
   - `value1`
3. Resolve `value1` from `replies.yaml` by parsing `${TransName.path.to.field[index]}` expressions from the `value` column.
4. Keep unresolved rows with empty `value1` so gaps are visible.

## Inputs
- `ScenarioPath` (required for extract mode)
- `RepliesPath` (required for resolve mode)
- `OutCsvPath` (required)
- `InCsvPath` (optional; when present, update existing CSV instead of extracting from scenario)
- `Unique` (optional; remove duplicate `name+value` rows in extract mode)

## Run
Create CSV from scenario and resolve value1 from replies:

```powershell
pwsh -NoProfile -Command "& '<skill>/scripts/run_skill_script.ps1' -ScriptName 'run_gatling_param_hardcoder.ps1' -- -ScenarioPath 'C:/path/scenario-data.yaml' -RepliesPath 'C:/path/replies.yaml' -OutCsvPath 'C:/path/param_values.csv' -Unique"
```

Update an existing CSV and only resolve `value1`:

```powershell
pwsh -NoProfile -Command "& '<skill>/scripts/run_skill_script.ps1' -ScriptName 'run_gatling_param_hardcoder.ps1' -- -InCsvPath 'C:/path/param_values.csv' -RepliesPath 'C:/path/replies.yaml' -OutCsvPath 'C:/path/param_values.csv'"
```

Direct script call:

```powershell
pwsh -NoProfile -File "<skill>/scripts/run_gatling_param_hardcoder.ps1" -ScenarioPath "C:/path/scenario-data.yaml" -RepliesPath "C:/path/replies.yaml" -OutCsvPath "C:/path/param_values.csv" -Unique
```

## Notes
- Parse only transaction blocks needed for expressions found in CSV values.
- Keep `value` column unchanged; write resolved concrete value to `value1`.
- Use this skill for CSV extraction/resolution tasks, not for full scenario auto-fix.
