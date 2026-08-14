---
name: gatling-fixer
description: Iteratively stabilize Gatling scenarios using causal KO/token remediation first, replies.yaml baseline filtering, row-to-username isolation, and pass-level audit backups; optionally apply strict replies.yaml-based transaction removal only when explicitly needed.
---

# Gatling Script Auto Fixer

Use this skill when the user asks to auto-fix or stabilize a Gatling script after report generation, especially with iterative run/fix cycles.

## Uses
- [$gatling-runner](C:\Users\prakash\.codex\skills\gatling-runner\SKILL.md) to execute scenario runs and regenerate reports.
- Optional integration after [$gatling-converter](C:\Users\prakash\.codex\skills\gatling-converter\SKILL.md) finishes generation.
- Optional [$sqlplus](C:\Users\prakash\.codex\skills\sqlplus\SKILL.md) to build patient/encounter row pools for username-isolated data fixes.

## Inputs
- `ScenarioName` (required)
- `TargetAlias` (default: `ablfhir`)
- `MaxIterations` (default: `20`)
- `FixMode` (guidance mode):
  - `preserve` (default): do not remove/disable transactions; apply causal/token/dataflow fixes.
  - `remove`: allow strict replies.yaml-based removal flow.
- `SkipFailedRepliesRemoval` (optional switch, default: `false`): do not remove transactions even when report marks `Failure in replies.yaml`
- `AutoApproveChanges` (optional switch, default: `false`): when set, apply proposed fixes without interactive confirmation prompts.
- `GenerateFixChangeReport` (optional switch, default: `false`): generate a human-readable HTML report summarizing scenario file changes and run deltas.
- `RemoveAnnotationKey` (optional string): targeted annotation replacement mode. Example: `key_4058`.
- `RemoveAnnotationReportLines` (optional string): targeted annotation replacement by `annotation-values-report.html` line number/range. Examples: `128-165`, `128,131,140-145`.
- Optional data-isolation inputs for appointment/check-in/admission style scripts:
  - `UsernameStart` / `UsernameEnd`
  - `PatientRowsCsv` (columns: `fin_num,person_id,encntr_id`)

## Core Rules
- Keep report generation and KO visibility unchanged.
- Baseline filtering: classify KO that are also KO in `replies.yaml` as baseline/report-only; do not actively remediate those first.
- Causal order: fix root gate transaction first, then downstream dependents.
- Preserve row-to-username isolation: do not mix `fin_num/person_id/encntr_id` across users.
- Prefer token/dataflow/path fixes over hardcoded shared values.
- Transaction removal is an explicit strategy (`FixMode=remove`) and must remain strict.

## Workflow
0. Targeted annotation mode (when `RemoveAnnotationKey` is provided):
   - If `annotation-values-report.html` is available for the scenario, use it first as the source of truth for annotation `name` -> `path` -> `actual value` mapping.
   - If report is not available (or key is missing in report), fall back to parsing `scenario-data.yaml` and resolving the path from `replies.yaml`.
   - Find the matching annotation `name` entry (for example `key_4058`) and its path/actual value.
   - Replace only that annotation reference in `scenario.yaml` with the resolved actual value.
   - Remove only that annotation entry from `scenario-data.yaml` for the matching transaction.
   - After removing the annotation entry, check the matching transaction block in `scenario-data.yaml` (for example `- transName: "GetRegistrationActionsByKeys_137_0"`). If `dataSets[].params` has no remaining annotation parameters, remove that empty transaction block.
   - Do not modify any other transaction, annotation, or file content.
   - Generate/update report evidence for this targeted change and stop (do not run broader auto-fix/removal loop unless explicitly requested).
0.a Targeted annotation-by-line mode (when `RemoveAnnotationReportLines` is provided):
   - Read `annotation-values-report.html` and select only annotations from the requested line numbers/ranges.
   - For each selected row, use `name` and `actual value` from the report.
   - Replace only matching `${name}` annotations in `scenario.yaml` with that row `actual value`.
   - Remove only matching `name` entries from `scenario-data.yaml` for affected transactions.
   - After annotation removal, remove any transaction block that has no remaining annotation params in `dataSets[].params`.
   - Do not modify any other transaction, annotation, or file content.
   - Generate/update `annotation-values-report.html` after changes and stop (do not run broader auto-fix/removal loop unless explicitly requested).

1. Baseline inventory pass:
   - Run the scenario via `gatling-runner`.
   - Create/use scenario report folder `C:/Users/prakash/Desktop/project/NBS/gatling/reports/<ScenarioName>/` (if already exists, reuse it).
   - Parse latest timestamped runner report files from `C:/Users/prakash/Desktop/project/NBS/gatling/reports/<ScenarioName>/`:
   - `<ScenarioName>-*.html`
   - `<ScenarioName>-*.out`
   (fallback to legacy `<ScenarioName>.html` only if needed).
   - Classify failures into:
     - Actionable KO (runtime KO + not KO in `replies.yaml`)
     - Baseline KO (runtime KO + KO in `replies.yaml`, report-only)
     - Failed build request
     - status `0` / `Not S` trackers
