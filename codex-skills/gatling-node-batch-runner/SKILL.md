---
name: gatling-node-batch-runner
description: Use when starting, checking, monitoring, or stopping a node-wide sequential batch of already-prepared ABLFEDA Gatling workflows beneath /ablpub/OCI/Torq/Gatling on INJABLFEDA001, with one common results CSV and a five-minute cooldown. Do not use for a single workflow, YAML editing, conversion, fixing, database work, AWR/ASH, transaction analysis, or SSH setup.
---

# Gatling Node Batch Runner

Operate the prepared node-wide batch only through the bundled controller. It pins the approved host key, uses Pageant authentication, and delegates validation and lifecycle ownership to the bundled remote runner.

## Select the action

- Use `start` only when the user asks to begin the prepared node-wide batch.
- Use `status` for checks, monitoring, progress requests, or any ambiguous request. `status` is the safe default and is read-only.
- Use `stop` only when the user explicitly authorizes stopping the node-wide batch. A request to check, monitor, diagnose, or report is not stop authorization.

Announce the selected action—`start`, `status`, or `stop`—before invoking it.

## Invoke the controller

Run only `scripts/invoke_gatling_node_batch.ps1` with one validated action:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/invoke_gatling_node_batch.ps1 -Action status
```

Replace `status` only with the selected `start` or explicitly authorized `stop`. Do not reconstruct an ad hoc SSH, Plink, Bash, or Docker loop. Do not invoke the remote Bash script directly. Never edit `config.yaml`, `scenario.yaml`, or `scenario-data.yaml` as part of this workflow.

## Report evidence

Report the controller exit code and the emitted `BATCH_STATE` value. Preserve concrete emitted values rather than inferring success.

- For `start`, report `VALIDATED_WORKFLOWS`, `CSV_PATH`, `BACKUP_PATH`, `WORKER_PID`, and `FIRST_WORKFLOW`.
- For active `status`, report `WORKER_PID`, `PROCESS_COMMAND`, `ACTIVE_WORKFLOW`, `ACTIVE_CONTAINER`, `COMPLETED`, `TOTAL`, and the emitted latest result rows. For completed status, report `COMPLETED`, `TOTAL`, and those result rows. Report `NOT_STARTED` or `STALE_STATE` exactly when emitted.
- For `stop`, report `STOPPED`; on refusal or failure, report the exact emitted reason and do not claim that the batch stopped.

If the controller exits nonzero, report the failure output and stop. Do not bypass its preflight, ownership, host-key, Pageant, or Plink checks.
