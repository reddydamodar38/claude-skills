---
name: eggplant-converter
description: Convert functional Eggplant scripts into perf-style scripts using a repeatable scaffold, data migration pattern, workflow instrumentation, and cleanup conventions.
---

# Functional → Perf Script Conversion Skills

This document captures the repeatable skill/pattern used to convert a **functional Eggplant script** into a **perf-style script**.

## 1) Perf Scaffold Pattern

- Add workflow globals:
  - `global wfName, wfStep, wfStepNum, imgWait, pauseDuration`
- Add data/login globals required by the script flow.
- Initialize workflow:
  - `Set wfName = "<Perf-Script-Name>"`
  - `Set wfDataLoader = ("DataLoader/" & wfName & "_DataLoader")`
  - `Run wfDataLoader`
- Add fallback defaults:
  - `if platform is empty then set platform to "EOD"`
  - `if appDomainName is empty then set appDomainName to "FPSG"`
  - `if millenniumDomain is empty then set millenniumDomain to "FPSG"`

## 2) Data Source Migration

- Functional scripts commonly read:
  - `JSONValue(file ResourcePath("testdata.json"))`
  - `JSONValue(file ResourcePath("Powerchart.json"))`
- Perf style shifts to **DataLoader-fed globals**.
- Keep old JSON blocks as comments (optional) for traceability.

## 3) Step Instrumentation

- Replace plain step logs with:
  - `Run "CTX/AbilitiesCitrixMethods".wfTestCase "<Step Description>"`
  - `EndTestCase wfStep`
- Preserve business flow sequence exactly.

## 4) Timing Normalization

- Convert fixed waits (`30/60/120/200`) to `imgWait` scale where practical:
  - `WaitFor: imgWait`
  - `WaitFor: imgWait*2`, `imgWait*4`, etc.

## 5) Runtime Instrumentation

- Add standardized run logs at start.
- Add movie control:
  - `StartMovie ["<name>"]` (or string variant)
  - `StopMovie`

## 6) Error & Cleanup Model

- Preserve `try/catch` style.
- Keep cleanup logic if functional script depends on it.
- Finalize with:
  - `Run "UTIL/Common".cleanupSelectedPlatform platform`

## 7) Practical Conversion Checklist

1. Copy functional script flow.
2. Add perf scaffold + DataLoader.
3. Globalize data variables.
4. Wrap each major step in `wfTestCase`/`EndTestCase`.
5. Normalize waits to `imgWait` style.
6. Preserve validations, screenshots, and cleanup behaviors.
7. Add `StartMovie/StopMovie`.

## 8) Artifact Generated in This Task

- Converted script path:
  - `Converted_Perf_Scripts/VA-Amb-Health-Maintenance-Invitations-Regression.script`
