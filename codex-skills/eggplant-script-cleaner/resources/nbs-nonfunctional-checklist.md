# CleanPlant Checklist

Use this checklist when converting a VA National Baseline Suite Eggplant workflow from functional to non-functional.

## Fast Mode (optional)

Use when speed is requested and the workflow matches common suite patterns:

- run preflight classifier and choose `standard` vs `complex` path before editing
- run context reads in parallel
- reuse cached parsed lookups for `workflowUsers.xlsm` and `ABLFHIR_CitrixShortcuts.csv` when valid
- apply template-first launch/recovery/exit/credential updates with anchored delta-only patches
- skip sections already compliant with CleanPlant rules
- create/update workflow CSVs in one pass from a single data map (`*_LoginData.csv`, `*_WorkflowData.csv`)
- run validator once, apply targeted fixes only for reported findings, then re-run
- if targeted validator fixes still fail, escalate remaining issues to normal-mode deep pass
- run validator + one-command post-check, then re-run validator as the final linter gate

## 1. Read everything first

- run a parallel context-gather pass: read the target script, DataLoader, and existing workflow CSV files together
- read the full target `.script`
- read the matching DataLoader
- read the matching workflow CSV files in `Resources`
- if any required workflow CSV file is missing, create it during conversion using one header row and one data row
- if legacy or mismatched workflow CSV names are present for this workflow, auto-rename them to canonical wfName-based names before reading or writing CSV values
- canonical CSV names are: Resources/<wfName>_LoginData.csv and Resources/<wfName>_WorkflowData.csv
- if both canonical and legacy/mismatched CSV sets exist, keep canonical as source-of-truth and report the duplicate legacy set instead of overwriting canonical data
- if the DataLoader uses `millUsername` or `millUsername*`, read `references/workflow-usernames.md`
- if the script name still contains legacy terms such as `Regression` or `Regression-Testing-Script`, scan the suite for references to the current script name before renaming any file on disk

## 2. Normalize workflow naming

- run a reference scan for the current script name before renaming any script file on disk
- check callers, DataLoader path strings, suite metadata/manifests, and workflow-specific helper/resource names that may still point at the old filename
- if the scan finds external dependencies that should not be changed in the same pass, stop and leave the rename for a separate follow-up instead of silently renaming only the script file
- if the workflow filename contains one or more spaces, replace each contiguous space sequence with `-` for the canonical workflow filename before any further validation or conversion steps
- apply the same space-to-hyphen normalization to associated workflow files (`Scripts/<wf>.script`, `Scripts/DataLoader/<wf>_DataLoader.script`, `Resources/<wf>_LoginData.csv`, `Resources/<wf>_WorkflowData.csv`)
- rename the script file on disk to the cleaned workflow name when legacy terms such as `Regression` or `Regression-Testing-Script` are present
- align the cleaned name across the script filename, `TEST CASE NAME: ...`, `Set wfName = "..."`, and any `wfDataLoader` path built from it

## 3. Remove functional scaffolding

- remove `Params platform, appDomainName, millenniumDomain`
- remove default platform/domain setters
- remove direct-login branches using `selectPlatform`, `openSupportFolderFromStoreFront`, and `loginExe`
- remove old globals such as `domain`, `citrixApp`, `citrixURL`, and `citrixCredentialID` when unused

## 4. Remove startup noise

- remove `imagefound "OK"` pre-login handlers when they only support desktop/Citrix startup noise
- remove `dismissRulesOfRoad`
- remove waits tied only to that flow
- remove `StartMovie`
- remove `StopMovie`
- remove commented-out copies of deleted startup behavior
- keep `CaptureScreen` only when it is part of exception handling

## 5. Standardize launch

- use `SCL_LaunchAndLoginCitrix citrixShortcut, sutUsername, sutPassword`
- wait for the correct app-ready image or login control
- if the storefront launch block is already active and structurally correct, leave it unchanged; an active `WaitFor imgWait*<number>, "Textbox_Login_Username"` line is acceptable and does not need to be rewritten to `imgWait*7`
- if that active block already matches the launch structure, preserve the whole block unchanged when the only differences are the `imgWait*<number>` multiplier and `millUsername` versus the matching `millUsername*` variable
- when legacy scaffolding already includes login-sequence `wfTestCase` labels, keep those labels unchanged as the block header; do not replace the whole block header with `wfTestCase "Launch Application"`, and only normalize launch-body lines under the preserved header
- log with `Millennium shortcut:` rather than old application-name wording when applicable
- use the CSV-driven `millUsername*` field that matches the workflow
- for Revenue Cycle or AppBar, keep the same launch structure but use the correct app-ready image or wait target
- if the workflow logs in again with a secondary username such as `millUsername2`, add the temporary fresh-session reset first:
  `Windows+R` -> `taskkill /f /IM msedge.exe` -> relaunch -> log in with `millUsername2`
