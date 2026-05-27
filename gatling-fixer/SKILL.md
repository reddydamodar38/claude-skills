---
name: gatling-fixer
description: Iteratively fix Gatling scenario scripts by running gatling-runner, removing failed transactions from scenario.yaml (starting with replies.yaml failures), applying additional safe removals from report evidence, and producing a change report for every pass.
---

# Gatling Script Auto Fixer

Use this skill when the user asks to auto-fix a Gatling script after report generation, especially with iterative run/fix cycles.

## Uses
- [$gatling-runner](C:\Users\prakash\.codex\skills\gatling-runner\SKILL.md) to execute scenario runs and regenerate reports.
- Optional integration after [$gatling-converter](C:\Users\prakash\.codex\skills\gatling-converter\SKILL.md) finishes generation.

## Inputs
- `ScenarioName` (required)
- `TargetAlias` (default: `ablfhir`)
- `MaxIterations` (default: `20`)
- `SkipFailedRepliesRemoval` (optional switch, default: `false`): do not remove transactions even when report marks `Failure in replies.yaml`
- `AutoApproveChanges` (optional switch, default: `false`): when set, apply proposed fixes without interactive confirmation prompts.

## Workflow
1. Run the scenario via `gatling-runner`.
2. Create/use scenario report folder `C:/Users/prakash/Desktop/project/NBS/gatling/reports/<ScenarioName>/` (if already exists, reuse it).
3. Parse latest timestamped runner report files from `C:/Users/prakash/Desktop/project/NBS/gatling/reports/<ScenarioName>/`:
   - `<ScenarioName>-*.html`
   - `<ScenarioName>-*.out`
   (fallback to legacy `<ScenarioName>.html` only if needed).
4. Build a proposed fix plan first and present it to the user (transactions to remove/update + reason + files impacted).
5. Confirmation behavior before edits:
   - By default, ask for explicit confirmation before making any file change.
   - If `AutoApproveChanges` is set, skip confirmation and apply the approved fix plan directly.
   - Do not edit `scenario.yaml` / `scenario-data.yaml` until one of the above conditions is met.
6. Annotation-first fix loop (mandatory for `Failed to build request` with unresolved `${...}`):
   - Parse missing token expressions from the latest `.out`/`.html` output (for example `${GetDynamicRoles_880_0.instanceJson.resource_lists[309].roles[0].resources[18].personnel_id}`).
   - Resolve actual token value from `replies.yaml` using the exact source transaction + JSON path.
   - Pick the lowest-numbered failed target transaction first (the smaller transaction number in name, e.g. `..._883_0` before `..._887_0`).
   - Replace the unresolved annotation in `scenario-data.yaml` / `scenario.yaml` with the resolved value.
   - Apply only one transaction fix per iteration, then run via `gatling-runner` immediately and evaluate the new `.out`/`.html` report.
   - Repeat with the next lowest-numbered unresolved annotation from the new report until annotation issues are resolved or no resolvable values remain.
7. If a missing token cannot be resolved from replies evidence, keep it unchanged and record it as unresolved with reason.
8. Strict removal rule (mandatory): remove a transaction from `scenario.yaml` only when that same transaction is explicitly marked `Failure in replies.yaml` in the report.
   - If `SkipFailedRepliesRemoval` is set, the fixer reports candidates but does not remove them.
9. Do not remove transactions for request build/token failures alone unless annotation-first replacement was attempted and no safe resolution is available.
10. On every iteration, create backups before any edit is applied.
   - Minimum required: `scenario.yaml` and `scenario-data.yaml` (plus any other script file being edited in that iteration).
   - Backup naming: `<file>.autofix.v<iteration>-<yyyyMMdd-HHmmss>.bak`
