---
name: CleanPlant
description: Convert VA National Baseline Suite Eggplant workflows from functional scripts into non-functional, scale-oriented scripts. Use when Codex should remove legacy launch scaffolding, recording artifacts, and verification-only logic, standardize storefront launch, exit, and recovery patterns, and sync DataLoader hardcoded values into the matching Resources CSV files.
---

# CleanPlant

Use this skill when converting a VA NBS Eggplant workflow from a functional script into a non-functional, data-driven baseline script.

## What "non-functional" means here

For this suite, the conversion usually means:

- remove environment-specific functional-test scaffolding
- keep workflow-driving actions but remove validation-only checks
- replace direct login with the storefront Citrix launch pattern
- standardize exit and recovery behavior for stable scale runs
- move credentials, FINs, workflow inputs, and Citrix shortcuts into the matching CSV files

Read [references/nbs-nonfunctional-checklist.md](references/nbs-nonfunctional-checklist.md) at the start of the task and use it as the working checklist.

## Mode Selection

Use either flag form or phrase form when choosing execution mode:

- Fast Mode: `-f` or `"fast"`
- Normal Mode: `-n` or `"normal"`
- Dry Run: `-d` or `"dry"`

If no mode is provided, run Normal Mode by default.

Dry Run behavior:

- do not edit files during the dry run
- provide a detailed, file-by-file summary of the exact changes that would be made
- after presenting the dry-run plan, explicitly ask whether to apply the changes
- only apply edits after the user confirms

Dry Run mode decision tree:

- `-d fast`, `-df`, or `"dry fast"` -> run a dry run of Fast Mode
- `-d`, `-dn`, `-d normal`, or `"dry"` -> run a dry run of Normal Mode (default)

Verification execution policy:

- Fast and Normal edit runs must always execute validator plus the required one-command post-check, then run the final validator re-check gate before completion.
- Dry Run must never execute validator, linting, or post-check commands; it must only describe those checks in the plan/output.
- Fast and Normal edit runs must use surgical in-place edits only; do not replace/retype large compliant blocks when targeted line edits are sufficient.

## Mode-wide hardening gates (apply to Fast, Normal, and Dry Run)

- `citrixApp`/`citrixApp*` protection gate: do not remove/comment `citrixApp` or `citrixApp*` until DH2 and FEDA `citrixShortcut`/`citrixShortcut*` values are resolved, then remove only after validator and post-check gates are clean.
- Rename safety gate: rename workflow files only when discovered references can be updated safely in the same change; otherwise keep current filenames and record rename as follow-up.
- CSV naming gate: enforce canonical workflow CSV names using exact wfName (Resources/<wfName>_LoginData.csv, Resources/<wfName>_WorkflowData.csv). Do not use `*_SutUsers.csv` for SUT credentials.
- CSV auto-rename gate: if only legacy/mismatched workflow CSV names exist for the same workflow, rename them to canonical names before any CSV read/write sync step.
- CSV collision gate: if both canonical and legacy/mismatched CSV sets exist, keep canonical files as source-of-truth, auto-rename/move legacy files to canonical only when canonical is absent, and report conflicts instead of silently overwriting canonical data.
- Post-check interpretation gate: treat regex leftovers as heuristic; confirm active executable context before deleting/replacing matched lines.
- `LogError` handling gate: never blanket-delete `LogError`; review and keep `LogError(...)` used for catch, recovery, or active failure diagnostics.
- Data integrity gate: require DataLoader syntax/structure checks and CSV integrity checks as completion criteria for edit modes; in Dry Run, include these checks in the proposed execution plan and expected outcomes before asking to apply edits.
- Secondary-user handoff gate: always run a dedicated check for secondary Millennium login paths (`millUsername2` or higher). If a secondary login exists and the pre-launch fresh-session reset block is missing, add the reset-and-relaunch guardrail before continuing validation.
- DataLoader control-flow gate: never remove, collapse, or rewrite the DataLoader functional/performance control-flow guard (If (the number of keys in performance_data is 0) ... Else ... End If). Preserve this block structure in every mode (Fast, Normal, and Dry Run).
- DataLoader credential-branch gate: DH2/FEDA credential and citrixShortcut edits are allowed only inside the functional branch (If (the number of keys in performance_data is 0)). Never add, move, comment/uncomment, or rewrite DH2/FEDA credential lines inside the Else branch.

## Workflow

1. Run a parallel context-gather pass before editing: read the target `.script`, matching DataLoader, and any existing `*_LoginData.csv` and `*_WorkflowData.csv` together instead of one-by-one.
2. Read the entire target `.script` before editing.
3. Read the matching DataLoader and the two Resources CSVs if the script uses externalized data; if either workflow CSV is missing, create it during conversion. If legacy or mismatched workflow CSV names are present (for example spacing/hyphen variants), rename those files to the canonical wfName-based names before reading/syncing values.
4. If the DataLoader uses `millUsername` or `millUsername*`, use the hardcoded `Approved workflow username mappings (hardcoded)` section in this `SKILL.md` as the primary source before changing login values. Only consult [references/workflow-usernames.md](references/workflow-usernames.md) when explicitly requested or when the workflow is not mapped/incomplete in the hardcoded section.
5. If the script name still contains legacy terms such as `Regression` or `Regression-Testing-Script`, scan the suite for references to the current script name before renaming any file on disk.
6. Find all active login paths, step wrappers, startup noise, movie calls, screenshot calls, verification-only checks, exit logic, and try/catch endings.
7. Convert the script to the storefront/non-functional pattern without changing the business workflow intent.
8. If the DataLoader still hardcodes credentials, FINs, workflow inputs, Citrix shortcuts, or `millUsername*` values, sync those values into the matching CSV files and wire the loader to read them; when a required workflow CSV is missing, create it and populate it with the current workflow data.
9. Re-scan the script and loader for leftover legacy patterns before finishing.
10. For Fast/Normal edit runs, run the script validator tool for the updated workflow script, fix reported issues, and re-run until clean (or report clearly if validator tooling is unavailable).
11. For Fast/Normal edit runs, run the required one-command post-check (described in the Verification section), fix any issues it reports, then run the validator command again as the final linter gate before finishing.
12. For Dry Run, do not execute validator/lint/post-check commands; list the exact commands and expected outcomes only.

## Fast Mode

Use Fast Mode when the user asks for speed, when the workflow already follows common suite patterns, or when the target is a standard single-workflow conversion without custom app behavior.

Fast Mode keeps all required outcomes but uses this speed-optimized execution contract:

1. Preflight classifier (route selection):
- run a quick marker scan first (`Params platform`, direct-login handlers, multi-launch hints, multi-user hints, missing CSVs)
- choose `standard` path for common workflows and `complex` path for edge-case workflows
- if classification is ambiguous, treat as `complex`

2. Parallel intake:
- read script, DataLoader, existing CSVs, username map source, and shortcut map source in parallel

3. Cached lookup reuse:
- during the session, cache parsed hardcoded workflow username mappings from this skill (authoritative) and `ABLFHIR_CitrixShortcuts.csv` results
- invalidate cache if source file timestamp/hash changes
- never block conversion on cache issues; rebuild and continue

4. Deterministic template patching:
- apply anchored template updates for launch, recovery, exit, and credential blocks
- patch only line deltas inside recognized block anchors
- if anchors are missing/ambiguous, skip template replacement and fall back to the normal edit path for that block

5. Strict no-touch-if-compliant:
- if a section already matches accepted CleanPlant structure, do not rewrite it
- exception: exit scaffolding normalization is non-skippable for supported app flows and is exempt from this no-touch rule
- avoid cosmetic churn outside required compliance edits
- preserve existing visual separator comment blocks exactly (for example `(*========================================================================================*)`) and do not retype them

6. One-pass CSV materialization:
- build one in-memory workflow data map from script/DataLoader values
- create/update `*_LoginData.csv` and `*_WorkflowData.csv` from that single map
- keep one header row and one data row unless suite requirements say otherwise

7. Targeted validator loop (edit runs only):
- run validator once after edits
- patch only validator-reported findings
- after the first validator pass, run the secondary-user handoff check; if a secondary login path exists without the required reset-and-relaunch guardrail, add the guardrail immediately
- re-run validator
- if failures persist after targeted fixes, escalate to normal-mode deep pass for remaining issues

