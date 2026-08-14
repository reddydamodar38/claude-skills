---
name: stale-stats
description: Use when collecting or publishing Millennium stale stats through QUEUE_STALE, PREVIEW_STALE, dm2_dbstats_runner, or dm2_publish_dbstats across application nodes in a TACO lab domain.
---

# Stale Stats

Use TACO to inspect, gather, validate, and publish stale database statistics for a specified Millennium lab domain. Read [references/operations.md](references/operations.md) before executing any action.

## Inputs

- Require `domain` unless it is unambiguous in the request.
- Accept `mode`: `full` (default), `preview-only`, `resume-runners`, `publish-only`, `restorepoint-only`, or `replace-restorepoint-only`.
- Default restore point name to `ABL_RESTORE_POINT`; accept `stale_stats_restore_point_name` only when it matches a safe Oracle identifier.
- Require `stale_stats_confirm_replace=true` with the explicit `replace-restorepoint` action. Never replace a restore point implicitly as part of `full`.
- Select the first `primaryDB` host (or explicit `stale_stats_db_host` override) as the `db01` target.
- Default to one runner on every host discovered from `primaryApp` plus `additionalApp`.
- Default expected `NOT QUEUED` families to `DM_INFO`, `DM_STAT_TABLE`, `DM_PROCESS_EVENT`, and `DM_PROCESS`.
- For `ablscale3`, also expect `DM_PROCESS_QUEUE`, `HE_JOB`, and `MP_GROUP_REFRESH_STATE`. These additions apply only to that domain and never suppress a `FAILURE` row.
- Accept an explicit application-node override only when inventory groups are incomplete and the user supplies the nodes.

## Mandatory Execution Rules

1. Invoke and follow `$node-orchestration-runner`. Work from the configured Linux runner and use the existing TACO checkout.
2. Use `lab_inventory/<domain>/` with `lab_inventory/lab_groups.yml`. Do not connect directly to application or database nodes.
3. Verify runner identity, Docker, inventory groups, node reachability, and the vault-password file. Never print the vault file or credentials. Do not run `git remote -v`.
4. Create the restore point on the selected `db01`/primary database host before stale-stat changes. Run shared database operations only on the first `primaryApp` host. Run collectors on all discovered application hosts.
5. Preserve unrelated CCL sessions. Match only `codex_dbstats_*` scripts, logs, markers, and processes owned by this skill.
6. Treat a CCL return code of `1` as success only when its log contains both `Command executed!` and `SESSION COMPLETE` and contains no fatal indicator.
7. Keep detached logs and `.done` markers under `$cer_temp`. Do not start a duplicate when the same skill-owned operation is still active.

## Workflow

Run `playbooks/stale-stats.yml` with `stale_stats_domain=<domain>` and each action below. Use the exact command template in the operations reference.

### 1. Create or explicitly replace the restore point

Before `full`, run `restorepoint` on the selected primary database node. It creates the requested safe name, verifies database identity and the row, and stops when that name already exists.

Use `replace-restorepoint` only after explicit user approval. Require `stale_stats_confirm_replace=true`; report the old row, drop only the validated name when present, create it with `GUARANTEE FLASHBACK DATABASE`, and require the new row to report `GUARANTEE=YES`. This action is database-only and never runs CCL or application-node tasks. In either restore-point-only mode, report verification and stop.

### 2. Preflight

Run `preflight` and require success on every application node. Confirm the resolved login environment equals the requested domain and that `$cer_exe/cclora` and `$cer_temp` are valid.

### 3. Baseline Preview

Run `preview` once on the primary node. Poll with `status` until its marker is complete. Copy or stream the preview log to the runner, resolve the domain policy, and execute `scripts/summarize-status.sh` as shown in the operations reference. In `preview-only` mode, report the parser output and stop here.

### 4. Queue Once

In `full` mode, run `queue` once only after baseline preview succeeds. Wait for its completion marker and validate its CCL success markers before starting collectors.

### 5. Run Collectors

Run `runners` on every application node. Poll `status` without imposing a short local timeout. Continue monitoring `V500.FILL_PRINT_ORD_HX`; do not restart it solely because elapsed time is high.

For `resume-runners`, start here after confirming no runner is active and queued work exists.

### 6. Validate and Recover

After all runner markers complete, run a new `preview`, then parse its log:

- Exit `0`: status is structurally valid.
- Exit `2`: one or more rows are `FAILURE`; run another collectors pass, wait, and preview again.
- Exit `3`: a `NOT QUEUED` family is outside the effective domain policy; stop before publish and report it.

Repeat a runner pass only while progress occurs. Do not publish while a runner is active, a failure remains, or an unexpected exception exists.

### 7. Publish

Run `publish` once on the primary node only after the validation gate passes. In `publish-only` mode, first create a fresh preview and prove the same gate.

### 8. Final Audit

Run a final `preview`, parse it with the same policy, and run `audit`. Require no failures, no unexpected exceptions, no active skill jobs, valid success markers, zero fatal log matches, and reachable application nodes.

Report the domain, selected hosts, effective policy, restore-point evidence, timestamps, marker paths, parser counts, recovery attempts, publish decision, and final audit result.
