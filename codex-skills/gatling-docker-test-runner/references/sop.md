# INJABLFEDA001 Gatling Docker Test Execution SOP

## Purpose

Use this SOP to execute a prepared ABLFEDA Gatling test folder on `INJABLFEDA001`, capture the actual workload window from the node/test output, and append the result to a CSV register on the operator's MacBook.

## Audience

Operators who have an approved, execution-ready Gatling test folder and authorized SSH access to the test node.

## Scope

This SOP covers:

- read-only verification of the prepared test files;
- verification that `scenario-data.yaml` supports ten users;
- Docker DNS-container preparation;
- foreground Gatling execution using the approved Docker command pattern;
- workload timestamp and result capture; and
- local CSV registration.

This SOP does not cover:

- SSH key creation or registration;
- editing `config.yaml`, `scenario.yaml`, or `scenario-data.yaml`;
- conversion, auto-annotation, or automatic transaction fixing;
- AWR, ASH, or `txn-analyzer` collection; or
- database access.

## Fixed environment

| Item | Value |
| --- | --- |
| Node name | `INJABLFEDA001` |
| Node IP | `10.44.121.15` |
| SSH user | `opc` |
| Test root | `/ablpub/OCI/Torq/Gatling` |
| DNS container | `gatling_dns_mappcernabl010` |
| Docker network | `gatling_dns_mappcernabl010` |
| Required DNS IP | `172.25.0.2` |
| Container suffix | `mappcernabl010` |
| Docker image | `iad.ocir.io/idxlj5etbfyf/gatling_docker:gatling_oci_test` |
| Local CSV | `/Users/ayushsaxena/Documents/gatling-test-execution-register.csv` |

## Expected test configuration

The supplied test folder must already contain these effective values:

```yaml
startUsers: 1
endUsers: 10
durationSeconds: 600
rampDurationSeconds: 0
```

Both `config.yaml` and `scenario-data.yaml` must contain:

```yaml
authority: ablfeda
```

No file is edited by this SOP. A mismatch is a stop condition.

## Required input

Provide the absolute test-folder path for each run:

```text
<TEST_FOLDER>
```

## Procedure

### 1. Connect to the node

From the MacBook:

```bash
ssh opc@10.44.121.15
```

SSH readiness and key registration are handled separately from this SOP.

### 2. Confirm the execution node

On the node:

```bash
whoami
hostname
date '+%Y-%m-%dT%H:%M:%S%z %Z'
```

Expected identity:

```text
opc
INJABLFEDA001
```

Stop if the connected user or node is different.

### 3. Set the run variables

Replace only `<TEST_FOLDER>`. It must be an absolute child of `/ablpub/OCI/Torq/Gatling`:

```bash
TEST_FOLDER="<TEST_FOLDER>"
TEST_NAME=$(basename "$TEST_FOLDER")
RUN_ID=$(date '+%Y%m%d-%H%M%S')

NODE_NAME="INJABLFEDA001"
NODE_IP="10.44.121.15"
NODE_SUFFIX="mappcernabl010"

DNS_CONTAINER="gatling_dns_mappcernabl010"
DOCKER_NETWORK="gatling_dns_mappcernabl010"
EXPECTED_DNS_IP="172.25.0.2"
DOCKER_IMAGE="iad.ocir.io/idxlj5etbfyf/gatling_docker:gatling_oci_test"

SAFE_TEST_NAME=$(printf '%s' "$TEST_NAME" | tr -c 'A-Za-z0-9_.-' '-')
RUN_CONTAINER="${SAFE_TEST_NAME}_${NODE_SUFFIX}"

REPORT_PATH="$TEST_FOLDER/Report"
LOG_PATH="$TEST_FOLDER/${SAFE_TEST_NAME}-${RUN_ID}.out"
```

### 4. Verify the prepared files without editing them

