---
name: gatling-converter
description: Convert Eggplant recordings to Gatling scripts using local workflow-converter jar execution from this skill's scripts folder, auto-build workflow-converter --move-to-global mappings from Eggplant/SQL/reference scenario-data, and then run generated scenarios with gatling-runner. Use when the user asks to generate Gatling from Eggplant recordings, especially for folders under NBS/gatling/recordings and Eggplant scripts under NBS/gatling/Eggplant.
---

# Eggplant Gatling Converter

## Workflow
1. Resolve local `workflow-converter*.jar` from this skill's `scripts` folder (or use explicit `-ConverterJarPath` when provided).
2. Copy each recording folder into a local temp conversion workspace.
3. Before conversion, delete noise folders matching `cernserver-*` and `discernnotify-*` from the local workspace copy, then decide converter input path + `--combine` based on remaining child folders:
   - if remaining child folder count is `> 1`: use parent recording path as `-input` and pass `--combine`
   - if remaining child folder count is `1`: use that single child folder as `-input` (no `--combine`)
   - if no child folders remain but files exist at root: use root as `-input` (no `--combine`)
   - if no content remains: fail fast
4. Run local `workflow-converter` jar from this skill's `scripts` folder (skip Eggplant recording toggles/execution).
   - if trigger overrides include more than one explicit username key (for example `username_a`, `username_b`), do **not** pass converter `-username '${username}'` argument for that run
5. Analyze pass-1 generated `scenario-data.yaml` + `replies*.yaml` to identify/refine params for `--move-to-global`:
   - when users provide explicit identity overrides, accept both `key:value` (user-friendly) and `value:key` (converter-native) formats; always normalize before converter execution so outgoing `--move-to-global` is correct `value:key`
   - when prompt includes `-ProvidedMoveToGlobal`, those prompt-provided keys are **locked highest priority** in pass-2 and must never be overridden by pass-1 extracted values
   - pass-1 extracted identity values are merged into pass-2 and retained for non-conflicting keys; for keys explicitly provided in prompt, prompt values win while pass-1 evidence is still shown in reports
   - detect frequent identity-like params (threshold default: at least 5 occurrences) such as `username_*`, `encntr_id_*`, `person_id_*`, `order_id_*`, `accession_*`, `updt_id_*`
   - never derive identity values from parameter-name numeric suffixes (for example `person_id_29682`, `accession_20758`); resolve values only from `replies*.yaml` expressions or concrete scenario-data literals
   - canonicalize keys (for example `encntr_id_20752` -> `encntr_id`, `accession_20758` -> `accession_nbr`, `updt_id_7` -> `updt_id`) and choose values
   - when user identity appears as `prsnl_id_*`, also derive and emit `user_id` from the same resolved value for `--move-to-global`
   - after resolving the first-pass `username`, run [$sqlplus](C:\Users\prakash\.codex\skills\sqlplus\SKILL.md) against the prompt-selected DB environment (default `ABLFHIR` when not specified) with:
     `SELECT person_id AS user_id FROM PRSNL p WHERE username = '$username'`
   - map SQL result as `user_id:<resolved-person-id>` into `--move-to-global` and keep key name exactly `user_id`
   - when multiple explicit usernames are provided (for example `username_a`, `username_b`), perform SQL lookup for each and add corresponding `user_id_*` mappings (for example `user_id_a`, `user_id_b`) into pass-2 `--move-to-global`
   - in duplicate/conflict resolution, give highest priority to SQL-derived `user_id` over other `user_id` candidates from pass-1 evidence
   - parse generated `scenario-data.yaml` identity params and resolve `${transaction.path}` placeholders using pass-1 `replies*.yaml` actual values
   - for each canonical key, select the most frequent resolved value from pass-1 evidence and merge into the refinement map used for `--move-to-global`
   - run converter pass 1, then re-run converter pass 2 with pass-1 replies-derived `--move-to-global`
   - capture converter console output for both pass-1 and pass-2 runs
   - after pass 2, generate a converter console-log HTML report under `NBS/gatling/reports/conversion-console-log/<scenario>/` (include command, start/end time, exit code, and full console output for each pass)
   - after pass 2, run a username normalization pass with split behavior:
     - `scenario.yaml`: replace leftover literal username values with `${username*}` annotations when converter missed those replacements
     - `scenario-data.yaml`: keep concrete username values (no `${username*}` annotations for username/user params)
   - scenario.yaml replacement must include `username` and `user` fields in request bodies outside `instanceJson` (for example JSON `"... \"username\" : \"ABL_...\" ..."` or `"... \"user\" : \"ABL_...\" ..."`) and work case-insensitively so uppercase DB-style usernames are also mapped
   - do **not** modify `replies*.yaml`; treat replies files as source-of-truth evidence used only for value resolution/reporting
6. Materialize local converter output and runnable scenario folders under:
   - `NBS/gatling/script/generated/<scenario>`
   - `NBS/gatling/script/<scenario>` (runner target)
