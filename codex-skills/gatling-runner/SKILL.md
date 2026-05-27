---
name: gatling-runner
description: Run a Gatling scenario from local YAML files against a remote Linux host over SSH, including file copy, token replacement, execution, output analysis, and HTML report export. Use when the user asks to run prompts like `run VA-PhysicianDocumentation-HomeMedication-Comp` or any `run <scenario-name>` Gatling remote execution workflow, including prompts like `on ablfhir`.
---

# Gatling Remote Runner

## Inputs
- scenario name (for example: `VA-PhysicianDocumentation-HomeMedication-Comp`)
- or multiple scenario names (batch mode)
- target alias (supported: `ablfhir`) or explicit host/user/auth
- auth mode: either SSH key path (`-KeyPath`) or password (`-Password` / `GATLING_SSH_PASSWORD`)

## Alias Mapping
- `ablfhir` resolves to:
- `HostName = 10.191.200.22`
- `UserName = root`
- `KeyPath = C:/Users/prakash/.ssh/id_gatling`

## Workflow
1. Resolve scenario folder from `C:/Users/prakash/Desktop/project/NBS/gatling/script/<scenario-name>`.
2. Stage `config.yaml`, `scenario.yaml`, and `scenario-data.yaml`, then compress them into a single `tar.gz` for transfer.
3. Replace `MillDomain` with `ablfhir` in `config.yaml` and `scenario-data.yaml` before upload.
   - Set `verboseLogging` in `config.yaml` from `-VerboseLogging`.
   - Default behavior: if run is for more than 1 user (`startUsers > 1` or `endUsers > 1`), `verboseLogging` defaults to `false` unless explicitly requested otherwise with `-VerboseLogging:$true`.
   - Single-user default remains `true` unless overridden.
   - Force `authority: ablfhir` in both `config.yaml` and `scenario-data.yaml`.
   - Force `password: c0630system` in `config.yaml`.
   - Force `password: scale` in `scenario-data.yaml`.
4. Set `scenario.yaml` values before upload from run arguments:
`durationSeconds` from `-DurationSeconds` (default `1`)
`rampDurationSeconds` from `-RampDurationSeconds` (default `0`)
`startUsers` from `-StartUsers` (default `1`)
`endUsers` from `-EndUsers` (default `1`)
   - when `-UsernameOverride` is used and `user_id` is resolved from DB, update `scenario-data.yaml` `user_id` and, if `appinfo` exists, update only the embedded `UPDT_ID` bytes inside base64 `appinfo` (byte-preserving; no other bytes changed)