```bash
cd "$TEST_FOLDER" || exit 1

for FILE in config.yaml scenario.yaml scenario-data.yaml
do
  test -r "$FILE" || {
    echo "STOP: missing or unreadable file: $FILE"
    exit 1
  }
done
```

Display the configured load values:

```bash
grep -nE \
  '^(startUsers|endUsers|durationSeconds|rampDurationSeconds):' \
  scenario.yaml
```

Require:

```text
startUsers: 1
endUsers: 10
durationSeconds: 600
rampDurationSeconds: 0
```

Display the authorities:

```bash
grep -n 'authority:' config.yaml scenario-data.yaml
```

Require `authority: ablfeda` in `config.yaml` and every global dataset in `scenario-data.yaml`.

### 5. Complete the ten-user data gate

Before execution, Codex must parse `scenario-data.yaml` from the supplied test folder and confirm:

- the YAML is structurally valid;
- the configured dataset can supply ten virtual users;
- all ten required user records are complete, or the schema explicitly supports approved reuse;
- usernames, user IDs, authority, and other required fields are populated; and
- no required value contains an unresolved placeholder such as `Change_Me`.

Do not execute until Codex reports:

```text
TEN_USER_DATA_GATE=PASS
```

### 6. Verify Docker and the approved image

```bash
sudo -n docker info >/dev/null || {
  echo "STOP: Docker is unavailable to opc"
  exit 1
}

sudo -n docker image inspect "$DOCKER_IMAGE" >/dev/null || {
  echo "STOP: approved Gatling image is unavailable"
  exit 1
}

sudo -n docker inspect "$DNS_CONTAINER" >/dev/null || {
  echo "STOP: DNS container is unavailable: $DNS_CONTAINER"
  exit 1
}

sudo -n docker network inspect "$DOCKER_NETWORK" >/dev/null || {
  echo "STOP: Docker network is unavailable: $DOCKER_NETWORK"
  exit 1
}
```

### 7. Start and inspect the DNS container

```bash
DNS_RUNNING=$(sudo -n docker inspect --format '{{.State.Running}}' "$DNS_CONTAINER")

if [ "$DNS_RUNNING" != "true" ]; then
  sudo -n docker start "$DNS_CONTAINER" || exit 1
fi
```

Resolve the DNS-container address specifically from the approved Docker network:

```bash
DNS_IP=$(sudo -n docker inspect \
  --format "{{with index .NetworkSettings.Networks \"$DOCKER_NETWORK\"}}{{.IPAddress}}{{end}}" \
  "$DNS_CONTAINER")

test "$DNS_IP" = "$EXPECTED_DNS_IP" || {
  echo "STOP: DNS address mismatch: expected=$EXPECTED_DNS_IP actual=${DNS_IP:-not-assigned}"
  exit 1
}

echo "DNS container: $DNS_CONTAINER"
echo "Docker network: $DOCKER_NETWORK"
echo "DNS IP: $DNS_IP"
```

### 8. Prepare the generated-output location

```bash
mkdir -p "$REPORT_PATH"
```

The Gatling log uses a timestamped filename so a retry does not overwrite an earlier log.

Because Docker uses `--rm`, the expected execution-container name is normally available. Stop rather than deleting an unexpected existing container:

```bash
if sudo -n docker ps -a --format '{{.Names}}' | grep -Fx "$RUN_CONTAINER" >/dev/null
then
  echo "STOP: container name is already in use: $RUN_CONTAINER"
  exit 1
fi
```

### 9. Capture node time immediately before execution

```bash
NODE_TIMEZONE=$(date '+%z %Z')
COMMAND_START_TIME=$(date '+%Y-%m-%dT%H:%M:%S%z')

echo "Test name: $TEST_NAME"
echo "Test folder: $TEST_FOLDER"
echo "Node timezone: $NODE_TIMEZONE"
echo "Command start: $COMMAND_START_TIME"
echo "Container: $RUN_CONTAINER"
echo "Log: $LOG_PATH"
echo "Report: $REPORT_PATH"
echo "Monitor container: sudo -n docker ps --filter name=$RUN_CONTAINER"
echo "Monitor log: tail -f '$LOG_PATH'"
```