8. Precompiled final gate (edit runs only):
- run validator command plus one-command post-check, then re-run validator as the final completion gate
- do not finish until gate passes, or report tool unavailability clearly with reasons

Fast Mode must still enforce:
- rename safety gate (no in-place rename when references cannot be safely updated in the same change)
- DataLoader syntax/structure and CSV integrity gates (run in edit mode; include as planned checks in dry-run output)

- non-skippable username-mapping gate: when the DataLoader uses `millUsername` or `millUsername*`, apply Millennium usernames/passwords from the hardcoded `Approved workflow username mappings (hardcoded)` section as the authoritative source of truth; if the workflow status is `no_match_preserve_existing` or the workflow is missing from that hardcoded list, do not force replacements and keep existing listed username/password values
- DH2 shortcut recheck/retry flow
- script validator pass for edit runs (or explicit tooling-unavailable note)
- final post-check passing with required structure and CSV presence for edit runs
- dry-run output must include planned verification commands but must not execute them

Normal Mode must still enforce:
- all mode-wide hardening gates defined above
- existing workflow, validator, and post-check gates as written
- surgical in-place edits only; avoid broad rewrites of compliant sections
- Dry Run exception: when running with `-d`, describe verification only and do not execute validator/lint/post-check commands
- symmetry note: this section is declarative only and does not add extra execution passes or duplicate reruns beyond the existing required steps

## Script conversion rules

### 1. Normalize workflow naming

Use the script's cleaned file name as the workflow name and remove legacy terms such as `Regression` or `Regression-Testing-Script`.

Before renaming the script file on disk, run a reference scan for the current script name across the suite and closely related files so you can update or at least account for callers and metadata that still point at the old name.

Rename the script file itself on disk to match the cleaned workflow name only when all discovered references can be updated safely in the same change.

Keep these items aligned with the cleaned script name:

- the script filename itself
- the header line such as `TEST CASE NAME: ...`
- `Set wfName = "..."` and any `wfDataLoader` path built from it
- the DataLoader filename casing in Scripts/DataLoader/<workflow>_DataLoader.script (must exactly match wfName casing)

At minimum, scan the suite for:

- script call sites or launcher references
- DataLoader path strings
- suite metadata or manifests that may still mention the old filename
- workflow-specific CSV names or helper files derived from the old workflow name

If the reference scan finds external dependencies that should not be renamed in the same change, do not rename in-place. Keep the current filename, complete non-rename cleanup, and record rename as a separate follow-up.

If the script file is `VA-Printing-Revenue-Cycle-1.script`, prefer:

```text
TEST CASE NAME: VA-Printing-Revenue-Cycle-1
Set wfName = "VA-Printing-Revenue-Cycle-1"
```

### 2. Replace step-wrapper logs with `wfTestCase`

Convert explicit wrappers shaped like:

```text
Log "Step 2: ..."
...
Log "End Step 2"
```

into:

```text
Run "CTX/AbilitiesCitrixMethods".wfTestCase "Step 2: ..."
...
EndTestCase wfStep
```

Do not rewrite ordinary `Log` statements that still communicate runtime information.
Preserve visual separator comment blocks used to delineate sections (for example `(********************************************************************************)`) when cleaning or rewrapping test-case steps.
Preserve workflow step-label comments that denote functional sub-steps (for example `//Select appropriate Relationship`); do not delete or rewrite these comment markers unless the user explicitly asks.

### 3. Remove startup noise

Remove startup blocks that only support functional or pre-login handling, including:

- `if imagefound (text:"OK"...` password-entry handlers
- `"DSK/Utilities".dismissRulesOfRoad`
- `Run "VA_Common_Workflows".beginScript`
- `Run "VA_Common_Workflows".endScript` when it is only legacy startup/teardown scaffolding
- waits tied only to that dismissal flow
- active `StartMovie`
- active `StopMovie`
- commented-out copies of removed startup behavior
- malformed block-comment JSON templates such as `(*Set common to JSONValue(file ResourcePath("COMMON.json")) ... * )`; remove this entire template block instead of preserving it, because it can trigger SenseTalk lint/parsing issues

Keep `CaptureScreen` only when it is part of exception handling.

### 4. Remove direct-login scaffolding

Remove old platform and domain scaffolding when no longer needed, including:

- `Params platform, appDomainName, millenniumDomain`
- legacy `Params ...` lines that are no longer used after conversion
- default setters for `platform`, `appDomainName`, and `millenniumDomain`
- globals such as `domain`, `citrixURL`, and `citrixCredentialID` if the cleaned script no longer uses them
- treat `citrixApp` or `citrixApp*` as protected until DataLoader shortcut derivation is complete for both DH2 and FEDA blocks; only remove them after `citrixShortcut`/`citrixShortcut*` values are fully resolved and validation passes
- direct-login branches using `selectPlatform`, `openSupportFolderFromStoreFront`, or `loginExe`

### 5. Use the storefront launch pattern

Prefer this pattern, adjusting the image or post-login wait only when the application genuinely differs:

```text
Run "CTX/AbilitiesCitrixMethods".wfTestCase "Launch Application"
If not ImageFound(imageName:"PowerChart/Icon_Powerchart", waitFor:(imgWait/2))
    Log ("Millennium shortcut:" && citrixShortcut && " is Not Running")
    Run "CTX/AbilitiesCitrixMethods".SCL_LaunchAndLoginCitrix citrixShortcut, sutUsername, sutPassword
    WaitFor imgWait*7, "Textbox_Login_Username"
    Run "MIL/Millennium".login millUsername, millPassword
Else
    Log ("Millennium shortcut:" && citrixShortcut && " is Running")
End If
WaitFor imgWait*3, "MIL/PowerChart/DropDown_RecentSearch/Dropdown_Arrow"
TypeText windowsKey & upArrow
EndTestCase wfStep
```

If the main script already has this storefront launch block active and structurally correct, leave it in place instead of rewriting the whole section. Treat `WaitFor imgWait*<number>, "Textbox_Login_Username"` as an acceptable login-control wait, not as a reason to replace the block just to force `imgWait*7`.

When an active, uncommented launch block already matches this structure, preserve the entire block as-is when the only differences are:

- `WaitFor imgWait*<number>, "Textbox_Login_Username"` instead of `WaitFor imgWait*7, "Textbox_Login_Username"`
- `Run "MIL/Millennium".login millUsername, millPassword` versus `Run "MIL/Millennium".login millUsername1, millPassword` or any other matching `millUsername*` variable

Do not rewrite any other line in that block when those are the only differences.

When converting legacy launch scaffolding, preserve the existing launch-block `wfTestCase` label exactly as written (for example `Run "CTX/AbilitiesCitrixMethods".wfTestCase "Login into PowerChart as a Physician Hospitalist."`). Do not replace that header with `"Launch Application"` and do not replace the entire block. Only normalize the launch-body lines under the preserved header (ImageFound/SCL_LaunchAndLoginCitrix/WaitFor/login/EndTestCase) so workflow-to-username mapping remains learnable.

For Revenue Cycle or AppBar, keep the same structure but use the correct app-ready image or wait target.

AppBar target-classification gate (required):

- do not classify a workflow target app from `citrixApp = "AppBar"` alone; AppBar can launch multiple applications
- first confirm AppBar context from launch evidence (for example `AppBar_Images/Icon_AppBar`, AppBar-ready wait targets, or AppBar shortcut/app header evidence)
- then require explicit target-app launch evidence from AppBar (for example double-clicking a target icon such as `PathNet/MaintainCase_Icon`)
- then require follow-on target-app namespace evidence in active workflow-driving steps (for example multiple `PathNet/...` image paths after launch)
- only classify `AppBar -> <TargetApp>` when all three checks above are satisfied
- if AppBar context exists but target-app evidence is weak or missing, classify as `AppBar -> Unknown` and preserve existing app-specific logic instead of forcing an app-specific normalization path

When the workflow logs back in with a secondary username such as `millUsername2`, add a fresh-session reset before the secondary launch so Eggplant does not search against a stale Citrix window. Prefer this temporary pattern:

