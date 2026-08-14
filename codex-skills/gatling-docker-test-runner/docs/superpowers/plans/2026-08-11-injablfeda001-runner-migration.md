# INJABLFEDA001 Gatling Runner Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fixed EPINJCERNABL000/ABLFHIR runner with the approved INJABLFEDA001/ABLFEDA execution contract.

**Architecture:** Keep the existing single-entry runner and validator. Retarget their fixed defaults and validation rules, add FEDA path/DNS/sudo gates, then synchronize documentation and metadata. Use the fake-SSH harness so implementation tests never start Gatling.

**Tech Stack:** Bash, Ruby/Psych YAML, OpenSSH, Docker CLI, Markdown, YAML metadata.

## Global Constraints

- Target `opc@10.44.121.15`; expect hostname `INJABLFEDA001` case-insensitively.
- Accept only absolute test folders below `/ablpub/OCI/Torq/Gatling`.
- Require users `1` to `10`, duration `600`, ramp `0`, and authority `ablfeda` in both YAML locations.
- Use DNS container/network `gatling_dns_mappcernabl010`, require dynamically resolved IP `172.25.0.2`, and suffix execution containers with `mappcernabl010`.
- Invoke remote Docker as `sudo -n docker` and stop when passwordless sudo fails.
- Preserve the approved image, ten-user gate, pinned SSH verification, read-only source YAML, foreground monitoring, KO-based status, and CSV registration.
- Do not start a live Gatling workload while implementing or testing.
- The installed skill is not a Git repository. Do not initialize one; record verification checkpoints instead of commits.

---

### Task 1: Retarget YAML validation test-first

**Files:**
- Modify: `tests/test_skill.sh`
- Modify: `scripts/validate_test_folder.rb`

**Interfaces:**
- Consumes: readable `config.yaml`, `scenario.yaml`, and `scenario-data.yaml`.
- Produces: `TEN_USER_DATA_GATE=PASS mode=<mode> ...` or nonzero `TEN_USER_DATA_GATE=FAIL reason=<reason>`.

- [ ] **Step 1: Change valid fixtures**

Make valid `scenario.yaml` fixtures contain:

```yaml
startUsers: 1
endUsers: 10
durationSeconds: 600
rampDurationSeconds: 0
```

Make valid config and dataset authority values `ablfeda`.

- [ ] **Step 2: Add regression fixtures**

Add a nonzero-ramp fixture with `rampDurationSeconds: 600` and require failure. Change the wrong-authority fixture to obsolete `ablfhir` and require failure. Preserve dedicated/shared-data, placeholder, identity, and duplicate validation coverage.

- [ ] **Step 3: Verify RED**

```bash
bash tests/test_skill.sh
```

Expected: FAIL because the validator still expects ramp `600` and authority `ablfhir`.

- [ ] **Step 4: Change the validator minimally**

Use:

```ruby
expected_scenario = {
  "startUsers" => 1,
  "endUsers" => 10,
  "durationSeconds" => 600,
  "rampDurationSeconds" => 0
}
```

Change config and dataset authority comparisons and failure messages to `ablfeda`.

- [ ] **Step 5: Verify GREEN for validator behavior**

```bash
ruby -c scripts/validate_test_folder.rb
bash tests/test_skill.sh
```

Expected: Ruby syntax PASS; validator cases pass. A later failure on old runner defaults is acceptable RED for Task 2.

- [ ] **Step 6: Record the changed files and test evidence**

Do not run `git commit`; the installed directory has no `.git` repository.

---

### Task 2: Retarget runner and Docker gates test-first

**Files:**
- Modify: `tests/test_skill.sh`
- Modify: `scripts/run_gatling_docker_test.sh`

**Interfaces:**
- Consumes: `--test-folder /ablpub/OCI/Torq/Gatling/<scenario>` and exactly one execution mode.
- Produces: prepare markers or the existing `GTR_RESULT_*`, status, timing, artifact, and CSV outputs.

- [ ] **Step 1: Add new fixed-contract assertions**

Require these script signatures:

```text
10.44.121.15
INJABLFEDA001
id_ed25519_injablfeda001
/ablpub/OCI/Torq/Gatling
gatling_dns_mappcernabl010
172.25.0.2
mappcernabl010
sudo -n docker
```

Reject `10.44.120.18`, `EPINJCERNABL000`, `ablfhir`, and `gatling_dns_epinjcernabl000` in active files. Make fake SSH return `USER=opc` and `HOST=injablfeda001`.

- [ ] **Step 2: Add path and remote-command tests**

Require `/home/gatling/prepared-test` to fail before SSH with `--test-folder must be beneath /ablpub/OCI/Torq/Gatling.` Use `/ablpub/OCI/Torq/Gatling/prepared-test` for success. Capture streamed remote Bash and assert sudo Docker use, fixed DNS/network, IP enforcement, and `mappcernabl010` suffix.

- [ ] **Step 3: Verify RED**

```bash
bash tests/test_skill.sh
```

Expected: FAIL on at least one old target, hostname, path, DNS, key, or sudo assertion.

- [ ] **Step 4: Replace runner defaults**

Set:

```bash
key_path="$HOME/.ssh/id_ed25519_injablfeda001"
expected_hostname="INJABLFEDA001"
target_host="10.44.121.15"
target_user="opc"
test_root="/ablpub/OCI/Torq/Gatling"
dns_container="gatling_dns_mappcernabl010"
docker_network="gatling_dns_mappcernabl010"
expected_dns_ip="172.25.0.2"
container_suffix="mappcernabl010"
```