5. Create a unique remote temp folder under `/root/gatling/templ-<id>`, upload one compressed archive, extract remotely, and remove temp artifacts after run completion.
6. Execute:
`java -jar gatling-crank-executor.jar ./testrun ./report false 0 > gatling.testrun.out`
7. Wait for completion, download `/root/gatling/gatling.templ-<id>.out`.
8. Parse failed transactions and exception/error lines.
9. Create/use scenario report folder `C:/Users/prakash/Desktop/project/NBS/gatling/reports/<scenario-name>/` (if already exists, reuse it).
10. Generate local HTML report in `C:/Users/prakash/Desktop/project/NBS/gatling/reports/<scenario-name>/<scenario-name>-<yyyyMMddHHmmss>.html` (timestamp is current local date-time in numeric format only):
   - Search reply files recursively under the scenario folder with names matching `replies*.yaml` (prefer files under `Results/`)
   - Add a `Failed Transaction Counts by Type` summary section above the `Failed Transactions` table, including total failed transactions grouped by failure type (for example `KO`, `Failed to build request`, `Failure in replies.yaml`, and other parsed error categories)
   - Report policy: suppress `response status 0` in report output (do not include it as a failure category and do not display `0` in the `Response Status` column)
   - Summary table includes `Transaction`, `KO / Error`, `replies.yaml`, and `Recommendation`
   - Sort failed transactions by transaction number in ascending order by default (applies to summary table and per-transaction detail sections)
   - `replies.yaml` summary column includes both status and matched reply file name (for example: `Failure in replies.yaml (replies_PhysDoc.yaml)`)
   - Includes KO entries (`KO > 0`) from Requests and error entries from Errors section (including wrapped multi-line `Failed to build request` rows from `.out` logs)
   - Transaction name is clickable and jumps to a detailed section for that transaction
   - Detail section computes a transaction window (`start/end`) from transaction-specific replacement markers and the next transaction boundary
   - Detail section includes line-numbered Transaction Window and Failure Trace expandable blocks tied to that window
   - Add a visible separator line after each transaction detail section
   - Detail section includes expandable/collapsible `Request JSON` and `Response JSON` blocks extracted from within the transaction window (`final body` + `Request failed, reply body`) with source line numbers
   - Detail section includes `replies.yaml` status, matched reply file name, and expandable `replies.yaml Response Body` for the transaction when found
   - For `Failed to build request` errors, detect missing token expressions (`${...}`), resolve the source transaction from the token path, and add a dependency subsection with:
     - missing token and error line
     - source transaction request/response from the log
     - source transaction replies file status + replies response body
     - exact dependency parameter path and extracted parameter value from replies.yaml
   - Dependency request/response extraction must scan the full `.out` log (not only the failing transaction window):
     - find source transaction request from `HttpHelper` lines (`[<source_transaction>] ... final body:`) and capture full JSON block even when it starts much earlier in the log
     - find source transaction response from `SimulationProcessor - Body:` for the same source transaction window, including very long single-line JSON
     - support wrapped/multi-line log entries and preserve exact source line numbers in report (start line for request block, start line for response block)
     - when parser cannot infer request/response in the local window, fallback to global search by source transaction id/name (for example `GetDynamicRoles_880_0`) before reporting "not parseable"
     - if response JSON is too large for inline view, still show a compact preview and provide expandable raw block with original line reference
   - Summary `replies.yaml` column also appends extracted dependency parameter value when available (for quick triage)
   - Detail section includes a per-transaction recommendation generated from failure type plus request/response evidence
   - Save raw output copy to `C:/Users/prakash/Desktop/project/NBS/gatling/reports/<scenario-name>/<scenario-name>-<yyyyMMddHHmmss>.out` for full-range troubleshooting
11. Batch mode (multiple scenarios):
   - Run scenarios one by one using `run_gatling_remote.ps1`
   - After all runs, generate combined report:
     `C:/Users/prakash/Desktop/project/NBS/gatling/reports/Gatling-Combined-Summary.html`
   - Combined report includes links to each scenario report and a consolidated summary table

## Run Script
Alias mode (`ablfhir`):
`pwsh C:/Users/prakash/.codex/skills/gatling-runner/scripts/run_gatling_remote.ps1 -ScenarioName <scenario-name> -TargetAlias ablfhir`

10-user example:
`pwsh C:/Users/prakash/.codex/skills/gatling-runner/scripts/run_gatling_remote.ps1 -ScenarioName <scenario-name> -TargetAlias ablfhir -StartUsers 1 -EndUsers 10 -VerboseLogging:$false`

Report-only from existing `.out` (no remote run):
`pwsh C:/Users/prakash/.codex/skills/gatling-runner/scripts/run_gatling_remote.ps1 -ScenarioName <scenario-name> -ReportOnlyOutPath "C:/Users/prakash/Desktop/project/NBS/gatling/reports/<scenario-name>/<scenario-name>-<timestamp>.out"`

Report parser backend selection:
`pwsh C:/Users/prakash/.codex/skills/gatling-runner/scripts/run_gatling_remote.ps1 -ScenarioName <scenario-name> -ReportOnlyOutPath "<out-file>" -ReportParserEngine auto`

Explicit SSH key auth:
`pwsh C:/Users/prakash/.codex/skills/gatling-runner/scripts/run_gatling_remote.ps1 -ScenarioName <scenario-name> -KeyPath "C:/Users/prakash/.ssh/id_gatling" -HostName 10.191.200.22 -UserName root`

Password auth:
`pwsh C:/Users/prakash/.codex/skills/gatling-runner/scripts/run_gatling_remote.ps1 -ScenarioName <scenario-name> -Password "<password>"`

Batch mode (alias):
`pwsh -NoProfile -Command "& 'C:/Users/prakash/.codex/skills/gatling-runner/scripts/run_gatling_remote_batch.ps1' -ScenarioNames @('<scenario1>','<scenario2>','<scenario3>') -TargetAlias ablfhir"`

