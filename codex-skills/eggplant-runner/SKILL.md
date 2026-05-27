---
name: eggplant-runner
description: Run Eggplant suite workflows on a remote Linux host over SSH using Docker, following Jenkins eggplant2gatling 'Run Eggplant using Docker' stage behavior, then validate run status from Eggplant logs and collect results artifacts.
---

# Eggplant Runner

Use this skill when you need to execute Eggplant on a remote host with Docker through SSH.

This skill is based on the Jenkins stage `Run Eggplant using Docker` from:
- `C:/Users/prakash/Desktop/project/torq-image/casc_configs/eggplant2gatling.groovy`

It mirrors the same run model and uses `docker run`.

## Uses
- [$ssh](C:/Users/prakash/.codex/skills/ssh/SKILL.md) for remote connectivity patterns.

## Remote Target Defaults
- Default remote host: `10.191.205.92`
- Built-in host alias: `fhirinj01` -> `10.191.205.92`
- Default SUT domain profile: `ABLA`
- ABLA profile defaults: `sutHost=dh2vablasut02.dh2.cerner.com` and ABLA-specific Citrix launch URL preference
- FHIR profile defaults: `sutHost=DH2VFHIRSUT01.DH2.cerner.com` and FHIR-specific Citrix launch URL preference
- Use `-SutDomain ABLA|FHIR` to switch profile; `-EggplantIP` still overrides `sutHost` explicitly
- You can use either `-HostName` or `-HostAlias`.

## Eggplant Expert Notes
- Eggplant execution is driven by `suite_name` and `workflow_name`.
- Core runtime flags used in this pipeline model are `--end_users`, `--iterations`, and `--debug`.
- Runner defaults to duration mode (`--duration 1`) to avoid known `--iterations 1` runtime bug in some `ablepf` images.
- Default Docker image: `toolbox.dh2.cerner.com:5000/ablepf:latest`.
- Pipeline success is determined from the last line of Eggplant run log (`runscript_*.log`) second tab-separated field, expected value `SUCCESS`.
- Results are written under a per-workflow run folder and should be zipped for artifact retention.

## Workflow
1. SSH to remote host.
2. Optional setup phase (enabled by default) inspired by Jenkins `Setup Eggplant`:
- ensure workspace folders exist (`scripts`, `EggplantSuites`, `results`)
- set permissions (`chmod` best effort)
- optionally create `sutHost.csv`, `sutCredentials.csv`, `EnvConfig.dic` when corresponding inputs are provided
- resolve Citrix URL in this order:
  - explicit `-CitrixURL`
  - auto-discover `#/launch/...` URL from suite files, preferring links for selected `-SutDomain`:
    - `ABLA` -> prefers links containing `ABLA`
    - `FHIR` -> prefers links containing `ABLFHIR`
  - auto-discovery now accepts absolute and relative Citrix launch links and normalizes relative values (for example `/Citrix/...#/launch/...`) into complete URLs using the StoreFront scheme/host
  - fallback `-CitrixStoreFrontUrl` (default: `http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/default.htm#/mode/view-appshortcuts`)
- runner prints the identified Citrix URL and its source in console output
- runner warns if resolved Citrix URL is not a launch link (missing `#/launch/`)
- runner writes/overrides `sutHost.csv` each run from selected `-SutDomain` profile unless `-EggplantIP` is explicitly provided
- optionally update DataLoader Citrix URL values (`citrixShortcut`, `citrixShortcut2`) when a Citrix URL is resolved
3. Run `chown -R 1000:1000 scripts/ EggplantSuites/` (best effort).
4. Execute Eggplant image with `docker run --rm` and Jenkins-equivalent mounts/env:
- workdir: `/home/eggplant`
- env: `EGGPLANT_ACCEPT_EULA=true`, `EGGPLANT_ACCEPT_PRIVACY_AGREEMENT=true`, `TZ=America/Chicago`
- mounts:
  - preferred direct mount: `<RemoteWorkspace>/ABL_VA_NBS.suite -> /home/eggplant/automation` (use `-AutomationHostPath`)
  - legacy mount: `${workspace}/scripts/${RepoName}/${SuiteRepoPath} -> /home/eggplant/automation`
  - `${workspace}/EggplantSuites -> /home/eggplant/EggplantSuites`
  - `${workspace}/results -> /home/eggplant/results`