```text
TypeText Windowskey, "r"
Click {text: "Open", Waitfor: 60, SearchRectangle: "UTIL/Screen".scale (0, .75, .20, 1)}
TypeText "taskkill /f /IM msedge.exe"
TypeText returnKey
wait 4

Run "CTX/AbilitiesCitrixMethods".wfTestCase "Launch Application MsgCenter- Physician User"
If not ImageFound(imageName:"PowerChart/Icon_Powerchart", waitFor:(imgWait/2))
    Log ("Millennium Application:" && citrixApp && "is Not Running")
    Run "CTX/AbilitiesCitrixMethods".SCL_LaunchAndLoginCitrix citrixShortcut, sutUsername, sutPassword
    WaitFor 60, "Textbox_Login_Username"
    Run "MIL/Millennium".login millUsername2, millPassword
Else
    Log ("Millennium Application:" && citrixApp && "is Running")
End If
TypeText windowsKey, upArrow
EndTestCase wfStep
```

Use that reset-and-relaunch pattern only for the secondary-user handoff path, not for every ordinary single-user launch block. Run the Edge taskkill reset block unconditionally before the secondary launch.

### 6. Remove verification-only checks

Remove `If ImageFound(...) then ... else ... End If` blocks when they only:

- log pass/fail status
- capture screenshots for evidence
- confirm a screen or state without driving workflow

Keep checks that still click, branch, retry, dismiss popups, or otherwise affect the flow.

Protect exception-path diagnostics. Do not remove `LogError(...)`, `CaptureScreen`, or similar statements when they are part of `try/catch` handling, exception reporting, or recovery flow.

Do not flatten an optional `If ImageFound(...) then` gate into an unconditional `WaitFor` when the guarded block performs workflow-driving work such as opening a manual-entry path, populating fields, or dismissing a conditional dialog.

For example, preserve patterns like:

```text
If ImageFound(text:"Scan or manually", SearchRectangle:"UTIL/Screen".center, WaitFor:imgWait) then
    Click {text:"Serial Number", HotSpot:[0,30], EnableAggressiveTextExtraction:"YES", SearchRectangle:"UTIL/Screen".center, WaitFor:imgWait}
    ...
End If
```

If a removed verification was the only protection against silent failure, replace it with a direct `WaitFor` or a targeted `throw`.

Normalize common token typos with the validator tool:

- `cleanplant-validate.ps1` performs `SerachRectangle` -> `SearchRectangle` conversion on the main workflow script
- `cleanplant-validate.ps1` auto-fixes malformed separator comment delimiters such as `(========================================================================================*)` -> `(*========================================================================================*)`
- treat this as an automatic validator conversion, not a manual follow-up

### 7. Normalize exits

First determine which application the cleaned workflow launches or is actively exiting. Match the exit keystrokes to that app instead of applying the PowerChart exit globally.

When the script exits PowerChart or an Appbar-launched PathNet workflow, prefer:

```text
Run "CTX/AbilitiesCitrixMethods".wfTestCase "Exit out of PowerChart."
wait 2
TypeText altKey
wait 2
TypeText "t"
wait 2
TypeText "x"
EndTestCase wfStep
```

When the script exits RevenueCycle, prefer:

```text
Run "CTX/AbilitiesCitrixMethods".wfTestCase "Exit out of Revenue Cycle."
wait 2
TypeText altKey
wait 2
TypeText "f"
wait 2
TypeText "x"
EndTestCase wfStep
```

Only normalize to those split-key exit patterns when the launched or exited application is clearly PowerChart, Appbar->PathNet, RevenueCycle, or FirstNet. For FirstNet and Appbar-launched PathNet workflows, use the standardized PowerChart exit sequence (`TypeText altKey`, wait, `TypeText "t"`, wait, `TypeText "x"`).

If the application is not explicitly PowerChart, Appbar->PathNet, RevenueCycle, or FirstNet, keep the workflow's existing exit scaffolding instead of forcing one of the normalized menu-key sequences.

Use the launch target, app-ready image, existing app header, or `citrixApp` value to decide which exit path to normalize to. For AppBar workflows specifically, treat `citrixApp` as context only and require explicit target-app launch plus follow-on target-app namespace evidence before choosing an app-specific exit path. Do not rewrite a RevenueCycle exit block to the PowerChart `TypeText altKey`, `wait 2`, `TypeText "t"`, `wait 2`, `TypeText "x"` sequence. For FirstNet and Appbar-launched PathNet workflows, normalize to that same PowerChart `alt`, `t`, then `x` exit sequence with waits between key presses.

Rewrite common exit variants such as toolbar exits, `Task > Exit`, image-based exit clicks, and similar short blocks.

### 8. Standardize recovery

Prefer this ending shape:

```text
Run "CTX/AbilitiesCitrixMethods".ScaleRecovery

catch exception

"UTIL/Common".handleException exception
Run "CTX/AbilitiesCitrixMethods".ScaleRecovery

end try
```

Do not add `Run "CTX/AbilitiesCitrixMethods".ScaleRecovery` immediately after a mid-workflow app-exit block. If a script exits an app in the middle of the workflow and then continues with additional workflow steps, keep that exit-local block free of `ScaleRecovery`.

`ScaleRecovery` belongs only in the final recovery region: once at the end right before `catch exception`, and once inside `catch exception`.

If the script performs app-specific cleanup in catch, keep it, then handle the exception, then run `ScaleRecovery`.

## DataLoader and CSV sync rules

When the workflow uses a DataLoader, also apply these rules.

### 1. Read the full set first

Inspect:

- `Scripts/DataLoader/<workflow>_DataLoader.script`
- `Resources/*_LoginData.csv`
- `Resources/*_WorkflowData.csv`

### 1a. Preserve DataLoader control flow

Never remove or flatten the DataLoader control-flow branch:

- `If (the number of keys in performance_data is 0) ... Else ... End If`
- keep both branches present even when values are normalized
- apply credential/header/value updates inside the existing branches instead of deleting the guard

### 1b. Remove unused DataLoader scaffolding

After wiring the loader to CSV fields and confirming the cleaned script no longer depends on legacy direct-login/platform paths, remove unused DataLoader scaffolding such as:

- `Params platform, appDomainName, millenniumDomain`
- default setters for `platform`, `appDomainName`, and `millenniumDomain`
- unused globals and assignments such as `domain`, `citrixURL`, and `citrixCredentialID`

Keep `citrixApp` or `citrixApp*` only when they are still actively used for shortcut derivation, app-token mapping, launch-order intent, or other active loader logic.

Precedence rule for `citrixApp` cleanup:

- never remove or comment `citrixApp`/`citrixApp*` before both DH2 and FEDA `citrixShortcut`/`citrixShortcut*` values are resolved
- after shortcut values are resolved, keep `citrixApp`/`citrixApp*` only where still needed for active loader logic
- only remove/comment `citrixApp`/`citrixApp*` after validator and post-check gates are clean

- for numbered app tokens (`citrixApp1`, `citrixApp2`, etc.), comment out the `Set citrixApp<number> = "..."` line only after the matching DH2 `ABLFHIR` `citrixShortcut<number>` literal has been placed in the loader (or confirmed from CSV/local evidence/helper lookup)
- do not comment `citrixApp<number>` before the matching `ABLFHIR` shortcut is populated
### 2. Move hardcoded values to CSVs

Use these homes:

- `millUsername*`, `millPassword*` -> `*_LoginData.csv`
- LoginData username header rule: use numbered `millUsername#` CSV headers only when active `millUsername#` variables exist in the DataLoader; otherwise use regular `millUsername`. Do not infer numbered login headers from comments or from unrelated CSV shape.
- FINs, patient names, order names, subjects, and similar workflow inputs -> `*_WorkflowData.csv`
- FIN source-of-truth rule: if any DataLoader hardcoded `*FIN*` variable value differs from `*_WorkflowData.csv`, treat the DataLoader value as authoritative and update the CSV to match; never overwrite DataLoader FIN defaults from CSV values
- `citrixShortcut` -> `*_WorkflowData.csv` under the existing app header, usually `PowerChart`, `RevenueCycle`, or `AppBar`
- if the workflow truly launches multiple Citrix apps, keep one shortcut variable per launch target such as `citrixShortcut1`, `citrixShortcut2`, and `citrixShortcut3`, and map each one to the matching workflow-data app header instead of collapsing them into a single shortcut
- keep `sutUsername`, `sutPassword`, and `sutUsername*`/`sutPassword*` hardcoded in the DataLoader credential block; do not move SUT credentials into `*_SutUsers.csv`

