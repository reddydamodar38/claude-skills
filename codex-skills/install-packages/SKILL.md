---
name: install-packages
description: Run Cerner EMPlus package installation workflows. Use when Codex needs to import packages, create EMPlus package plans, build/execute plans, approve plan impact, rollback/unbuild/delete plans, complete failed steps, inspect plan details, or clear EMPlus environment locks for ABLSCALE/other domains.
---

# Install Packages

Use this skill for EMPlus package install/reinstall workflows on Windows nodes where `EMPlus.bat` and `emp-cmd` are available, usually from `C:\Program Files\Cerner EMPlus`.

## Safety

- Treat build, execute, rollback, unbuild, delete, complete-step, approve/disapprove, and clear-lock as state-changing operations. Confirm the target environment, plan ID, and package CSV before running them unless the user explicitly asked to perform that exact action.
- Prefer read-only checks first: `environments`, `plans`, `plan-details`, and package status reports.
- Do not expose hidden DB credentials from EMPlus config files. Use EMPlus commands or user-provided DB access for status checks.
- Keep package action accurate:
  - Use `install,<package>` when the package is imported but not installed in the environment.
  - Use `reinstall,<package>` when EMPlus/package status says it is already installed or `NOT_PERMANENTLY_INSTALLED`.

## Standard workflow

Run commands from:

```bat
cd /d "C:\Program Files\Cerner EMPlus"
```

### 1. Set environment

List environments if the environment ID is unknown:

```bat
EMPlus.bat environments
```

Common ABLSCALE3 value:

```bat
set envid=22399419
```

### 2. Import packages

Place `.ocd` packages under `C:\pkgimport`, then run:

```bat
EMPlus.bat import-packages --dir "C:\pkgimport"
```

### 3. Create the plan

Create a plan from the plan INI and package CSV:

```bat
EMPlus.bat create-plan --plan-file=ablscale3.ini --packages-file=packages.csv --environment-id=%envid%
```

Alternate example:

```bat
EMPlus.bat create-plan --plan-file=lntec.ini --packages-file=admin199.csv --environment-id=%envid%
```

After creation, capture the Plan ID from the output:

```bat
set planid=1009639
```

### 4. Build and execute the plan

```bat
EMPlus.bat build-plan --plan-id=%planid%
EMPlus.bat execute-plan --plan-id=%planid%
```

### 5. Plan impact review

View impact:

```bat
emp-cmd plan-impact --plan-id=%planid% --view
```

Approve impact:

```bat
emp-cmd plan-impact --plan-id=%planid% --approve
```

Disapprove impact:

```bat
emp-cmd plan-impact --plan-id=%planid% --disapprove
```

## Recovery and cleanup commands

Use these only when appropriate for the plan state.

Rollback an executed plan:

```bat
EMPlus.bat rollback-plan --plan-id=%planid%
```

Unbuild a built plan:

```bat
EMPlus.bat unbuild-plan --plan-id=%planid%
```

Delete a plan:

```bat
EMPlus.bat delete-plan --plan-id=%planid%
```

Complete a blocked/manual step:

```bat
EMPlus.bat complete-step --plan-id=%planid% --step-id=49132540
```

Inspect a specific plan:

```bat
EMPlus.bat plans --env-id=%envid% --plan-id=%planid%
EMPlus.bat plan-details --plan-id=%planid%
```

Clear an environment lock:

```bat
EMPlus.bat clear-lock --environment-id=%envid% --lock-type=3
```

## Useful examples

Complete a step and resume an existing plan:

```bat
EMPlus.bat complete-step --plan-id=1009632 --step-id=53928244
EMPlus.bat execute-plan --plan-id=1009632
EMPlus.bat plan-details --plan-id=1009632
```

Check imported package metadata:

```bat
EMPlus.bat packages --package-number=689902
```

Generate package environment status:

```bat
EMPlus.bat generate-package-status-report --package-number=689902 --package-version=2 --platform=RHEL_X86_64 --output-format=csv
```

Interpretation: if the status report shows the package with an Environment Name and status such as `NOT_PERMANENTLY_INSTALLED`, EMPlus treats the package as present in that environment, so use `reinstall,<package>` instead of `install,<package>`.