5. Resolve Eggplant status from log tail and mark success/failure.
6. Zip results as `eggplant_log.zip` on remote.
7. Optionally download zip artifact locally.
8. Use `-SkipSetup` to bypass setup and run only the container execution/status flow.
9. Runner preflight validates `<suite>/Scripts/<EggplantScriptName>.script` exists before Docker execution and prints close matches if not found.
10. Use `-DiagnosticMode` to capture full `docker run` output to a remote log file and print a tail preview in console.
11. If `<suite>/Resources/<EggplantScriptName>_LoginData.csv` is missing, use `-LoginDataSourceFile <existingLoginData.csv>` to copy a compatible file to the expected name before run.
12. If `<suite>/Resources/<EggplantScriptName>_WorkflowData.csv` is missing, use `-WorkflowDataSourceFile <existingWorkflowData.csv>` similarly.
13. Use `-NormalizeSuiteInfoIfScriptPresent` to run `update_suiteinfo.py` (if present in automation path) against suite and helper suites to mitigate Windows-style path issues.
14. Setup now auto-normalizes helper-suite path references across `SuiteInfo` and `.script` files, including Windows/legacy forms like `C:/EggplantSuites/...`, `N:/Wayne_Wertz/VA-Repos/...`, `<Suite_root>/../...`, and `./IPDev...` to Linux container paths under `/home/eggplant/EggplantSuites/...`.
15. Runner clears all previous contents under `${workspace}/results` before each run by default (plus stale `eggplant_log.zip` and prior diagnostic logs for that workflow); use `-SkipResultCleanup` to keep prior run artifacts.
16. Before log-status evaluation, runner creates a backup of `runscript_*.log` and removes lines matching `WARNING: The -compare: method for NSObject is deprecated.` from the active log to reduce log noise.
17. Setup auto-creates missing `SuiteInfo` files in helper suites under `${workspace}/EggplantSuites` so Linux container resolution has the required metadata files.
18. Runner now performs a hard helper-suite preflight before Docker execution: it scans suite/helper references, normalizes legacy path forms, and fails early if any referenced helper suite directory is missing.
19. Use `-SkipHelperPreflight` when you intentionally want to bypass strict helper validation and run Docker anyway.

## Run
Preferred launcher:
`pwsh -NoProfile -Command "& 'C:/Users/prakash/.codex/skills/eggplant-runner/scripts/run_skill_script.ps1' -ScriptName 'run_eggplant_podman.ps1' -- -HostAlias fhirinj01 -UserName root -KeyPath C:/Users/prakash/.ssh/id_gatling -RemoteWorkspace /home/eggplant -AutomationHostPath /home/eggplant/ABL_VA_NBS.suite -EggplantSuiteName ABL_VA_NBS -EggplantScriptName MyWorkflow -EggplantDomainUser DH2\XAAuto001 -EggplantIP 10.1.2.3 -CitrixStoreFrontUrl 'http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/default.htm#/mode/view-appshortcuts' -CitrixStoreFrontUser 'DH2\XAAuto001' -CitrixStoreFrontPassword 'Cerner1' -DownloadArtifact"`

Direct script:
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/eggplant-runner/scripts/run_eggplant_podman.ps1" -HostAlias fhirinj01 -UserName root -KeyPath C:/Users/prakash/.ssh/id_gatling -RemoteWorkspace /home/eggplant -AutomationHostPath /home/eggplant/ABL_VA_NBS.suite -EggplantSuiteName ABL_VA_NBS -EggplantScriptName MyWorkflow -EggplantDomainUser DH2\XAAuto001 -EggplantIP 10.1.2.3 -CitrixStoreFrontUrl 'http://10.191.200.35/Citrix/AblCertDedCtx_storeWeb/default.htm#/mode/view-appshortcuts' -CitrixStoreFrontUser 'DH2\XAAuto001' -CitrixStoreFrontPassword 'Cerner1' -DownloadArtifact`

Force StoreFront URL instead of auto-discovery:
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/eggplant-runner/scripts/run_eggplant_podman.ps1" -HostAlias fhirinj01 -UserName root -KeyPath C:/Users/prakash/.ssh/id_gatling -RemoteWorkspace /home/eggplant -AutomationHostPath /home/eggplant/ABL_VA_NBS.suite -EggplantSuiteName ABL_VA_NBS -EggplantScriptName MyWorkflow -EggplantDomainUser DH2\XAAuto001 -CitrixStoreFrontUser 'DH2\XAAuto001' -CitrixStoreFrontPassword 'Cerner1' -PreferStoreFrontCitrixUrl -DownloadArtifact`