If either `*_LoginData.csv` or `*_WorkflowData.csv` is missing, create the missing file(s) in `Resources` using the workflow name and write one header row plus one data row that match the loader/script field names and current values.
Before creating missing workflow CSV files, normalize naming first:

- canonical names must be Resources/<wfName>_LoginData.csv and Resources/<wfName>_WorkflowData.csv
- if only legacy/mismatched names exist, auto-rename them to canonical names and continue sync
- if both canonical and legacy/mismatched sets exist, treat canonical files as source-of-truth and do not overwrite canonical values from legacy duplicates; report the duplicate set in output

When assigning `millUsername` values, use the hardcoded `Approved workflow username mappings (hardcoded)` section in this `SKILL.md` first. Use [references/workflow-usernames.md](references/workflow-usernames.md) only when explicitly requested or when the workflow is not mapped/incomplete in the hardcoded section.

Treat the hardcoded `Approved workflow username mappings (hardcoded)` section below as the authoritative source of truth for applying Millennium usernames and passwords:

- `workflow`
- `status`
- `resolved_usernames`
- `position`
- `resolved_mill_password`

For the matching workflow:

- if one approved username exists, set `millUsername = "<username>" //{<position>}`
- if multiple approved usernames exist, first read the target `.script` and determine role order primarily from login `wfTestCase` labels; if those labels do not exist, use preserved section markers/comments such as `//Part1: Physician workflow ...`; for PowerChart workflows, use `PopUps.assignRelationship "<Role Text>"` as an additional indicator when label/comment evidence is ambiguous; then assign `millUsername1`, `millUsername2`, `millUsername3`, and so on in that inferred role order with inline position comments `//{<position>}`
- set every `millPassword` or `millPassword*` value to `"scale"` when hardcoded login defaults are being refreshed

Mandatory ordering rule: inferred script role order always wins for workflows with more than one mapped username (primary: login `wfTestCase` labels; fallback: preserved part comments; additional PowerChart indicator: `PopUps.assignRelationship`). Do not assign `millUsername*` by `resolved_usernames` list order alone.
Position-pairing rule: `resolved_usernames` and `position` must stay index-aligned during any reorder; always move the paired `//{<position>}` comment with its username assignment.

Auto-update rule: when the current `millUsername*` assignments do not match inferred script role order, rewrite them to match the detected order. Do not stop the run for this case.

Consistency gate (required): after applying approved mappings, compare expected millUsername* and millPassword* values against both DataLoader hardcoded defaults and *_LoginData.csv. If either target still carries legacy values (or the login CSV columns do not match the selected username shape), fail the run instead of silently proceeding.

<!-- BEGIN APPROVED WORKFLOW USERNAME MAPPINGS -->
### Approved workflow username mappings (hardcoded)

Use this in-file list as the authoritative source of truth for applying Millennium usernames and passwords in this skill revision.

- if `status` is `mapped`, apply `resolved_usernames`, `position`, and `resolved_mill_password`
- if `status` is `no_match_preserve_existing`, keep current DataLoader and login CSV username/password values unchanged
- if a workflow is missing from this hardcoded list, preserve existing DataLoader and login CSV username/password values (`no_match_preserve_existing` behavior)
- for workflows with multiple mapped usernames, treat `resolved_usernames` as the candidate username set, preserve username-to-position index pairing from `position`, and place those candidates by actual script login order

