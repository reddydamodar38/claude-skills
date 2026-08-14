---
name: recover-torq-eggplant
description: Use when a TORQ/Jenkins Eggplant Performance build hangs during engine initialization, TestController reports Initialization failed or maximum injector failures, pending users never drain, or a failed run leaves Eggplant, runscript, injector.jar, or port 39000 state on Linux injectors.
---

# Recover TORQ Eggplant

## Overview

Recover one failed Eggplant run without disturbing VNC, newer runs, or unrelated TORQ work. Treat Jenkins, TestController, run processes, and injector listeners as separate state boundaries.

**REQUIRED BACKGROUND:** Use `superpowers:systematic-debugging`, `desktop`, `torq-toolbelt`, and `node-orchestration-runner`. Use `browser:control-in-app-browser` when Jenkins requires an authenticated UI abort.

Read [references/commands.md](references/commands.md) before running commands.

## Safety Gates

Before cleanup, prove all of these:

1. TestController is terminal (`Initialization failed`, equivalent error, or aborted).
2. TestController reports `running=0`.
3. The exact Jenkins build is aborted and reports `building=false`.
4. The evidence-derived run token appears in target process command lines.
5. No Functional or `runscript` process with a different run token is active.

If any gate fails, stop before all mutation, including exact-target `TERM`. A live other run blocks cleanup. Wait for it to finish or obtain separate authorization to abort it. Never alter TestController counters/records, use `killall`, kill all Java, or restart hosts.

When TestController is nonterminal or `running>0`, do not abort Jenkins unless the user separately and explicitly authorizes aborting that active run.

## Recovery Workflow

1. Obtain the exact build URL, TestController status URL, environment, injector group, run number, and evidence-derived token. Capture Jenkins/workflow state, TestController state, controller startup log, and per-host process/listener state.
2. Abort only the affected Jenkins build. Prefer authenticated `Cancel` -> `Yes`; do not reuse unrelated credentials. Wait for `building=false`.
3. Bracket the token's last digit for matching, for example `.1718` -> `.171[8]`. This matches the process but not the inspection command.
4. Send `TERM` only to that exact pattern and wait for zero matches. Use `KILL` only for remaining re-inspected target PIDs.
5. Restart `epinjector` on the scoped injector group. Do not restart VNC.
6. If systemd is inactive but one old `injector.jar` owns 39000, first prove no other run exists. Terminate that listener PID, wait for the port to clear, then start `epinjector`.
7. Verify every host and centralized state again.

## Verification Contract

Require per injector:

- zero target-run, Eggplant Functional, and `runscript` processes;
- exactly one `injector.jar`;
- exactly one TCP listener on 39000;
- at least one VNC listener on 5900;
- `epinjector` active.

Report Jenkins/TestController state, hosts, before/after counts, and unresolved conditions. Retry as a new TORQ build/run; never revive the failed run.

## Common Mistakes

| Mistake | Correct check |
|---|---|
| Trusting `systemctl` alone | Verify PID and `lsof` listener ownership |
| Treating pending users as active | Gate on TestController `running` and terminal status |
| Broad Eggplant/Java cleanup | Match the exact run token and listener PID |
| Cleaning beside a live newer run | Stop all injector mutation |
| Restarting VNC "for completeness" | Preserve 5900 unless separately diagnosed |