Skip setup example:
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/eggplant-runner/scripts/run_eggplant_podman.ps1" -HostAlias fhirinj01 -UserName root -KeyPath C:/Users/prakash/.ssh/id_gatling -RemoteWorkspace /home/eggplant -AutomationHostPath /home/eggplant/ABL_VA_NBS.suite -EggplantSuiteName ABL_VA_NBS -EggplantScriptName MyWorkflow -EggplantDomainUser cerner\myuser -SkipSetup -DownloadArtifact`

Diagnostic example:
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/eggplant-runner/scripts/run_eggplant_podman.ps1" -HostAlias fhirinj01 -UserName root -KeyPath C:/Users/prakash/.ssh/id_gatling -RemoteWorkspace /root/eggplant -AutomationHostPath /root/eggplant -EggplantSuiteName ABL_VA_NBS -EggplantScriptName VA-PathNet-Gen-Micro-Lab-Cultures-and-Storage-Tracking-1 -EggplantDomainUser DH2\XAAuto001 -CitrixStoreFrontUser DH2\XAAuto001 -CitrixStoreFrontPassword Cerner1 -DiagnosticMode -DownloadArtifact`

LoginData mapping example:
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/eggplant-runner/scripts/run_eggplant_podman.ps1" -HostAlias fhirinj01 -UserName root -KeyPath C:/Users/prakash/.ssh/id_gatling -RemoteWorkspace /root/eggplant -AutomationHostPath /root/eggplant -EggplantSuiteName ABL_VA_NBS -EggplantScriptName VA-PathNet-Gen-Micro-Lab-Cultures-and-Storage-Tracking-1 -LoginDataSourceFile VA-PathNet-Gen-Lab-Micro-Lab-Regression-Cultures-and-Storage-Tracking-1_LoginData.csv -EggplantDomainUser DH2\XAAuto001 -CitrixStoreFrontUser DH2\XAAuto001 -CitrixStoreFrontPassword Cerner1 -PreferStoreFrontCitrixUrl -DiagnosticMode -DownloadArtifact`

LoginData + WorkflowData mapping example:
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/eggplant-runner/scripts/run_eggplant_podman.ps1" -HostAlias fhirinj01 -UserName root -KeyPath C:/Users/prakash/.ssh/id_gatling -RemoteWorkspace /root/eggplant -AutomationHostPath /root/eggplant -EggplantSuiteName ABL_VA_NBS -EggplantScriptName VA-PathNet-Gen-Micro-Lab-Cultures-and-Storage-Tracking-1 -LoginDataSourceFile VA-PathNet-Gen-Lab-Micro-Lab-Regression-Cultures-and-Storage-Tracking-1_LoginData.csv -WorkflowDataSourceFile VA-PathNet-Gen-Lab-Micro-Lab-Regression-Cultures-and-Storage-Tracking-1_WorkflowData.csv -EggplantDomainUser DH2\XAAuto001 -CitrixStoreFrontUser DH2\XAAuto001 -CitrixStoreFrontPassword Cerner1 -PreferStoreFrontCitrixUrl -DiagnosticMode -DownloadArtifact`

Duration + SuiteInfo normalization example:
`pwsh -NoProfile -File "C:/Users/prakash/.codex/skills/eggplant-runner/scripts/run_eggplant_podman.ps1" -HostAlias fhirinj01 -UserName root -KeyPath C:/Users/prakash/.ssh/id_gatling -RemoteWorkspace /root/eggplant -AutomationHostPath /root/eggplant -EggplantSuiteName ABL_VA_NBS -EggplantScriptName VA-PathNet-Gen-Micro-Lab-Cultures-and-Storage-Tracking-1 -DurationMinutes 1 -NormalizeSuiteInfoIfScriptPresent -EggplantDomainUser DH2\XAAuto001 -CitrixStoreFrontUser DH2\XAAuto001 -CitrixStoreFrontPassword Cerner1 -PreferStoreFrontCitrixUrl -DiagnosticMode -DownloadArtifact`

## Foreground Default
- Default execution mode is foreground.
- Use background execution only when the user explicitly requests it.