7. Normalize scenario names to script name format:
   - top-level `name:` and `scenarios: - name:` are set to normalized script name
   - all non-alphanumeric characters are converted to `_` (for example `VA-Printing-Regression-Testing-Script-Lab-P1` -> `VA_PRINTING_REGRESSION_TESTING_SCRIPT_LAB_P1`)
   - remove per-scenario `startUsers` and `endUsers` under `scenarios:` entries in `scenario.yaml`
   - apply same normalized script name to related files where applicable:
     - `replies*.yaml`: top-level `name:` and `replyScenarios: - name:`
     - `scenario-data.yaml`: `scenarioName:` fields only (without changing parameter `- name:` entries)
8. Ensure `scenario-data.yaml` required global values are present:
   - `authority` default: `MillDomain`
   - `password` default: `scale`
   - `username` from first-pass extracted scenario-data values, otherwise Eggplant/derived fallback
   - enforce these keys inside `globalDataSets.params` (never as top-level `authority/username/password` YAML scalars)
9. After conversion (and after pass-2 username normalization), generate a **pre-run YAML audit report** before calling runner:
   - include conversion parameters at the top (recording/scenario, converter jar path, target alias, DB env, timezone, initial/final `--move-to-global`, pass-2 priority overrides, and whether converter `-username '${username}'` was passed or omitted)
   - include both `prompt-provided move-to-global (locked priority)` and `pass-1 extracted move-to-global` in conversion parameters
   - include parsed move-to-global parameter tables (`key`, `value`, and `value:key` pair) for prompt-provided, pass-1 extracted, and final pass-2 mappings
   - include transaction annotation coverage from generated `scenario.yaml`:
     - total transaction count
     - transaction count containing at least one `${...}` annotation
     - transaction count without annotations
   - include `scenario-data.yaml` annotation mapping resolved from `replies*.yaml`:
     - annotation expression (for example `${txn.instanceJson.id}`)
     - parameter name and transaction
     - resolved actual value (or unresolved marker)
   - save report artifact under `NBS/gatling/reports/conversion-yaml-audit/<scenario>/` as HTML
10. Before calling [$gatling-runner](C:\Users\prakash\.codex\skills\gatling-runner\SKILL.md), normalize `scenario.yaml` post bodies:
   - for each transaction, read transaction-level `timestamp:`
   - compare datetime literals inside `postBody` values to transaction `timestamp` using a `+/- 5 seconds` window
   - when datetime is within `+/- 5 seconds`, replace postBody datetime literal with `${current_dt_tm}`
  - when datetime differs by whole-hour offset (`+/- N hour`) within `+/- 5 seconds` tolerance, create/reuse `scenario-data.yaml` global annotation with value format `{currentDateTime N Hour}` for positive offsets and `{currentDateTime -N Hour}` for negative offsets, and replace hardcoded postBody datetime with that annotation
   - special case for `GetAppointmentAvailability_823_0`:
     - target only `instanceJson.list_of_date_range[*].begin_dt_tm` and `instanceJson.list_of_date_range[*].end_dt_tm`
     - replace only the date portion with `${current_dt_plus_<N>_day}` / `${current_dt_minus_<N>_day}` and preserve original static time suffix (for example `${current_dt_plus_16_day}T04:59:00Z`)
     - compute day offset from transaction `timestamp` using UTC-normalized dates
     - create/reuse `scenario-data.yaml` global annotations with value format `{currentDate N Day}` (including `N=0`)
   - add created offset annotations under `globalDataSets.params` in `scenario-data.yaml` (for example `current_dt_tm_plus_2_hour`)
   - generate datetime replacement report listing all replaced annotations with fields: `transName`, `fieldPath`, `timestamp`, `originalDateTime`, `replacement`, `rule`, `dayOffset`, `annotationKey`, `keyStatus` (`created`/`reused`), `deltaSeconds`
   - do not modify transaction-level `timestamp:`
   - this normalization step can be run standalone on existing `scenario.yaml` + `scenario-data.yaml` (without full conversion) for targeted re-annotation and should be idempotent on rerun
11. After conversion, run [$gatling-annotation-report](C:\Users\prakash\.codex\skills\gatling-annotation-report\SKILL.md) to generate annotation value report from `scenario-data.yaml` + `replies*.yaml`:
   - output columns: `index`, `name`, `path`, `actual value`, `count`
   - order by transaction number extracted from path prefix
   - save HTML artifact under `NBS/gatling/reports/annotation-values/<scenario>/`
12. Next step: run the generated script using [$gatling-runner](C:\Users\prakash\.codex\skills\gatling-runner\SKILL.md).
13. Username reliability mode for execution:
   - build prioritized username candidates from recorder evidence first, then Eggplant `millUsername` fallback
   - set generated output default `username` to candidate #1 (recorder-first)
   - run up to 2 Gatling attempts per scenario using top distinct candidates (attempt 1 = highest priority)
   - for each attempt, rewrite `globalDataSets.username` before run and save attempt-specific report/output copies