2. Build a proposed fix plan first and present it to the user (transactions to remove/update + reason + files impacted).
3. Confirmation behavior before edits:
   - By default, ask for explicit confirmation before making any file change.
   - If `AutoApproveChanges` is set, skip confirmation and apply the approved fix plan directly.
   - Do not edit `scenario.yaml` / `scenario-data.yaml` until one of the above conditions is met.
4. Backup before each edit pass:
   - Create: `C:/Users/prakash/Desktop/project/NBS/gatling/reports/<ScenarioName>/fix-backups/<yyyyMMdd-HHmmss>/`
   - Copy before edits:
     - `scenario.yaml`
     - `scenario-data.yaml`
     - latest `*.html`
     - latest `*.out`
   - Keep per-iteration backups: `<file>.autofix.v<iteration>-<yyyyMMdd-HHmmss>.bak`
5. Annotation/token-first loop (mandatory for `Failed to build request` with unresolved `${...}`):
   - Parse missing token expressions from the latest `.out`/`.html` output (for example `${GetDynamicRoles_880_0.instanceJson.resource_lists[309].roles[0].resources[18].personnel_id}`).
   - Resolve actual token value from `replies.yaml` using the exact source transaction + JSON path.
   - Build dependency/topological order from source-token -> target transaction.
   - Pick the lowest-numbered failed target transaction first when order is otherwise equal (e.g. `..._883_0` before `..._887_0`).
   - Replace the unresolved annotation in `scenario-data.yaml` / `scenario.yaml` with the resolved value.
   - Apply only one transaction fix per iteration, then run via `gatling-runner` immediately and evaluate the new `.out`/`.html` report.
   - Repeat with the next lowest-numbered unresolved annotation from the new report until annotation issues are resolved or no resolvable values remain.
6. If a missing token cannot be resolved from replies evidence, keep it unchanged and record it as unresolved with reason.
7. Root-gate and lock/version discipline (mandatory):
   - Identify root gate transaction (for affected families often `AdmitEncounter_*`) and resolve it before dependent transactions.
   - If report/out indicates `LOCKED` (for example `status: Z` with lock message), ensure `scenario-data.yaml` `globalDataSets.params` includes `appinfo`.
   - If `appinfo` is missing for a dataset row and `user_id` exists, auto-add `appinfo` generated from a template payload with embedded `UPDT_ID` updated to that row `user_id`.
   - Ensure encounter/version fields are sourced consistently per user/row lifecycle.
   - Apply these fixes before any removal strategy and rerun.
7.a CCL mpage payload typing + appinfo alignment (mandatory when failures show CCL type mismatch):
   - If report/out includes errors like `Assignment of Report expression (...) to incompatible type` for mpage scripts (`CCL_RUN_MPAGE`, `MP_*`, `mp_*`), treat as request payload typing issue first.
   - In `scenario.yaml`, for impacted transaction `instanceJson.blob_in.^base64_encode` payloads, convert numeric business fields from quoted annotations to numeric annotations:
     - `"USERID" : "${user_id}"` -> `"USERID" : ${user_id}`
     - `"POSITIONCD" : "${role_id_7759}"` -> `"POSITIONCD" : ${role_id_7759}`
     - `"PERSONID" : "${person_id}"` -> `"PERSONID" : ${person_id}`
     - `"ENCOUNTERID" : "${encntr_id}"` -> `"ENCOUNTERID" : ${encntr_id}`
     - `"encounter_id" : "${encntr_id}"` -> `"encounter_id" : ${encntr_id}`
     - `"position_code" : "${role_id_7759}"` -> `"position_code" : ${role_id_7759}`
   - Ensure `crmInstanceJson.encrypted.appinfo` is aligned to the active row `user_id` for impacted transactions; use the same user-id-embedded appinfo pattern consistently across related requests in the same flow.
   - Rerun immediately after this typing/appinfo correction before considering any removal.
8. Username/row isolation strategy (when applicable):
   - If `PatientRowsCsv` is provided, map rows sequentially to usernames sequentially.
   - Use first N rows needed for active users while preserving row order.
   - Never cross-wire person/encounter/fin among users.
8.a First-N row validation option (recommended for quick stabilization):
   - When dataset is small or user requests narrow validation, run a focused pass with first N records (commonly first 8 rows) before full-scale reruns.
   - Keep username-to-row mapping stable and deterministic during this pass.
   - After fixes are validated on first N rows, expand back to requested scale tiers.
9. Scale-tier execution strategy (when applicable):
   - Tier 1: 1 user -> stabilize
   - Tier 2: 5 users -> stabilize
   - Tier 3: 10 users (or requested scale) -> stabilize
10. Strict removal rule (only when `FixMode=remove` and not skipped):
   - Remove a transaction from `scenario.yaml` only when that same transaction is explicitly marked `Failure in replies.yaml` in the report.
   - If `SkipFailedRepliesRemoval` is set, the fixer reports candidates but does not remove them.