### 10. Execute the test in the foreground

Run the approved Docker command pattern with values derived from the supplied test folder and fixed node configuration:

```bash
sudo -n docker run \
  --rm \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  --network "$DOCKER_NETWORK" \
  --dns "$DNS_IP" \
  --name "$RUN_CONTAINER" \
  -e MAVEN_GOAL='gatling-crank:crank' \
  -e MAVEN_OFFLINE='true' \
  -e GATLING_MAX_HEAP='4g' \
  -v "$TEST_FOLDER:/gatling/dataDirectory" \
  -v "$REPORT_PATH:/gatling/results" \
  "$DOCKER_IMAGE" \
  > "$LOG_PATH" 2>&1

TEST_EXIT_CODE=$?
```

Do not disconnect while the foreground process is active. To observe progress, use the fully resolved monitoring commands printed before execution in a second SSH session.

### 11. Capture completion evidence

Immediately after Docker exits:

```bash
COMMAND_END_TIME=$(date '+%Y-%m-%dT%H:%M:%S%z')

echo "Command end: $COMMAND_END_TIME"
echo "Exit code: $TEST_EXIT_CODE"
tail -n 200 "$LOG_PATH"
```

From the Gatling completion output, capture:

```text
PRINTED_WORKLOAD_END_TIME
PRINTED_DURATION_SECONDS
```

Use the node's timezone for the execution register. If Gatling prints its end time in another timezone, convert it to the node timezone and preserve the original printed value in the notes.

Set the workload end to Gatling's printed end time. Calculate the workload start by subtracting the printed duration:

```text
WORKLOAD_END_TIME = printed Gatling end time converted to node timezone
WORKLOAD_START_TIME = WORKLOAD_END_TIME - PRINTED_DURATION_SECONDS
```

If Gatling does not print an end time, use `COMMAND_END_TIME` as the fallback and record that the fallback was used.

### 12. Assign the final status

The expected result is `PASS`. Record `PASS` only when all of the following are true:

- `TEST_EXIT_CODE` is `0`;
- the Gatling completion marker is present in the log; and
- a report was created under `REPORT_PATH`.

Otherwise record the observed result instead of forcing `PASS`:

| Status | Meaning |
| --- | --- |
| `PASS` | Docker and Gatling completed and the report exists. |
| `COMPLETED_WITH_FAILURES` | Gatling completed but reported transaction failures. |
| `EXECUTION_FAILED` | Docker returned nonzero or no usable report was created. |
| `INTERRUPTED` | The run was interrupted before normal completion. |

### 13. Display the remote execution record

Populate these values from the completion output:

```bash
WORKLOAD_START_TIME="<WORKLOAD_START_IN_NODE_TIMEZONE>"
WORKLOAD_END_TIME="<WORKLOAD_END_IN_NODE_TIMEZONE>"
ACTUAL_DURATION_SECONDS="<PRINTED_DURATION_SECONDS>"
FINAL_STATUS="<FINAL_STATUS>"
```

Print the values that must be registered locally:

```bash
echo "TEST_NAME=$TEST_NAME"
echo "TEST_FOLDER=$TEST_FOLDER"
echo "TEST_NODE=$NODE_NAME"
echo "TEST_HOST=$NODE_IP"
echo "NODE_TIMEZONE=$NODE_TIMEZONE"
echo "COMMAND_START_TIME=$COMMAND_START_TIME"
echo "COMMAND_END_TIME=$COMMAND_END_TIME"
echo "WORKLOAD_START_TIME=$WORKLOAD_START_TIME"
echo "WORKLOAD_END_TIME=$WORKLOAD_END_TIME"
echo "ACTUAL_DURATION_SECONDS=$ACTUAL_DURATION_SECONDS"
echo "TEST_EXIT_CODE=$TEST_EXIT_CODE"
echo "FINAL_STATUS=$FINAL_STATUS"
echo "LOG_PATH=$LOG_PATH"
echo "REPORT_PATH=$REPORT_PATH"
```

