---
name: gatling-docker-test-runner
description: Use when validating or executing an already-prepared ABLFEDA Gatling test folder on INJABLFEDA001, checking ten-user readiness, retrying the approved Docker workflow, capturing workload timing and artifacts, or registering a result. Do not use for SSH setup, YAML modification, conversion, auto-fixing, database work, AWR/ASH collection, or transaction analysis.
---

# Gatling Docker Test Runner

Run prepared tests through the deterministic script. Do not re-create the Docker command manually.

## Required input

- Absolute test-folder path beneath `/ablpub/OCI/Torq/Gatling` on `INJABLFEDA001`.
- Confirmation whether fewer than ten `globalDataSets` entries are intentionally shared across ten virtual users.
- Authorized SSH access already configured outside this skill.

## Fixed execution contract

- Target: `opc@10.44.121.15` (`INJABLFEDA001`).
- Default key: `~/.ssh/id_ed25519_injablfeda001` with pinned known-hosts verification.
- Docker access: passwordless `sudo -n docker`.
- Docker DNS container/network: `gatling_dns_mappcernabl010`.
- Required DNS IP on that network: `172.25.0.2`.
- Execution-container suffix: `mappcernabl010`.
- Image: `iad.ocir.io/idxlj5etbfyf/gatling_docker:gatling_oci_test`.
- Expected load: start `1`, end `10`, duration `600`, ramp `0` seconds (`rampDurationSeconds: 0`).
- Required authority: `ablfeda` in `config.yaml` and every `scenario-data.yaml` global dataset.
- Local register: `/Users/ayushsaxena/Documents/gatling-test-execution-register.csv`.
- Source YAML files are read and verified, never edited.
- Execution is foreground. Do not detach or background the skill.

## Workflow

1. Obtain an absolute remote test-folder path beneath `/ablpub/OCI/Torq/Gatling`.
2. Decide the data mode:
   - require at least ten `globalDataSets` entries by default;
   - add `--allow-shared-data` only after the user confirms the prepared dataset is intentionally reused across ten virtual users.
3. Run prepare-only first:

```bash
./gatling-docker-test-runner/scripts/run_gatling_docker_test.sh \
  --test-folder '<REMOTE_TEST_FOLDER>' \
  --prepare-only
```

4. Stop if prepare-only does not report both:

```text
TEN_USER_DATA_GATE=PASS
REMOTE_DOCKER_GATE=PASS
PREPARE_ONLY_OK
```

5. When the user asks to execute, run:

```bash
./gatling-docker-test-runner/scripts/run_gatling_docker_test.sh \
  --test-folder '<REMOTE_TEST_FOLDER>' \
  --execute
```

6. For approved shared data, add `--allow-shared-data` to both commands.
7. Monitor the foreground output until the script reports the final status and local CSV path.
8. Report the workload start/end, duration, exit code, status, remote log/report paths, and local CSV.

## Safety rules

- Treat SSH registration and host-key enrollment as prerequisites; do not weaken SSH checking.
- Never add `StrictHostKeyChecking=no`, password authentication, or trust-on-first-use automation.
- Never edit or upload `config.yaml`, `scenario.yaml`, or `scenario-data.yaml`.
- Never print application passwords or private keys.
- Stop if `sudo -n docker` is unavailable or the DNS IP is not `172.25.0.2`.
- Do not delete an unexpected Docker container. Stop on a container-name collision.
- Do not force `PASS`; record the status derived from completion evidence.
- Do not run database, AWR, ASH, or `txn-analyzer` commands.

## Overrides

Use script flags only when the user supplies an approved alternative:

```text
--key-path
--known-hosts-path
--local-csv
--dns-container
--docker-network
--docker-image
--expected-hostname
```

Do not override the fixed host, user, or load settings casually. Read [`references/sop.md`](references/sop.md) when the user asks for the manual SOP or a field-by-field explanation.

## Outputs

- Secret-free prepare-only result.
- Timestamped remote Gatling `.out` log.
- Remote Gatling `Report` output.
- Workload start/end normalized to the node timezone.
- Local CSV row containing the test identity, timing, load, exit code, status, and artifact paths.