11. Record all edits and reasons in `C:/Users/prakash/Desktop/project/NBS/gatling/reports/<ScenarioName>/<ScenarioName>-autofix-report.html`.
12. Re-run and repeat until no new safe edits are found or max iterations is reached.
## Run
Recommended launcher:
`pwsh -NoProfile -Command "& 'C:/Users/prakash/.codex/skills/gatling-fixer/scripts/run_skill_script.ps1' -ScriptName 'run_gatling_script_auto_fix.ps1' -- -ScenarioName '<scenario-name>' -TargetAlias 'ablfhir' -MaxIterations 20"`

Direct script:
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/gatling-fixer/scripts/run_gatling_script_auto_fix.ps1" -ScenarioName "<scenario-name>" -TargetAlias "ablfhir" -MaxIterations 20`

Direct script (skip confirmation prompts):
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/gatling-fixer/scripts/run_gatling_script_auto_fix.ps1" -ScenarioName "<scenario-name>" -TargetAlias "ablfhir" -MaxIterations 20 -AutoApproveChanges`

Direct script (no removals):
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/gatling-fixer/scripts/run_gatling_script_auto_fix.ps1" -ScenarioName "<scenario-name>" -TargetAlias "ablfhir" -MaxIterations 20 -SkipFailedRepliesRemoval`

## Notes

## Foreground Default
- Default execution mode is foreground (direct mode).
- Use background/monitored mode only when the user explicitly asks to run in background.
- If the user does not explicitly request background execution, do not start background jobs.

- Creates one-time backup: `scenario.yaml.autofix.bak`.
- Creates per-iteration backups for all `scenario*.yaml` files: `.autofix.v<iteration>-<yyyyMMdd-HHmmss>.bak`.
- Uses conservative removal-only edits to avoid risky payload rewrites; strict replies.yaml-failure matching is required for removals.
- Emits a clear report of each iteration, run status, removed transactions, and stop reason.
- Default behavior asks before edits; pass `-AutoApproveChanges` to skip confirmation prompts.
- Annotation-first strategy:
  - Resolve and replace missing `${...}` tokens from replies evidence before considering removals.
  - Process lowest-numbered failed transaction first, one replacement per run cycle, then re-evaluate.
  - Example: for `GetAppointmentAvailability_883_0` missing `${GetDynamicRoles_880_0.instanceJson.resource_lists[309].roles[0].resources[18].personnel_id}`, replace with resolved value (for example `4495108`), rerun, then continue with the next lowest failed transaction.
- Report layout policy: keep all scenario-specific reports/artifacts in `C:/Users/prakash/Desktop/project/NBS/gatling/reports/<ScenarioName>/` (reuse folder if present).
- Suggestion for `mic_act_acd_result_*` task-id issues:
  - If failures point to `dtask_id`/`doldtask_id` mismatch (or hardcoded task ids), prefer dynamic mapping from the preceding `mic_get_new_id_*` response.
  - In `scenario-data.yaml`, add a parameter like `dnew_id_<token>` with value `${mic_get_new_id_<n>_<m>.instanceJson.qual[0].dnew_id}`.
  - In `scenario.yaml`, replace hardcoded task id values in the related `mic_act_acd_result_*` request with `${dnew_id_<token>}` (for example `mic_get_new_id_254_1 -> dnew_id_622954 -> mic_act_acd_result_255_1.tasks[0].dtask_id`).
  - Re-run once after this mapping fix before considering transaction removal.
- Suggestion for single-item `patienttrackinglist` responses from `GetPatientTrackingApptListByCriteria_*`:
  - If failures show missing paths like `patienttrackinglist[1]`, `[4]`, `[5]`, `[6]`, treat the response as a single-item list.
  - Normalize references to `${GetPatientTrackingApptListByCriteria_<n>_<m>.instanceJson.patienttrackinglist[*]...}` by forcing index `[0]` in `scenario-data.yaml` (and `scenario.yaml` if present).
  - Fix logic now includes this normalization before iteration runs, then proceeds with normal replies.yaml-based removal flow.




