# Sanitize and Sync Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish every recoverable user-maintained skill on a review branch without credentials, generated artifacts, caches, nested repositories, or oversized files.

**Architecture:** Copy recoverable skills into `codex-skills/` with explicit artifact exclusions, then sanitize credential-bearing scripts to read environment variables. A repository validator enforces the public-publication boundary before commit and push; existing top-level skill copies are refreshed from their sanitized collection copies.

**Tech Stack:** PowerShell 5.1, Git, robocopy, YAML frontmatter, GitHub branches.

## Global Constraints

- Do not copy `.system`, backup directories, broken junctions, `.skill-build`, `outputs`, `__pycache__`, `*.pyc`, generated report HTML, or nested `.git` directories.
- Do not publish private-key blocks, GitHub/AWS/Slack token prefixes, or literal password/secret assignments.
- Do not track a file larger than 100,000,000 bytes.
- Require `SKILL.md` in every directory immediately beneath `codex-skills/`.
- Preserve the existing `codex-skills/<skill-name>` layout and refresh existing legacy top-level copies.
- Push only `codex/sanitize-and-sync-all-skills`; do not push directly to `main`.

---

### Task 1: Add the publication validator

**Files:**
- Create: `tools/tests/Test-PublicSkillRepository.Tests.ps1`
- Create: `tools/Test-PublicSkillRepository.ps1`

**Interfaces:**
- Consumes: repository root passed as `-Root <path>`.
- Produces: exit success with a `PASS` message for a clean collection; throws with categorized file paths for violations.

- [ ] **Step 1: Write the failing validator test**

Create clean and dirty temporary repositories. The clean fixture contains `codex-skills/example/SKILL.md` and `Password = $env:EXAMPLE_PASSWORD`; the dirty fixture contains `Password = 'embedded-secret'`. Invoke `tools/Test-PublicSkillRepository.ps1` for both and require clean success plus dirty failure.

- [ ] **Step 2: Run the test to verify RED**

Run:

```powershell
& .\tools\tests\Test-PublicSkillRepository.Tests.ps1
```

Expected: failure because `tools/Test-PublicSkillRepository.ps1` does not exist.

- [ ] **Step 3: Implement the validator**

Inspect files beneath `codex-skills/` and tracked legacy skill directories. Reject missing `SKILL.md`, forbidden directories/files, files above 100,000,000 bytes, private-key headers, known access-token prefixes, and literal assignments to `password`, `passwd`, `secret`, or `api_key`. Permit environment-variable and explicit placeholder assignments.

- [ ] **Step 4: Run the test to verify GREEN**

Run the same command. Expected: both fixture assertions pass and the script prints `PASS`.

- [ ] **Step 5: Commit the validator**

```powershell
git add tools
git commit -m "test: enforce sanitized skill publication"
```

### Task 2: Synchronize recoverable skill sources

**Files:**
- Modify: `codex-skills/*`
- Add: `codex-skills/app-tier-scp-investigator/*`

**Interfaces:**
- Consumes: accessible non-junction directories beneath `C:\Users\DP096786\.codex\skills` and `\\dh2ffs01\ABLPUB\codex skill\app-tier-scp-investigator`.
- Produces: one complete directory per recoverable skill beneath `codex-skills/`.

- [ ] **Step 1: Mirror each accessible skill with exclusions**

Use robocopy for each exact source/destination pair with `/E`, excluding `.git`, `.skill-build`, `outputs`, `__pycache__`, `*.pyc`, and generated `report*.html` files. Exclude `.system`, `*.backup-*`, and the four broken junctions from the source list.

- [ ] **Step 2: Verify the inventory**

Require 33 directories beneath `codex-skills/`, each with `SKILL.md`. Record the four unavailable names as validation output rather than inventing files.

- [ ] **Step 3: Run the publication validator to verify RED**

```powershell
& .\tools\Test-PublicSkillRepository.ps1 -Root .
```

Expected: failure identifying credential-bearing files copied from the local collection.

### Task 3: Replace embedded credentials

