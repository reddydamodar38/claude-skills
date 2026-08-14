# TORQ Eggplant Recovery Commands

Use these commands from the existing `/root/node-orchestration` clone on `codex-runner`. Do not edit inventory files or expose the vault password.

## Canonical ablscale3 inventory

```bash
INV="-i lab_inventory/ablscale3/ablscale3.yml \
-i lab_inventory/ablscale3/ablscale3_vault.yml \
-i lab_inventory/ablscale3/ablscale3_vmware.yml \
-i lab_inventory/lab_groups.yml \
--vault-password-file /home/taco/.codex_tmp/vault-pass.txt"
```

Use the resolved arguments directly in automation commands; `INV` is only explanatory shorthand.

## 1. Verify the runner

```powershell
ssh codex-runner "hostname; id -un; pwd"
```

Expect `dh2vpc067`, `root`, and `/root`. If the alias is unavailable, report it. Use the already-approved canonical FQDN `root@dh2vpc067.dh2.cerner.com` with SSH key authentication only when that fallback is established for the session.

## 2. Read Jenkins and TestController state

```powershell
$job = Invoke-RestMethod -Uri '<BUILD_URL>/api/json' -UseDefaultCredentials
$flow = Invoke-RestMethod -Uri '<BUILD_URL>/wfapi/describe' -UseDefaultCredentials
$tc = Invoke-RestMethod -Uri '<TESTCONTROLLER_STATUS_URL>' -UseDefaultCredentials
[pscustomobject]@{
  building = $job.building
  result = $job.result
  flow = $flow.status
  status = $tc.status
  runNumber = $tc.runNumber
  running = $tc.running
  pending = $tc.pending
}
```

For an authenticated abort, open the exact build URL, click `Cancel`, confirm `Yes`, and poll `/api/json` until `building=false`. A terminal `result` with `building=true` is still unwinding.

## 3. Inspect target processes and health

Replace `OCI_30WF_Scale_60min.171[8]` with the evidence-backed token whose last digit is bracketed.

```bash
docker compose run --rm taco ansible eggplant_injector \
  -i lab_inventory/ablscale3/ablscale3.yml \
  -i lab_inventory/ablscale3/ablscale3_vault.yml \
  -i lab_inventory/ablscale3/ablscale3_vmware.yml \
  -i lab_inventory/lab_groups.yml \
  --vault-password-file /home/taco/.codex_tmp/vault-pass.txt \
  -m shell -a 'pgrep -af "OCI_30WF_Scale_60min.171[8]" || true;
  systemctl is-active epinjector || true;
  lsof -nP -iTCP:39000 -sTCP:LISTEN || true;
  lsof -nP -iTCP:5900 -sTCP:LISTEN || true'
```

Also inspect any non-target Functional work before cleanup:

```bash
pgrep -af '[E]ggplant.app/Eggplant' || true
pgrep -af '[E]ggplant.app/runscript' || true
```

## 4. Terminate only the failed run

```bash
before=$(pgrep -fc 'OCI_30WF_Scale_60min.171[8]' || true)
pkill -TERM -f 'OCI_30WF_Scale_60min.171[8]' || true
for i in $(seq 1 10); do
  after=$(pgrep -fc 'OCI_30WF_Scale_60min.171[8]' || true)
  [ "$after" -eq 0 ] && break
  sleep 1
done
[ "$after" -eq 0 ]
```

Run this through the same scoped Ansible inventory. Do not add a `KILL` fallback until the remaining PIDs have been re-inspected and attributed to the exact run.

## 5. Restart the injector service

```bash
docker compose run --rm taco ansible eggplant_injector \
  -i lab_inventory/ablscale3/ablscale3.yml \
  -i lab_inventory/ablscale3/ablscale3_vault.yml \
  -i lab_inventory/ablscale3/ablscale3_vmware.yml \
  -i lab_inventory/lab_groups.yml \
  --vault-password-file /home/taco/.codex_tmp/vault-pass.txt \
  -m systemd -a 'name=epinjector state=restarted enabled=yes'
```

An inactive unit plus one listening `injector.jar` indicates an orphan outside systemd ownership. Only after proving zero Functional work from other runs:

```bash
old=$(lsof -nP -iTCP:39000 -sTCP:LISTEN -t)
ps -o pid,ppid,state,lstart,args -p "$old"
kill -TERM "$old"
for i in $(seq 1 10); do
  lsof -nP -iTCP:39000 -sTCP:LISTEN -t >/dev/null || break
  sleep 1
done
systemctl start epinjector
```

## 6. Final per-host check

```bash
run=$(pgrep -fc 'OCI_30WF_Scale_60min.171[8]' || true)
egg=$(pgrep -fc '[E]ggplant.app/Eggplant' || true)
wrap=$(pgrep -fc '[E]ggplant.app/runscript' || true)
inj=$(pgrep -fc '[i]njector.jar' || true)
p39=$(lsof -nP -iTCP:39000 -sTCP:LISTEN -t | wc -l)
p59=$(lsof -nP -iTCP:5900 -sTCP:LISTEN -t | wc -l)
unit=$(systemctl is-active epinjector 2>/dev/null || true)
echo "run=$run eggplant=$egg runscript=$wrap injector_java=$inj port39000=$p39 port5900=$p59 unit=$unit"
[ "$run" -eq 0 ] &&
[ "$egg" -eq 0 ] &&
[ "$wrap" -eq 0 ] &&
[ "$inj" -eq 1 ] &&
[ "$p39" -eq 1 ] &&
[ "$p59" -ge 1 ] &&
[ "$unit" = active ]
```

Run Jenkins/TestController status checks again after all hosts return success.