- use that reset-and-relaunch pattern only for the secondary-user handoff path, not for ordinary single-user launches

## 6. Convert explicit step wrappers

- replace `Log "Step ..."` / `Log "End Step ..."` wrappers with `wfTestCase` / `EndTestCase wfStep`
- preserve visual separator comment blocks (for example `(********************************************************************************)`) used to distinguish sections/test cases

## 7. Remove verification-only logic

- remove `LogSuccess` / `LogError` checks that only confirm state
- remove non-exception `CaptureScreen`
- remove pass/fail `If ImageFound(...) then ... else ... End If` blocks that only verify state
- keep checks that still click, branch, retry, dismiss popups, or otherwise drive the workflow
- keep `LogError(...)`, `CaptureScreen`, and similar diagnostics when they live inside `catch` blocks, exception handling, or recovery/reporting paths
- keep optional `If ImageFound(...) then` gates when the found state unlocks follow-on workflow actions such as manual entry, required field population, or conditional popup handling
- do not replace those optional gates with a bare `WaitFor`
- replace validation-only checks with `WaitFor` or `throw` if the workflow still needs a hard stop
- let `cleanplant-validate.ps1` perform the `SerachRectangle` -> `SearchRectangle` conversion on the main workflow script

## 8. Normalize exits and recovery

- determine the launched/exited app first before changing exit keystrokes
- use `TypeText altKey` then `wait 2` then `TypeText "t"` then `wait 2` then `TypeText "x"` for PowerChart exits and Appbar-launched PathNet exits
- use `TypeText altKey` then `wait 2` then `TypeText "f"` then `wait 2` then `TypeText "x"` for RevenueCycle exits
- if the app is not explicitly PowerChart, Appbar-launched PathNet, or RevenueCycle, keep the existing exit scaffolding instead of forcing one of those normalized exit patterns
- do not apply the PowerChart exit sequence to RevenueCycle workflows
- rewrite short toolbar, menu, or image-based exit blocks into the matching normalized exit when possible
- add `Run "CTX/AbilitiesCitrixMethods".ScaleRecovery` immediately before `catch exception`
- keep `Run "CTX/AbilitiesCitrixMethods".ScaleRecovery` inside catch after exception handling

## 9. Sync DataLoader values into CSVs

- remove unused DataLoader scaffolding once CSV wiring is in place and the cleaned script no longer uses direct-login/platform paths
- remove DataLoader `Params platform, appDomainName, millenniumDomain` when unused
- remove DataLoader default setters for `platform`, `appDomainName`, and `millenniumDomain` when unused
- remove unused DataLoader globals and assignments such as `domain`, `citrixURL`, and `citrixCredentialID`
- keep `citrixApp` or `citrixApp*` only when still actively used (for shortcut derivation, app-token mapping, launch-order intent, or other active loader logic)
- for numbered app tokens (`citrixApp1`, `citrixApp2`, etc.), comment out the `Set citrixApp<number> = "..."` line only after the matching DH2 `ABLFHIR` `citrixShortcut<number>` literal has been placed in the loader (or confirmed from CSV/local evidence/helper lookup)
- do not comment `citrixApp<number>` before the matching `ABLFHIR` shortcut is populated


- keep `sutUsername` and `sutPassword` hardcoded in the DataLoader credential block (DH2 commented, FEDA active)
- put `millUsername*` and `millPassword*` in `*_LoginData.csv`
- put workflow inputs in `*_WorkflowData.csv`
- put `citrixShortcut` in `*_WorkflowData.csv` under `PowerChart`, `RevenueCycle`, `AppBar`, or the existing app header
- if the workflow truly launches multiple Citrix apps, keep numbered shortcut variables such as `citrixShortcut1`, `citrixShortcut2`, and `citrixShortcut3` and map each one to the matching workflow-data app header
- if any required workflow CSV is missing (`*_LoginData.csv`, `*_WorkflowData.csv`), create it in `Resources` and populate it from current loader/script values
- if a local `workflowUsers.xlsm` workbook exists, use it for `millUsername*` mapping; if it does not exist, leave that username-mapping section for manual user completion
- use workbook confirmation rather than the workflow name alone when deciding whether combined username handling applies; normalize legacy workflow names by removing `Regression`, `Regression-Testing-Script`, and `_DataLoader` before comparing
- if `Script Type` does not positively identify a combined workflow, do not use the combined username path just because the workflow name contains `and`, `combine`, `combined`, or `combination`
- update the loader to read those fields from `performance_data`
- at the start of the functional branch, keep both credential blocks:
  `DH2` commented out and `FEDA` active