| workflow | status | resolved_usernames | position | resolved_mill_password |
|---|---|---|---|---|
| OCONUS-Ambulatory-Patient-Intake-1 | mapped | ABL_AmbIntake_PtOne1 | Scheduling Advanced | scale |
| OCONUS-Ambulatory-Patient-Intake-2 | mapped | ABL_Oconus_Amb_PtItk_PtTwo_A1&#124;ABL_Oconus_Amb_PtItk_PtTwo_B1 | Scheduling Advanced&#124;Ambulatory: RN | scale |
| OCONUS-Ambulatory-Schedule-Appointment | mapped | ABL_Amb_SchedAppt1 | Scheduling Advanced | scale |
| OCONUS-Clinical-Reporting-Medical-Record-Request | mapped | ABL_ClinicalReporting_MRR_A1&#124;ABL_ClinicalReporting_MRR_B1 | VA Nurse: Nurse&#124;VA Registration/Scheduling Clerk I | scale |
| OCONUS-FirstNet-Combined-Quick-Full-Reg | mapped | ABL_Oconus_FnetQuickFullReg_A1&#124;ABL_Oconus_FnetQuickFullReg_B1 | ED Registration Clerk&#124;VA Registration/Scheduling Clerk III | scale |
| OCONUS-Provider-Workflow-CPOE-Orders-1 | mapped | ABL_CPOE_Orders_PtOne_A1&#124;ABL_CPOE_Orders_PtOne_B1 | Physician - Hospitalist&#124;RN | scale |
| OCONUS-Provider-Workflow-CPOE-Orders-2 | mapped | ABL_CPOE_Orders_PtTwo1 | RN | scale |
| OCONUS-Registration-Add-Net-New-Person | mapped | ABL_Oconus_RegAddPerson1 | Registration Clerk | scale |
| VA-Amb-Health-Maintenance-Invitations | mapped | ABL_HealthMaint_Invitation1 | VA Physician - Primary Care | scale |
| VA-Ambulatory-End-to-End-Part1 | mapped | ABL_Amb_EndToEnd_PtOne1 | VA Registration/Scheduling Clerk III | scale |
| VA-Ambulatory-Organizer-Confirm-Decline | mapped | ABL_AmbOrg_Decline_Grp15_B1&#124;ABL_AmbOrg_Confirm_Grp15_A1 | VA Ambulatory: RN&#124;VA Ambulatory: RN | scale |
| VA-Ambulatory-Referral-1 | mapped | ABL_Amb_Referral_PtOne_A1&#124;ABL_Amb_Referral_PtOne_B1 | VA Physician Assistant&#124;VA Physician - Primary Care | scale |
| VA-Batch-Charge-Entry-And-Charge-Viewer-Script | mapped | ABL_BatchChrgEntry_Grp13_A1&#124;ABL_ChrgViewer_Grp13_B1 | VA Charge Analyst - Local&#124;VA Charge Analyst - Local | scale |
| VA-CDA-And-LetterPreview | mapped | ABL_LetterPreview_Grp8_A1&#124;ABL_VA_CDA_Grp8_BA1 | VA Physician - Primary Care&#124;VA Physician - Primary Care | scale |
| VA-Configure-AppBar-Applications | mapped | ABL_PharmWrkstation_Grp1_B1&#124;ABL_PrintReg_Periop_Grp1_A1 | VA PharmNet: Pharmacist&#124;VA Perioperative - Nurse | scale |
| VA-ED-Quick-Reg-And-MMR-External-Provider | mapped | ABL_MMRExtProvSearch_Grp12_B1&#124;ABL_EDQuickReg_Grp12_A1 | VA PharmNet: Pharmacist&#124;VA Registration/Scheduling Clerk III | scale |
| VA-Financial-Combine-And-Modify-Charge | mapped | ABL_Financial_Combine_Grp7_A1&#124;ABL_MOD_CHARGE_Grp7_B1 | VA Billing - MRT&#124;VA Billing - MRT | scale |
| VA-Health-Maintenance-and-Immunizations-And-Vaccine | mapped | ABL_HealthMaint_Imz_Grp6_A1&#124;ABL_VA_Vaccine_Grp6_BB1 | VA Ambulatory: RN&#124;VA Ambulatory: RN | scale |
| VA-Home-Medication-Component-Physician-Documentation | mapped | ABL_HomeMedsComponnet_Grp4_B1&#124;ABL_Phys_Doc_Grp4_A1 | VA Physician - Primary Care&#124;VA Physician - Primary Care | scale |
| VA-IP-Registration | mapped | ABL_IP_Registration1 | VA Registration/Scheduling Clerk III | scale |
| VA-IView-Copay-Printing-PowerChart | mapped | ABL_PrintReg_Pchart_Grp16_B1&#124;ABL_Iview_Full_Grp16_C1&#124;ABL_Copay_Grp16_A1 | VA Physician - Primary Care&#124;VA Nurse: Nurse&#124;VA CM - Cashier | scale |
| VA-Inpatient-Pharmacy-1 | mapped | ABL_InPatient_Pharm_PtOne1&#124;ABL_InPatient_Pharm_PtOne_B1 | VA Physician - Hospitalist&#124;VA PharmNet: Pharmacist | scale |
| VA-Inpatient-Pharmacy-2 | mapped | ABL_InPatient_Pharm_PtTwo_A1&#124;ABL_InPatient_Pharm_PtTwo_B1 | VA Nurse: Nurse&#124;VA Physician - Hospitalist | scale |
| VA-MPage-DynDoc | mapped | ABL_Mpage_DynDoc1 | VA Physician - Hospitalist | scale |
| VA-Messages-And-Orders | mapped | ABL_Messages_Orders_A1&#124;ABL_Messages_Orders_B1&#124;ABL_Messages_Orders_C1 | VA Physician - Hospitalist&#124;VA Physician - Primary Care&#124;VA Physician - Resident HPT | scale |
| VA-Origination-Referral-Part1 | mapped | ABL_Orig_Referral_PtOne_A1&#124;ABL_Orig_Referral_PtOne_B1 | VA Physician Assistant&#124;VA Physician - Primary Care | scale |
| VA-Origination-Referral-Part2 | mapped | ABL_Orig_Referral_PtTwo1 | VA Referral Coordinator | scale |
| VA-PathNet-AP-1 | mapped | ABL_PathNet_AP_PtOne_A1 | VA Lab: AP Histotech | scale |
| VA-PathNet-AP-2 | mapped | ABL_PathNet_AP_PtTwo_AA1&#124;ABL_PathNet_AP_PtTwo_B1&#124;ABL_PathNet_AP_PtTwo_C1 | VA Lab: AP Histotech&#124;VA Lab: AP Transcription&#124;VA Lab: AP Pathologist | scale |
| VA-PathNet-Blood-Products-Orders-1 | mapped | ABL_BloodProduct_PtOne1 | VA Physician - Hospitalist | scale |
| VA-PathNet-Blood-Products-Orders-2 | mapped | ABL_BloodProduct_PtTwo1 | VA Physician - Hospitalist | scale |
| VA-PathNet-DOE | mapped | ABL_PATHNET_DOE1 | VA Laboratory: Hybrid Medical Tech | scale |
| VA-PathNet-Gen-Micro-Lab-Cultures-and-Storage-Tracking-1 | mapped | ABL_GLB_CultureStorage_PtOne1 | VA Laboratory: Hybrid Medical Tech | scale |
| VA-PathNet-GenLabFull-Part1 | mapped | ABL_PN_GLB_Full_PtOne1 | VA Laboratory: Hybrid Medical Tech | scale |
| VA-PathNet-GenLabFull-Part2 | mapped | ABL_PN_GLB_Full_PtTwo1 | VA Laboratory: Hybrid Medical Tech | scale |
| VA-PathNet-Micro-Full-1 | mapped | ABL_PathNet_MicroFull_PtOne1 | VA Laboratory: Hybrid Medical Tech | scale |
| VA-Patient-Centric-Referral-DiagnosisAsst | mapped | ABL_PatCentric_Referral_Grp9_A1&#124;ABL_Diagnosis_Asst_Grp9_B1 | VA Physician Assistant&#124;VA Physician - Primary Care | scale |
| VA-Patient-Deficiency-Analysis | mapped | ABL_Patient_Def_Analysis1 | VA HIM: Chief | scale |
| VA-Periop-Pref-Cards-1 | no_match_preserve_existing |  |  |  |
| VA-Periop-Pref-Cards-2 | no_match_preserve_existing |  |  |  |
| VA-Periop-Pref-Cards-3 | no_match_preserve_existing |  |  |  |
| VA-PhaCharge-Credit-1 | mapped | ABL_PhaChrgCredit_Pt1_AA1&#124;ABL_PhaChrgCredit_Pt1_B1 | VA Nurse: Nurse&#124;VA Physician - Hospitalist | scale |
| VA-PhaCharge-Credit-2 | mapped | ABL_PhaChrgCredit_PtTwo1 | VA PharmNet: Pharmacist | scale |
| VA-Pharmacy-Care-Organizer-And-Supply-Chain | mapped | ABL_Pharm_CareOrg_Grp14_B1&#124;ABL_SupplyChain_Grp14_A1 | VA PharmNet: Pharmacist&#124;VA Supply Chain - Inventory Specialist | scale |
| VA-Physician-Deficiency-Analysis | mapped | ABL_Phys_Def_Analysis1 | VA HIM: Chief | scale |
| VA-PowerChart-Inpatient-1 | mapped | ABL_Pchart_Inpatient_PtOne1 | VA Physician - Hospitalist | scale |
| VA-PowerChart-Inpatient-2 | mapped | ABL_Pchart_Inpatient_PtTwo_A1&#124;ABL_Pchart_Inpatient_PtTwo_B1&#124;ABL_Pchart_Inpatient_PtTwo_C1 | VA Physician - Hospitalist&#124;VA Physician - Hospitalist&#124;VA Physician - Hospitalist | scale |
| VA-PowerChart-RX-Writer | mapped | ABL_Pchart_RX_Writer_C1 | VA Physician - Hospitalist | scale |
| VA-PowerForm-Charting-And-Text-Control-Net | mapped | ABL_PwfCharting_Grp3_A1&#124;ABL_TxtControlNet_Grp3_B1 | VA Physician - Primary Care&#124;VA Physician - Primary Care | scale |
| VA-Printing-Lab-1 | mapped | ABL_PrintReg_TestLab_PtOne1 | VA Laboratory: Hybrid Medical Tech | scale |
| VA-Printing-Lab-2 | mapped | ABL_PrintReg_TestLab_PtTwo_A1&#124;ABL_PrintReg_TestLab_PtTwo_B1 | VA Laboratory: Hybrid Medical Tech&#124;VA Physician - Emergency | scale |
| VA-Printing-PeriOp-Pharmacy-Workstation | mapped | ABL_PrintReg_Periop_Grp1_A1&#124;ABL_PharmWrkstation_Grp1_B1 | VA Perioperative - Nurse&#124;VA PharmNet: Pharmacist | scale |
| VA-Printing-Pharmacy | mapped | ABL_PrintReg_Pharmacy1 | Automation Pharmacist | scale |
| VA-Printing-Radiology | mapped | ABL_PrintReg_Radiology1 | VA RadNet: Radiology Technologist | scale |
| VA-Printing-Revenue-Cycle-1 | mapped | ABL_PrintReg_RevCycle_PtOne1 | VA Registration/Scheduling Clerk III | scale |
| VA-Printing-Revenue-Cycle-2 | mapped | ABL_PrintReg_RevCycle_PtTwo1 | VA OPECC - Biller | scale |
| VA-Procedure-Social-Family-History | mapped | ABL_PROCHIST_SOCHIST_FAMHIST1 | VA Physician - Primary Care | scale |
| VA-Quick-Reg | mapped | ABL_Quick_Registration1 | VA Registration/Scheduling Clerk I | scale |
| VA-Revenue-Cycle-Worklist-Performance-Check | mapped | ABL_RevCycle_WorklistPerfCheck1 | VA Registration/Scheduling Clerk III | scale |
| VA-Sch-Appt-Many-Locations-Mult-Appt-First-Available | mapped | ABL_SCHEDAPPT_ML_Grp10_A1&#124;ABL_MULTIPLEAPPT_FA_Grp10_B1 | VA Registration/Scheduling Clerk I&#124;VA Registration/Scheduling Clerk I | scale |
| VA-Schedule-Appointment-Through-First-Available-and-Modify-Appointments | mapped | ABL_SCHEDAPPT_FA_MODAPPT1 | VA Registration/Scheduling Clerk I | scale |
| VA-Scheduling-Protocol-Appointment | mapped | ABL_SchedProtocolAppt_Regres_A1&#124;ABL_SchedProtocolAppt_Regres_B1 | VA Physician - Primary Care&#124;VA Registration/Scheduling Clerk I | scale |
| VA-Single-Block-Occurrence-Modify-Appointments | mapped | ABL_SingleBlockOccur_Grp11_A1&#124;ABL_MODIFYAPPT_Grp11_B1 | VA Registration/Scheduling Clerk I&#124;VA Registration/Scheduling Clerk I | scale |
| VA-VTE-Risk-Assessment | mapped | ABL_VTERiskAssessment1 | VA Physician - Hospitalist | scale |
| VA-XR-1 | mapped | ABL_XR_Regression1 | VA HIM: ROI | scale |
| VA-XR-2 | mapped | ABL_XR_Regression1 | VA HIM: ROI | scale |
| VA-XR-MRR | mapped | ABL_XR_MRR_AA1&#124;ABL_XR_MRR_B1 | VA Ambulatory: Clinic Manager&#124;VA HIM: Chief | scale |
| VA-XR-Manual-Expedite | mapped | ABL_XR_Manual_Expedite_A1&#124;ABL_XR_Manual_Expedite_B1&#124;ABL_XR_Manual_Expedite_C1 | VA Laboratory: Hybrid Medical Tech&#124;VA HIM: ROI&#124;VA RadNet: Radiology Technologist | scale |
<!-- END APPROVED WORKFLOW USERNAME MAPPINGS -->