**Files:**
- Modify: `codex-skills/gatling-converter/scripts/run_gatling_converter.ps1`
- Modify: `codex-skills/gatling-scenario-data-creator/scripts/run_gatling_scenario_data_creator.ps1`
- Modify: `codex-skills/sqlplus/scripts/run_oracle_query.ps1`
- Modify: affected `SKILL.md` files that document literal credentials

**Interfaces:**
- Consumes: environment variables named in each script's error message and corresponding skill documentation.
- Produces: the same generated configuration and connection behavior when variables are supplied; a clear missing-variable failure otherwise.

- [ ] **Step 1: Add environment-variable expectations to existing script tests or focused parse/behavior checks**

Require that scripts contain no literal password assignments, parse under PowerShell, and fail with the exact missing environment-variable name when their relevant named profile is selected without credentials.

- [ ] **Step 2: Run checks to verify RED**

Expected: current copied scripts fail because credentials are embedded and the documented variables are absent.

- [ ] **Step 3: Implement minimal substitutions**

Use `GATLING_CONFIG_PASSWORD` for generated Gatling configuration. Use profile-specific `FPABL_DB_PASSWORD`, `ABLFHIR_DB_PASSWORD`, `FPABL_ALT_DB_PASSWORD`, `FPABL2_DB_PASSWORD`, and `FPSG_DB_PASSWORD` variables for database profiles. Preserve explicit credential parameters where already supported.

- [ ] **Step 4: Update skill instructions**

Replace literal credential examples with the exact environment-variable names and state that agents must obtain credentials through approved secret management rather than commit them.

- [ ] **Step 5: Run script checks and the publication validator to verify GREEN**

Expected: all modified PowerShell files parse, focused checks pass, and the repository validator reports no credential violations.

### Task 4: Refresh legacy copies and validate every skill

**Files:**
- Modify: existing top-level skill directories that duplicate `codex-skills/<name>`.

**Interfaces:**
- Consumes: sanitized collection copies.
- Produces: identical hashes for each duplicated top-level skill and its `codex-skills` counterpart.

- [ ] **Step 1: Mirror sanitized duplicates**

For each existing top-level skill directory with a same-named directory beneath `codex-skills/`, mirror the sanitized collection copy over the legacy copy using exact validated paths.

- [ ] **Step 2: Validate metadata and syntax**

Parse every `SKILL.md` frontmatter for `name` and `description`, require lowercase/hyphen directory names, and parse every `.ps1` file with the PowerShell parser.

- [ ] **Step 3: Run available non-destructive tests**

Run repository validator tests plus existing self-contained tests that do not connect to lab systems or modify remote state.

- [ ] **Step 4: Review repository diff**

Run `git status --short`, `git diff --stat`, `git diff --check`, and inspect changed file names. Confirm no `.system`, generated output, cache, nested `.git`, credential file, or oversized file is staged.

### Task 5: Commit and upload the branch

**Files:**
- Modify: Git index and branch history only.

**Interfaces:**
- Consumes: validated working tree.
- Produces: pushed branch `origin/codex/sanitize-and-sync-all-skills` and a GitHub compare URL.

- [ ] **Step 1: Run final verification**

Run the publication validator, metadata checks, PowerShell parse checks, `git diff --check`, and staged secret/size scan from a clean command invocation.

- [ ] **Step 2: Commit the synchronized collection**

```powershell
git add codex-skills tools docs
git add eggplant-runner gatling-converter gatling-fixer gatling-pipline gatling-runner gatling-scenario-data-creator sqlplus ssh ssh-win
git commit -m "feat: publish sanitized Codex skill collection"
```

- [ ] **Step 3: Push the working branch**

```powershell
git push --set-upstream origin codex/sanitize-and-sync-all-skills
```

- [ ] **Step 4: Provide PR handoff**

Return `https://github.com/reddydamodar38/claude-skills/compare/main...codex/sanitize-and-sync-all-skills?expand=1` with the exact included/excluded skill counts and verification evidence.