- if `citrixShortcut` is already populated in the DH2 or FEDA block, keep that exact value
- if `citrixShortcut` is missing in either block, set it to `""`
- for the DH2 shortcut, use approved hardcoded mappings from `C:\Users\KS078306\Desktop\codex-skills\eggplant-script-cleaner\ABLFHIR_CitrixShortcuts.csv`
- for the FEDA shortcut, use approved hardcoded mappings from `C:\Users\KS078306\Desktop\codex-skills\eggplant-script-cleaner\ABLFEDA_CitrixShortcuts.csv`
- for both environments, match `AppName` to DataLoader `citrixApp` (case-insensitive, treat optional `.exe` suffixes as equivalent) and copy the mapped `citrixShortcut` value exactly
- if no approved mapping exists for the app token, keep the existing literal value if one exists; otherwise keep `""` and report the unmapped token
- cross-reference the workflow CSV app shortcut:
  if it contains `ABLFHIR`, copy it into the DH2 shortcut line
  if it contains `ABLFEDA`, copy it into the FEDA shortcut line
- if `citrixApp` is missing, do not add it
- when a workflow needs multiple launches, keep the numbering aligned across `citrixApp*`, `citrixShortcut*`, the workflow CSV headers, and the cleaned script launch order
- if separate numbered DH2 or FEDA literal shortcut lines already exist, preserve that shape and refresh each numbered variable independently
- do not duplicate the same literal URL across every numbered shortcut unless the checked-in evidence shows the workflow really launches the same Citrix target each time
- preserve literal values exactly as written when syncing:
  keep `\x` sequences, capitalization, spacing, and URLs unchanged

## 10. Final scan

Search for leftovers:

- `StartMovie`
- `StopMovie`
- `CaptureScreen`
- `dismissRulesOfRoad`
- `selectPlatform`
- `loginExe`
- `Params platform`
- `appDomainName`
- `millenniumDomain`
- `LogSuccess`
- `LogError`
- treat `LogError` hits as review items rather than automatic removals; keep exception-path and recovery-path failure logging

Confirm:

- every `wfTestCase` closes with `EndTestCase wfStep`
- workflow-driving actions stay inside `wfTestCase` blocks
- utility/session-reset commands (for example `Windows+R` + `taskkill /f /IM msedge.exe`) may be left outside `wfTestCase` blocks when they do not advance business workflow steps
- the loader and CSV headers match
- the launch path uses `citrixShortcut` or the required numbered shortcut variables, together with `sutUsername` and the correct `millUsername*`
- recheck DH2 and FEDA shortcuts at the end of validation; if any `citrixShortcut`/`citrixShortcut*` lines are still `""`, rerun lookup from the approved hardcoded CSV mapping lists (`ABLFHIR_CitrixShortcuts.csv` and `ABLFEDA_CitrixShortcuts.csv`) and fill any found literals
- the script keeps workflow-driving waits and popup handling
- the script includes `ScaleRecovery` before `catch exception` and again inside catch
- the loader reads the values that now live in the CSVs
- the workflow has both required CSV files (`*_LoginData.csv`, `*_WorkflowData.csv`); create missing files before finishing
- the CSV files remain one header row and one data row unless the suite already requires otherwise
- the script still performs the workflow steps, not just the cleanup
- run the suite script validator tool on the workflow script, fix findings, and re-run until clean (or document clearly if validator tooling is unavailable)
- run `C:\Users\KS078306\Desktop\codex-skills\eggplant-script-cleaner\tools\cleanplant-validate.ps1 -ConversionMode On` against the workflow, fix findings, and re-run until clean

Run a one-command post-check before finishing and fix all hits:

```powershell
$wf="<workflow>"; $s="Scripts\$wf.script"; $r="Resources";
$left=rg -n "StartMovie|StopMovie|CaptureScreen|dismissRulesOfRoad|selectPlatform|loginExe|Params platform|appDomainName|millenniumDomain|LogSuccess|SerachRectangle" $s;
$a=(rg -n 'wfTestCase' $s | Measure-Object).Count; $b=(rg -n 'EndTestCase wfStep' $s | Measure-Object).Count;
$sr=(rg -n 'ScaleRecovery' $s | Measure-Object).Count; $ct=(rg -n 'catch exception' $s | Measure-Object).Count;
$csvOk=(Test-Path "$r/${wf}_LoginData.csv") -and (Test-Path "$r/${wf}_WorkflowData.csv");
"wfTestCase=$a EndTestCase=$b ScaleRecoveryHits=$sr CatchHits=$ct CsvPresent=$csvOk"; $left
```

Expected outcome:

- no leftover matches printed
- `wfTestCase` equals `EndTestCase wfStep`
- `catch exception` exists and `ScaleRecovery` has at least two hits
- both required workflow CSV files exist
- after post-check fixes, run `cleanplant-validate.ps1` one last time and only finish when that final validator run is clean