Examples:

```text
Set millUsername = "ABL_Quick_Registration1" //{VA Registration/Scheduling Clerk III}
Set millPassword = "scale"
```

```text
Set millUsername1 = "ABL_PhaChrgCredit_Pt1_B1" //{VA Physician - Hospitalist}
Set millUsername2 = "ABL_PhaChrgCredit_Pt1_AA1" //{VA Nurse: Nurse}
Set millPassword = "scale"
```

At the beginning of the functional branch in the DataLoader, keep the active FEDA block and handle the DH2 block with this rule:

- if an existing `sutUsername` or `sutUsername<number>` already contains a `dh2\xaauto<#>` value, keep that existing DH2 username as-is
- only use the hardcoded DH2 fallback block shown below when no existing `dh2\xaauto<#>` user is present anywhere in the DataLoader credential section

```text
//DH2 Credentials
//Set sutUsername = "dh2\xaauto022"
//Set sutPassword = "Cerner1"
//Set citrixShortcut = ""

//SUT CREDs: FEDA
Set sutUsername = "cernabliad\xaauto000"
set sutPassword = "Cerner01"
Set citrixShortcut = ""
```

Keep the DH2 block commented and the FEDA block active. Do not replace an existing DH2 username with `dh2\xaauto022`.
Apply this DH2/FEDA toggle rule only within the functional branch (If (the number of keys in performance_data is 0)). Do not perform DH2/FEDA edits in the Else (performance_data) branch.
Keep SUT credential assignment in this DataLoader block; do not externalize SUT credentials to `*_SutUsers.csv`.
Do not auto-add `sutUsername` or `sutPassword` columns to `Resources/<wfName>_LoginData.csv` when they are sourced from a static/shared location. Preserve existing LoginData header shape and keep it Millennium-login focused (`millUsername*`, `millPassword`) unless the workflow already explicitly uses SUT columns there.

For `citrixShortcut` in those two credential blocks:

- if a workflow already has a literal shortcut value for DH2 or FEDA, keep it exactly as-is
- if a workflow does not have a value there yet, set it to `""`

Do not blank out an existing shortcut just because the workflow CSV also supplies one later.

For the DH2 block specifically, select the shortcut directly from the approved ABLFHIR mappings below. Do not use the old CSV lookup, local-evidence lookup, or Python-helper fallback flow for this skill.

Use this selection process:

1. Read the DataLoader's active `citrixApp` or `citrixApp<number>` value.
2. Normalize the app token for matching by trimming spaces, comparing case-insensitively, and treating an optional `.exe` suffix as equivalent.
3. Match that normalized app token to the approved `AppName` list below.
4. Copy the mapped `citrixShortcut` literal into the commented DH2 `citrixShortcut` or `citrixShortcut<number>` line exactly as written.
5. If no approved mapping exists for the DataLoader app token, leave the current literal value in place if one already exists; otherwise use `""` and report that the app token has no approved mapping yet.

For numbered launch flows, map each `citrixApp<number>` independently to its matching `citrixShortcut<number>` using the same approved list and launch-order numbering.

Approved `ABLFHIR_CitrixShortcuts.csv` mappings:

- `Accessionresultentry` -> `http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/#/launch/ABLFHIR_Accessionresultentry/7DssAlHfGG6LI8HdEBtqcrHVWLYPIIv0Gt71vCL4vaFBQkxGSElSX0FjY2Vzc2lvbnJlc3VsdGVudHJ5`
- `Appbar` -> `http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/#/launch/ABLFHIR_Appbar/CxJFcTpLlZ77mJ83GRwfWdiMiglhl5BVyxZ0XhRsswRBQkxGSElSX0FwcGJhcg%3D%3D`
- `CernerApps` -> `http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/#/launch/ABLFHIR_CernerApps/amCs%2BEMPlKX4%2F3wO5Gar4D0%2FXoSyZA7L0%2BrGbwV98KJBQkxGSElSX0Nlcm5lckFwcHM%3D`
- `Csbatchchargeentry` -> `http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/#/launch/ABLFHIR_Csbatchchargeentry/IYZuv2RPxOY76QF6cZwT%2BPLMkdN0Z7BvkwVv5BlKythBQkxGSElSX0NzYmF0Y2hjaGFyZ2VlbnRyeQ%3D%3D`
- `Cschargeviewer` -> `http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/#/launch/ABLFHIR_Cschargeviewer/VsQ2eVN1cWAWYiX164i48ZaDG6zJPiWG5%2BT3O4FWwEpBQkxGSElSX0NzY2hhcmdldmlld2Vy`
- `Deptorderentry` -> `http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/#/launch/ABLFHIR_Deptorderentry/qm4tvGzI0RuYbYvGc%2BbAq04sy88yLx1%2Bt6GqrZP8zqZBQkxGSElSX0RlcHRvcmRlcmVudHJ5`
- `Desktoplauncher` -> `http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/#/launch/ABLFHIR_Desktoplauncher/EJwC2mgKFsngakuqCga1%2FzpX1br4dKa1PaPCRPRoRnlBQkxGSElSX0Rlc2t0b3BsYXVuY2hlcg%3D%3D`
- `FirstNet` -> `http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/#/launch/ABLFHIR_FirstNet/7Y7W8hIX6qTa9mvEE9uF4JmgxVKIceuzEm0yLulhGbZBQkxGSElSX0ZpcnN0TmV0`
- `Himphysiciandeficiencyanalysis` -> `http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/#/launch/ABLFHIR_Himphysiciandeficiencyanalysis/g6xfZw34MsWpg0ypOyv1KOAZagwdi1wE0u9m2gDpGOBBQkxGSElSX0hpbXBoeXNpY2lhbmRlZmljaWVuY3lhbmFseXNpcw%3D%3D`
- `PMLaunch` -> `http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/#/launch/ABLFHIR_PMLaunch/o8OK0Ud%2B38MkKGxLr0MsjR4smUPEvA3raE2j%2F1mvNPhBQkxGSElSX1BNTGF1bmNo`
- `PMOffice` -> `http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/#/launch/ABLFHIR_PMOffice/TUl9ZkqI5CqzhTUzHUPs2NXbTfzfnWSKw00n50EMMmxBQkxGSElSX1BNT2ZmaWNl`
- `PhaMedMgr` -> `http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/#/launch/ABLFHIR_PhaMedMgr/T5GFF0q%2Ftx50Fot9TjMq0gqZN%2BKb87VdfWdsZhNmKZhBQkxGSElSX1BoYU1lZE1ncg%3D%3D`
- `Phamedmgrretail` -> `http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/#/launch/ABLFHIR_Phamedmgrretail/OqCehxD%2BMm6x8V1pTCIB0oOP1tItXdxDlssBavLt089BQkxGSElSX1BoYW1lZG1ncnJldGFpbA%3D%3D`
- `Powerchart` -> `http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/#/launch/ABLFHIR_Powerchart/pF57arefNxEEc%2FhDsMKoNPOWTCnA11BBccFrJGWLtIZBQkxGSElSX1Bvd2VyY2hhcnQ%3D`
- `Radexammgmt` -> `http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/#/launch/ABLFHIR_Radexammgmt/M%2FQKUubCtoPDn4J8NLh9i64lsfek%2B2CIgr4PD%2BgKK5xBQkxGSElSX1JhZGV4YW1tZ210`
- `Reportrequestmaint` -> `http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/#/launch/ABLFHIR_Reportrequestmaint/LiL8XzHofLK6WUqFI%2FtveORCQH8vXXrs84fY2OKa3tdBQkxGSElSX1JlcG9ydHJlcXVlc3RtYWludA%3D%3D`
- `RevenueCycle` -> `http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/#/launch/ABLFHIR_RevenueCycle/Ehl7N3bKBS52LOxbDOqvaAH33XoJdRwXOGBwlQAzJq5BQkxGSElSX1JldmVudWVDeWNsZQ%3D%3D`
- `SchedulingApptBook` -> `http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/#/launch/ABLFHIR_SchedulingApptBook/xgG54Rk6zmvpcMnGXep3c9EO6z2dER9%2FUloD4R5YWo5BQkxGSElSX1NjaGVkdWxpbmdBcHB0Qm9vaw%3D%3D`
- `Specimenlogin` -> `http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/#/launch/ABLFHIR_Specimenlogin/N589K19SVjkUXfaIHQgSUf4tKBROZDjh766cazWq63FBQkxGSElSX1NwZWNpbWVubG9naW4%3D`