11. Do not remove transactions for request build/token failures alone unless token/dataflow replacement was attempted and no safe resolution is available.
12. Record all edits and reasons in `C:/Users/prakash/Desktop/project/NBS/gatling/reports/<ScenarioName>/<ScenarioName>-autofix-report.html`.
12.a Optional change-summary report (`GenerateFixChangeReport`):
   - Generate `C:/Users/prakash/Desktop/project/NBS/gatling/reports/<ScenarioName>/<ScenarioName>-fix-change-report-<yyyyMMdd-HHmm>.html`.
   - Include:
     - before/after request/OK/KO summary (latest successful baseline vs latest run)
     - transactions fixed in the current pass
     - exact `scenario.yaml` and `scenario-data.yaml` modifications (field-level summary with line references where possible)
     - remaining KO list after the pass
   - Do not replace `-autofix-report.html`; publish this as an additional user-facing summary artifact.
13. If any annotation was added/removed/replaced by fixer logic (in `scenario.yaml` or `scenario-data.yaml`), regenerate annotation report using [$gatling-annotation-report](C:\Users\prakash\.codex\skills\gatling-annotation-report\SKILL.md):
   - Generate/update `C:/Users/prakash/Desktop/project/NBS/gatling/reports/<ScenarioName>/annotation-values-report.html`.
   - Use updated `scenario-data.yaml` and scenario `replies*.yaml` as inputs.
14. Re-run and repeat until stop criteria:
   - Actionable KO = 0
   - Failed to build request = 0
   - or no new safe edits found / max iterations reached
   - Baseline KO may remain and should stay reported.

## Run
Recommended launcher:
`pwsh -NoProfile -Command "& 'C:/Users/prakash/.codex/skills/gatling-fixer/scripts/run_skill_script.ps1' -ScriptName 'run_gatling_script_auto_fix.ps1' -- -ScenarioName '<scenario-name>' -TargetAlias 'ablfhir' -MaxIterations 20"`

Direct script:
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/gatling-fixer/scripts/run_gatling_script_auto_fix.ps1" -ScenarioName "<scenario-name>" -TargetAlias "ablfhir" -MaxIterations 20`

Direct script (skip confirmation prompts):
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/gatling-fixer/scripts/run_gatling_script_auto_fix.ps1" -ScenarioName "<scenario-name>" -TargetAlias "ablfhir" -MaxIterations 20 -AutoApproveChanges`

Direct script (no removals):
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/gatling-fixer/scripts/run_gatling_script_auto_fix.ps1" -ScenarioName "<scenario-name>" -TargetAlias "ablfhir" -MaxIterations 20 -SkipFailedRepliesRemoval`

Direct script (no removals + change summary report):
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/gatling-fixer/scripts/run_gatling_script_auto_fix.ps1" -ScenarioName "<scenario-name>" -TargetAlias "ablfhir" -MaxIterations 20 -SkipFailedRepliesRemoval -GenerateFixChangeReport`

## Notes

## Foreground Default
- Default execution mode is foreground (direct mode).
- Use background/monitored mode only when the user explicitly asks to run in background.
- If the user does not explicitly request background execution, do not start background jobs.

- Creates one-time backup: `scenario.yaml.autofix.bak`.
- Creates per-iteration backups for all `scenario*.yaml` files: `.autofix.v<iteration>-<yyyyMMdd-HHmmss>.bak`.
- Default strategy is preserve-and-fix (non-removal) with causal token/dataflow remediation.
- Strict replies.yaml-failure matching is required for removals when removal strategy is explicitly chosen.
- Emits a clear report of each iteration, run status, removed transactions, and stop reason.
- When `GenerateFixChangeReport` is enabled, also emits a user-facing HTML delta report for `scenario.yaml` / `scenario-data.yaml` and KO trend summary.
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

- Proven fix profile for OCONUS Ambulatory Intake / mpage interop transactions:
  - Prioritize CCL type mismatch remediation (`blob_in` numeric typing) before status-code checker tuning.
  - Keep `appinfo` and `blob_in` user context synchronized with the same active row (`user_id`, `person_id`, `encntr_id`, `role_id_7759`).
  - Validate target transactions explicitly after rerun (for example `MP_GET_ENDORSE_CNT_*`, `MP_GET_PATHWAY_NOTIFICATIONS_*`, `mp_get_Interop_View_Pref_*`) and confirm transition from `OK=0 KO=1` to `OK=1 KO=0`.
  - Preserve non-target KO for separate passes; do not broaden edits when targeted transactions are already fixed.

- Suggested SQL pattern for patient pool preparation (when needed):
```sql
SELECT ea.ALIAS as fin_num, p.PERSON_ID, e.ENCNTR_ID, p.NAME_FULL_FORMATTED
FROM person p
JOIN encounter e ON p.PERSON_ID = e.PERSON_ID AND e.ENCNTR_TYPE_CD = 19962609
JOIN ENCNTR_ALIAS ea ON e.ENCNTR_ID = ea.ENCNTR_ID AND ea.ENCNTR_ALIAS_TYPE_CD IN (1077)
WHERE p.NAME_LAST like 'OCONUSAmbPatientIntakePtOne'
ORDER BY p.PERSON_ID
```