After absolute-path validation, enforce:

```bash
case "$test_folder" in
  "$test_root"/*) ;;
  *) echo "--test-folder must be beneath $test_root." >&2; exit 64 ;;
esac
```

- [ ] **Step 5: Apply sudo and DNS safety consistently**

Pass `expected_dns_ip` and `container_suffix` into remote prepare/execute scripts. Define `docker_cmd=(sudo -n docker)` in both and replace every remote Docker operation with `"${docker_cmd[@]}"`. Reject a DNS IP other than `172.25.0.2`:

```bash
if [ "$dns_ip" != "$expected_dns_ip" ]; then
  echo "DNS address mismatch: expected=$expected_dns_ip actual=${dns_ip:-not-assigned}" >&2
  exit 1
fi
```

Build `run_container="${safe_test_name}_${container_suffix}"`. Keep filesystem operations unprivileged.

- [ ] **Step 6: Preserve execution-result logic**

Keep timestamped output, report marker, completion/duration parsing, KO count, final-status derivation, CSV quoting, and non-PASS exit behavior unchanged except for the new node identity.

- [ ] **Step 7: Verify GREEN**

```bash
bash -n scripts/run_gatling_docker_test.sh
bash tests/test_skill.sh
```

Expected: PASS with `GATLING_DOCKER_TEST_RUNNER_TESTS=PASS`.

- [ ] **Step 8: Record the changed files and evidence**

Do not initialize Git in the installed skill directory.

---

### Task 3: Synchronize instructions, SOP, and metadata test-first

**Files:**
- Modify: `SKILL.md`
- Modify: `references/sop.md`
- Modify: `agents/openai.yaml`
- Modify: `tests/test_skill.sh`

**Interfaces:**
- Consumes: the fixed contract implemented by Tasks 1–2.
- Produces: discoverable instructions and an operator SOP matching executable defaults.

- [ ] **Step 1: Add documentation assertions**

Require active docs/metadata to contain the new hostname/IP, authority, ramp, root, DNS/network, DNS IP, suffix, and sudo usage. Assert obsolete EPINJ/ABLFHIR defaults are absent from active files.

- [ ] **Step 2: Verify RED**

```bash
bash tests/test_skill.sh
```

Expected: FAIL because docs and metadata still describe EPINJCERNABL000.

- [ ] **Step 3: Update `SKILL.md`**

Retarget the description, input, fixed contract, examples, outputs, overrides, and safety rules to INJABLFEDA001/ABLFEDA. State the permitted root, ramp `0`, `sudo -n docker`, and the `mappcernabl010` DNS profile/IP.

- [ ] **Step 4: Update `references/sop.md`**

Replace the fixed-environment table, SSH examples, YAML expectations, run variables, Docker checks, DNS validation, container suffix, Docker command, CSV node fields, checklist, and stop conditions. All Docker examples use `sudo -n docker`; all test paths use `/ablpub/OCI/Torq/Gatling`.

- [ ] **Step 5: Update `agents/openai.yaml`**

```yaml
interface:
  display_name: "Gatling Docker Test Runner"
  short_description: "Run prepared Gatling tests on INJABLFEDA001"
  default_prompt: "Use $gatling-docker-test-runner to validate and run a prepared ABLFEDA Gatling test folder on INJABLFEDA001."
```

- [ ] **Step 6: Verify GREEN and remove stale defaults**

```bash
bash tests/test_skill.sh
grep -RniE 'EPINJCERNABL000|10\.44\.120\.18|gatling_dns_epinjcernabl000|authority: ablfhir|rampDurationSeconds: 600' SKILL.md agents references scripts tests
```

Expected: tests PASS; grep produces no obsolete active defaults.

- [ ] **Step 7: Record the checkpoint**

Do not create a commit in the non-Git installed directory.

---

### Task 4: Verify on the prescribed Linux runner

**Files:**
- Verify: `SKILL.md`, `agents/openai.yaml`, `references/sop.md`
- Verify: `scripts/run_gatling_docker_test.sh`, `scripts/validate_test_folder.rb`, `tests/test_skill.sh`

**Interfaces:**
- Consumes: completed Tasks 1–3.
- Produces: syntax, regression, and static-contract evidence without a live workload.

- [ ] **Step 1: Verify the Linux host**

```bash
ssh codex-runner 'hostname; id -un; pwd'
```

Expected: `dh2vpc067`, `root`, then use `/root/codex-workspace`.

- [ ] **Step 2: Create an isolated verification copy**

Create `/root/codex-workspace/gatling-docker-test-runner-update` and copy only updated skill files. Do not transfer keys, credentials, logs, unrelated skills, or attachments.

- [ ] **Step 3: Run final verification**

```bash
cd /root/codex-workspace/gatling-docker-test-runner-update
bash -n scripts/run_gatling_docker_test.sh
ruby -c scripts/validate_test_folder.rb
bash tests/test_skill.sh
```

Expected:

```text
Syntax OK
GATLING_DOCKER_TEST_RUNNER_TESTS=PASS
```

- [ ] **Step 4: Re-scan installed files and report**

Confirm every active file reflects the FEDA contract. Report changed files, verification output, the absence of a Git commit because there is no repository, and that no live Gatling execution or source-YAML modification occurred.