Treat the approved list above as the source of truth for DH2 shortcut selection in this skill revision. Pull the correct mapping from that list based on the DataLoader `citrixApp` value rather than re-deriving it from other files or helpers.

For the FEDA block specifically, select the shortcut directly from the approved ABLFEDA mappings below using the same matching flow used for DH2/ABLFHIR mappings.

Use this selection process:

1. Read the DataLoader's active `citrixApp` or `citrixApp<number>` value.
2. Normalize the app token for matching by trimming spaces, comparing case-insensitively, and treating an optional `.exe` suffix as equivalent.
3. Match that normalized app token to the approved `AppName` list below.
4. Copy the mapped `citrixShortcut` literal into the active FEDA `citrixShortcut` or `citrixShortcut<number>` line exactly as written.
5. If no approved mapping exists for the DataLoader app token, leave the current literal value in place if one already exists; otherwise use `""` and report that the app token has no approved mapping yet.

For numbered launch flows, map each `citrixApp<number>` independently to its matching `citrixShortcut<number>` using the same approved list and launch-order numbering.

Approved `ABLFEDA_CitrixShortcuts.csv` mappings:

- `ABLFEDA Support Folder` -> `http://10.44.120.36/Citrix/Prodweb/?LaunchApp=ABLFEDA%20Support%20Folder`
- `ABLFEDA_CSbatchchargeentry` -> `http://10.44.120.36/Citrix/Prodweb/?LaunchApp=ABLFEDA_CSbatchchargeentry`
- `ABLFEDA_Cschargeviewer` -> `http://10.44.120.36/Citrix/Prodweb/?LaunchApp=ABLFEDA_Cschargeviewer`
- `ABLFEDA_DG_AccessionResultEntry` -> `http://10.44.120.36/Citrix/Prodweb/?LaunchApp=ABLFEDA_DG_AccessionResultEntry`
- `ABLFEDA_DG_Appbar` -> `http://10.44.120.36/Citrix/Prodweb/?LaunchApp=ABLFEDA_DG_Appbar`
- `ABLFEDA_DG_DeptOrderEntry` -> `http://10.44.120.36/Citrix/Prodweb/?LaunchApp=ABLFEDA_DG_DeptOrderEntry`
- `ABLFEDA_DG_DesktopLauncher` -> `http://10.44.120.36/Citrix/Prodweb/?LaunchApp=ABLFEDA_DG_DesktopLauncher`
- `ABLFEDA_DG_FirstNet` -> `http://10.44.120.36/Citrix/Prodweb/?LaunchApp=ABLFEDA_DG_FirstNet`
- `ABLFEDA_DG_HIMPhysicianAnalysis` -> `http://10.44.120.36/Citrix/Prodweb/?LaunchApp=ABLFEDA_DG_HIMPhysicianAnalysis`
- `ABLFEDA_DG_PhaMedMgrRetail` -> `http://10.44.120.36/Citrix/Prodweb/?LaunchApp=ABLFEDA_DG_PhaMedMgrRetail`
- `ABLFEDA_DG_RadExamMgmt` -> `http://10.44.120.36/Citrix/Prodweb/?LaunchApp=ABLFEDA_DG_RadExamMgmt`
- `ABLFEDA_DG_SpecimenLogin` -> `http://10.44.120.36/Citrix/Prodweb/?LaunchApp=ABLFEDA_DG_SpecimenLogin`
- `ABLFEDA_PowerChart` -> `http://10.44.120.36/Citrix/Prodweb/?LaunchApp=ABLFEDA_PowerChart`
- `ABLFEDA_ReportRequest` -> `http://10.44.120.36/Citrix/Prodweb/?LaunchApp=ABLFEDA_ReportRequest`
- `ABLFEDA_ReportRequestMaint` -> `http://10.44.120.36/Citrix/Prodweb/?LaunchApp=ABLFEDA_ReportRequestMaint`
- `ABLFEDA_RevenueCycle` -> `http://10.44.120.36/Citrix/Prodweb/?LaunchApp=ABLFEDA_RevenueCycle`

Treat the approved list above as the source of truth for FEDA shortcut selection in this skill revision. Pull the correct mapping from that list based on the DataLoader `citrixApp` value rather than re-deriving it from templates or helpers.

Before leaving a block as `""`, cross-reference the workflow CSV app shortcut field:

- if the CSV shortcut contains `ABLFHIR`, put that literal value into the commented DH2 `citrixShortcut` line
- if the CSV shortcut contains `ABLFEDA`, put that literal value into the active FEDA `citrixShortcut` line
- if the CSV does not contain a matching shortcut value for that environment, leave that block at `""` unless it already had a literal shortcut

Treat the CSV shortcut text as raw literal text and copy it exactly.

### 3. Temporary multi-shortcut scaffolding

Keep the single-`citrixShortcut` pattern as the default. Only introduce numbered shortcut variables when the cleaned workflow genuinely launches multiple Citrix URLs.

When a workflow needs more than one Citrix launch:

- keep or add matching globals such as `citrixApp1`, `citrixApp2`, `citrixShortcut1`, `citrixShortcut2`, and `citrixShortcut3`
- align the numbering with launch order in the cleaned script
- keep each launch block pointed at its matching shortcut variable instead of reusing the first shortcut everywhere
- wire each shortcut from the matching workflow CSV app header when one already exists, such as `PowerChart`, `RevenueCycle`, `AppBar`, `firstnet`, or `ReportRequestmaint`
- if the loader already contains separate literal DH2 or FEDA shortcut lines for numbered variables, preserve that shape and refresh each variable independently
- if the workflow truly needs temporary scaffolding and no stable shared name exists yet, numbered shortcut variables are acceptable until the loader can be normalized later

Prefer this temporary loader shape:

```text
global citrixApp1, citrixApp2, citrixShortcut1, citrixShortcut2

Set citrixApp1 = "RevenueCycle"
Set citrixApp2 = "PowerChart"

//Put performance_data.RevenueCycle into citrixShortcut1
//Put performance_data.PowerChart into citrixShortcut2
```

And keep the cleaned script aligned with that numbering:

```text
Run "CTX/AbilitiesCitrixMethods".SCL_LaunchAndLoginCitrix citrixShortcut1, sutUsername, sutPassword
...
Run "CTX/AbilitiesCitrixMethods".SCL_LaunchAndLoginCitrix citrixShortcut2, sutUsername, sutPassword
```

Do not duplicate the same literal URL across every numbered shortcut unless the local evidence shows the workflow really launches the same Citrix target each time.

### 4. Match loader names to CSV headers

Keep the loader and CSV headers aligned. Common examples:

- `millUsername1`, `millUsername2`, `millUsername3`
- `PowerChart`
- `RevenueCycle`
- `AppBar`

Do not invent a new app header if the suite already uses one for the same launch type.