Batch mode (explicit key):
`pwsh -NoProfile -Command "& 'C:/Users/prakash/.codex/skills/gatling-runner/scripts/run_gatling_remote_batch.ps1' -ScenarioNames @('<scenario1>','<scenario2>') -KeyPath 'C:/Users/prakash/.ssh/id_gatling' -HostName 10.191.200.22 -UserName root"`

Unified launcher (recommended for non-interactive approvals):
`pwsh -NoProfile -Command "& 'C:/Users/prakash/.codex/skills/gatling-runner/scripts/run_skill_script.ps1' -ScriptName '<script>.ps1' -- <script-args>"`

Examples with unified launcher:
- Single scenario:
`pwsh -NoProfile -Command "& 'C:/Users/prakash/.codex/skills/gatling-runner/scripts/run_skill_script.ps1' -ScriptName 'run_gatling_remote.ps1' -- -ScenarioName 'VA-PhysicianDocumentation-HomeMedication-Comp' -TargetAlias 'ablfhir'"`
- Batch:
`pwsh -NoProfile -Command "& 'C:/Users/prakash/.codex/skills/gatling-runner/scripts/run_skill_script.ps1' -ScriptName 'run_gatling_remote_batch.ps1' -- -ScenarioNames @('SCENARIO_1','SCENARIO_2') -TargetAlias 'ablfhir'"`
- Combined summary only:
`pwsh -NoProfile -Command "& 'C:/Users/prakash/.codex/skills/gatling-runner/scripts/run_skill_script.ps1' -ScriptName 'build_gatling_combined_summary.ps1' -- -ScenarioNames @('SCENARIO_1','SCENARIO_2') -OutputFileName 'Gatling-Combined-Summary.html'"`

## Notes

## Foreground Default
- Default execution mode is foreground (direct mode).
- Use background/monitored mode only when the user explicitly asks to run in background.
- If the user does not explicitly request background execution, do not start background jobs.

- Requires OpenSSH (ssh/scp) for key mode.
- If SSH key path access is denied for C:/Users/prakash/.ssh/id_gatling in sandboxed runs, rerun the same command with elevated permissions so the runner process can read the key file.
- Requires `Posh-SSH` module for password mode.
- Uses `tar` for local archive creation and remote extraction to reduce transfer overhead.
- Use only one auth mode at a time: `-KeyPath` or password.
- Default remote paths are `/root/gatling/testrun`, `/root/gatling/report`, and `/root/gatling/gatling.testrun.out`.
- If the user prompt says `on ablfhir`, call the script with `-TargetAlias ablfhir`.
- If the user asks to run for `N` users, populate `N` rows in `scenario-data.yaml` `globalDataSets` and run with `-EndUsers N` (and `-StartUsers 1` unless user says otherwise).
- The runner enforces `authority=ablfhir` in staged YAML files before remote execution.
- For `ablfhir`, the runner enforces `password=c0630system` in staged `config.yaml`.
- The runner enforces `password=scale` in staged `scenario-data.yaml`.
- Report layout policy: all per-scenario reports/artifacts must be written under `C:/Users/prakash/Desktop/project/NBS/gatling/reports/<scenario-name>/` (reuse folder if present).
- Report/log naming policy: per-run HTML report and `.out` log filenames must include current local timestamp in numeric format only (`yyyyMMddHHmmss`).
- Dependency evidence policy: for missing-token failures, prioritize source transaction request/response extraction from anywhere in the log (for example source request around line `98428` and response around line `413874`) rather than only nearby lines.
- Report parser engine policy:
  - `-ReportParserEngine auto` (default): try Python fast parser first, fallback to PowerShell parser on failure.
  - `-ReportParserEngine python`: require Python parser (fail if unavailable).
  - `-ReportParserEngine powershell`: force legacy PowerShell parser.
  - Fast parser writes a sidecar cache `<out>.report-index.json` keyed by out-file path/size/mtime; report HTML content remains the same.
- Execution policy for this skill: start/continue execution immediately without skill-level confirmation prompts.
- Prefer the unified launcher `run_skill_script.ps1` so one approved command pattern can cover current and newly-added scripts in this skill.
- If the platform requires a first-time prefix approval, approve once and reuse the same launcher pattern for future non-interactive runs.