### 14. Append the result to the local CSV

Return to the MacBook. Set these values from the remote execution record:

```bash
TEST_NAME="<TEST_NAME>"
TEST_FOLDER="<REMOTE_TEST_FOLDER>"
NODE_TIMEZONE="<NODE_TIMEZONE>"
COMMAND_START_TIME="<COMMAND_START_TIME>"
COMMAND_END_TIME="<COMMAND_END_TIME>"
WORKLOAD_START_TIME="<WORKLOAD_START_TIME>"
WORKLOAD_END_TIME="<WORKLOAD_END_TIME>"
ACTUAL_DURATION_SECONDS="<ACTUAL_DURATION_SECONDS>"
TEST_EXIT_CODE="<TEST_EXIT_CODE>"
FINAL_STATUS="<FINAL_STATUS>"
LOG_PATH="<REMOTE_LOG_PATH>"
REPORT_PATH="<REMOTE_REPORT_PATH>"

LOCAL_CSV="/Users/ayushsaxena/Documents/gatling-test-execution-register.csv"
```

Create the header only when the CSV does not already exist:

```bash
if [ ! -f "$LOCAL_CSV" ]; then
  printf '%s\n' \
    'test_name,test_folder,test_node,test_host,ssh_user,node_timezone,command_start_time,command_end_time,workload_start_time,workload_end_time,test_duration_seconds,start_users,end_users,ramp_duration_seconds,exit_code,final_status,log_path,report_path' \
    > "$LOCAL_CSV"
fi
```

Append the run:

```bash
printf '"%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s"\n' \
  "$TEST_NAME" \
  "$TEST_FOLDER" \
  "INJABLFEDA001" \
  "10.44.121.15" \
  "opc" \
  "$NODE_TIMEZONE" \
  "$COMMAND_START_TIME" \
  "$COMMAND_END_TIME" \
  "$WORKLOAD_START_TIME" \
  "$WORKLOAD_END_TIME" \
  "$ACTUAL_DURATION_SECONDS" \
  "1" \
  "10" \
  "0" \
  "$TEST_EXIT_CODE" \
  "$FINAL_STATUS" \
  "$LOG_PATH" \
  "$REPORT_PATH" \
  >> "$LOCAL_CSV"
```

Confirm the saved row:

```bash
tail -n 1 "$LOCAL_CSV"
```

The CSV can be opened directly in Excel.

## Completion checklist

- [ ] Connected as `opc` to `INJABLFEDA001`.
- [ ] Supplied the absolute test-folder path.
- [ ] Verified all three YAML files without editing them.
- [ ] Verified `1` start user, `10` end users, `600` seconds duration, and `0` seconds ramp.
- [ ] Verified `authority: ablfeda` in both required files.
- [ ] Received `TEN_USER_DATA_GATE=PASS` from Codex.
- [ ] Started and inspected `gatling_dns_mappcernabl010`.
- [ ] Confirmed DNS IP `172.25.0.2` on the `gatling_dns_mappcernabl010` network.
- [ ] Captured command start time from the node.
- [ ] Ran Docker in the foreground using the approved pattern.
- [ ] Captured Gatling workload end time and duration.
- [ ] Calculated workload start time in the node timezone.
- [ ] Captured exit code, log path, report path, and final status.
- [ ] Appended the result to the local CSV.

## Stop conditions

Stop without executing the test when any of the following occurs:

- the connected user or node is incorrect;
- a required YAML file is missing or unreadable;
- a required load or authority value is incorrect;
- the ten-user data gate does not pass;
- Docker, the approved image, DNS container, or Docker network is unavailable;
- the DNS container IP is not `172.25.0.2` on the approved network; or
- the generated execution-container name is already in use.