When a workflow CSV already has the app header, still preserve any existing literal shortcut already present in the DH2 block. For the FEDA block, prefer the `citrixApp`-derived `ABLFEDA_<AppName>#` value.

If that CSV app-header value clearly identifies an environment by containing `ABLFHIR` or `ABLFEDA`, use it to populate the matching DH2 or FEDA `citrixShortcut` block in the loader when that block is currently blank.

### 5. Preserve literal values

Copy values exactly as written in the loader when syncing to CSV:

- preserve `\x` sequences
- preserve capitalization and spacing
- preserve URLs literally
- do not normalize path separators

## Verification

### Script validator tool

Run the suite's script validator tool after edits are complete for Fast/Normal edit runs only:

- `Scripts/<workflow>.script`

Validator location:

- `C:\Users\KS078306\Desktop\codex-skills\eggplant-script-cleaner\tools\cleanplant-validate.ps1`

Dry Run rule:

- do not run this validator in Dry Run
- include the exact command in dry-run output as a planned step only

### SearchRectangle extractor aliases

For SearchRectangle extraction requests in skill prompts, map these phrases to:

- `tools/extract_search_rectangles.py`

Accepted short forms:

- `run recs`
- `run rects`
- `run searchrect`
- `rr`

Default interpretation when the user keeps it brief (for example `run recs on <workflow>`):

Shortcut form also accepted: `/cleanPlant rr` (optionally `/cleanPlant rr on <workflow>`).

- script path: `Scripts/<workflow>.script`
- result log: latest successful `Results/<workflow>/<run-id>/LogFile.txt`
- include `--exclude-login-artifacts` unless user says otherwise
- output files: `temp/<workflow>.searchrect.json` and `temp/<workflow>.searchrect.csv`
Preferred command:
```powershell
& 'C:\Users\KS078306\Desktop\codex-skills\eggplant-script-cleaner\tools\cleanplant-validate.ps1' -Workflow '<workflow>' -SuiteRoot '<suite-root>' -ConversionMode On -FailureMode Verbose
```

Then:

- fix any validator findings
- re-run validator until no blocking findings remain
- include validator output summary in the final handoff (or explicitly state validator was unavailable and why)

### Required one-command post-check

Run one command that checks all required leftovers and structure rules for the target workflow, then fix all hits before finishing (Fast/Normal edit runs only).

Dry Run rule:

- do not run this post-check command in Dry Run
- include the exact command in dry-run output as a planned step only

Example PowerShell command (replace `<workflow>`):

```powershell
$wf="<workflow>"; $s="Scripts\$wf.script"; $r="Resources";
$left=rg -n "StartMovie|StopMovie|CaptureScreen|dismissRulesOfRoad|selectPlatform|loginExe|Params platform|appDomainName|millenniumDomain|beginScript|endScript|LogSuccess|SerachRectangle" $s;
$a=(rg -n 'wfTestCase' $s | Measure-Object).Count; $b=(rg -n 'EndTestCase wfStep' $s | Measure-Object).Count;
$scaleBefore=(rg -n 'ScaleRecovery' $s | Measure-Object).Count; $hasCatch=(rg -n 'catch exception' $s | Measure-Object).Count;
$hasSecondaryLogin=(rg -n 'Run "MIL/Millennium"\.login millUsername([2-9][0-9]*), millPassword' $s | Measure-Object).Count;
$hasEdgeReset=(rg -n 'taskkill /f /IM msedge\.exe' $s | Measure-Object).Count;
$hasWindowsRun=(rg -n 'TypeText (Windowskey|windowsKey), "r"' $s | Measure-Object).Count;
$secondaryGateOk=($hasSecondaryLogin -eq 0) -or (($hasEdgeReset -ge 1) -and ($hasWindowsRun -ge 1));
$csvOk=(Test-Path "$r/${wf}_LoginData.csv") -and (Test-Path "$r/${wf}_WorkflowData.csv");
"wfTestCase=$a EndTestCase=$b ScaleRecoveryHits=$scaleBefore CatchHits=$hasCatch SecondaryLoginHits=$hasSecondaryLogin SecondaryResetHits=$hasEdgeReset SecondaryRunBoxHits=$hasWindowsRun SecondaryGateOk=$secondaryGateOk CsvPresent=$csvOk"; $left
```

Interpretation guardrails for the one-command post-check:

- treat the regex scan as a fast heuristic, not a parser
- before editing, confirm each hit is active executable code (not comments, dead templates, or string literals)
- for any ambiguous hit, verify with local code context before removing or rewriting
- secondary-user handoff guardrail is non-skippable: if `SecondaryGateOk=False` after first pass, insert the reset-and-relaunch pattern before the secondary launch path, then re-run post-check and validator

Expected outcome:

- leftover scan prints no matches
- `wfTestCase` count equals `EndTestCase wfStep` count
- script includes `catch exception` and exactly two `ScaleRecovery` hits in the ending recovery region (one immediately before `catch exception`, one inside `catch`)
- `SecondaryGateOk=True` (or `SecondaryLoginHits=0`)
- both required workflow CSV files exist (`*_LoginData.csv` and `*_WorkflowData.csv`)

Search the final script for these leftovers and remove them unless still required:

- `StartMovie`
- `StopMovie`
- `CaptureScreen`
- `dismissRulesOfRoad`
- `selectPlatform`
- `loginExe`
- `Params platform`
- `appDomainName`
- `millenniumDomain`
- `Run "VA_Common_Workflows".beginScript`
- `Run "VA_Common_Workflows".endScript`
- `LogSuccess`

Treat the `LogError` search as a review step, not a blanket delete. Keep `LogError(...)` statements that are part of exception handling, catch blocks, recovery diagnostics, or other active failure-reporting paths.

Then verify:

- each `wfTestCase` still closes with `EndTestCase wfStep`
- remove any extra/orphan `EndTestCase wfStep` lines so total `EndTestCase wfStep` count matches active `wfTestCase` blocks
- if a new `Run "CTX/AbilitiesCitrixMethods".wfTestCase "..."` starts, the previous workflow-driving block must already be closed with `EndTestCase wfStep`
- keep workflow-driving executable lines inside a `wfTestCase` block rather than between `EndTestCase wfStep` and the next `wfTestCase` start
- utility or session-reset commands that do not advance business workflow steps (for example `Windows+R` and `taskkill /f /IM msedge.exe`) may remain outside `wfTestCase` blocks
- if a trailing workflow action (for example `Click ...Button_SaveandClose`) appears after `EndTestCase wfStep`, move that action above `EndTestCase wfStep` so it remains inside the active `wfTestCase`
- the launch path uses `citrixShortcut` or the required numbered shortcut variables, together with `sutUsername` and the correct `millUsername*`
- if the script has any secondary Millennium login (`millUsername2` or higher), enforce the secondary-user handoff guardrail: an unconditional Windows Run dialog reset (`taskkill /f /IM msedge.exe`) must execute before the secondary launch/login block
- recheck step: at the end of validation, inspect both DH2 and FEDA `citrixShortcut`/`citrixShortcut*` lines again; if any are still `""`, re-read the DataLoader `citrixApp`/`citrixApp*` values and apply the approved ABLFHIR/ABLFEDA mapping lists again before finishing
- the script keeps workflow-driving waits and popup handling
- `ScaleRecovery` appears only in the ending recovery region (immediately before `catch exception` and inside catch), not after mid-workflow app exits
- the loader reads the values that now live in the CSVs
- the CSV files exist for the workflow; create missing `*_LoginData.csv` and `*_WorkflowData.csv` files before finishing when they were absent at start
- the CSV files remain one header row and one data row unless the suite already requires otherwise
- run a DataLoader syntax/structure check for `Scripts/DataLoader/<workflow>_DataLoader.script` (at minimum: balanced `if/end if`, `try/catch/end try`, and no unresolved variable references introduced by conversion)
- run a CSV integrity check for `*_LoginData.csv` and `*_WorkflowData.csv` (at minimum: required headers present, one active data row by default unless workflow evidence requires more, and no header/value column-count mismatch)
- final linter gate: re-run `cleanplant-validate.ps1` after all post-check fixes and only finish when this last validator run is clean

## Reference

Use [references/nbs-nonfunctional-checklist.md](references/nbs-nonfunctional-checklist.md) as the default conversion checklist.
