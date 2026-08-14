#!/usr/bin/env bash

set -euo pipefail

skill_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
runner="$skill_dir/scripts/run_gatling_docker_test.sh"
validator="$skill_dir/scripts/validate_test_folder.rb"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/gatling-docker-test-runner-tests.XXXXXX")

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

assert_contains() {
  haystack=$1
  needle=$2
  if ! printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null; then
    echo "Expected output to contain: $needle" >&2
    exit 1
  fi
}

assert_file_contains() {
  file=$1
  needle=$2
  if ! grep -F -- "$needle" "$file" >/dev/null; then
    echo "Expected $file to contain: $needle" >&2
    exit 1
  fi
}

write_base_files() {
  folder=$1
  authority=$2
  ramp_duration=${3:-0}
  mkdir -p "$folder"
  cat > "$folder/config.yaml" <<YAML
authority: $authority
username: system
password: example-test-value
verboseLogging: false
YAML
  cat > "$folder/scenario.yaml" <<YAML
scenarioName: fixture
userTimeUnit: second
startUsers: 1
endUsers: 10
durationSeconds: 600
rampDurationSeconds: $ramp_duration
YAML
}

write_data_file() {
  folder=$1
  count=$2
  placeholder=${3:-false}
  authority=${4:-ablfeda}
  {
    printf 'data: []\n'
    printf 'globalDataSets:\n'
    index=1
    while [ "$index" -le "$count" ]; do
      user_value="USER_$index"
      if [ "$placeholder" = "true" ] && [ "$index" -eq 1 ]; then
        user_value="Change_Me"
      fi
      cat <<YAML
- queryString: null
  params:
  - name: username
    value: "$user_value"
  - name: user_id
    value: "$((53000000 + index))"
  - name: authority
    value: "$authority"
  - name: password
    value: "protected-at-runtime"
  headers: null
YAML
      index=$((index + 1))
    done
    printf 'scenarioDataSets: null\n'
  } > "$folder/scenario-data.yaml"
}

bash -n "$runner"
ruby -c "$validator" >/dev/null
help_output=$("$runner" --help)
assert_contains "$help_output" "--prepare-only"
assert_contains "$help_output" "--execute"
assert_contains "$help_output" "--allow-shared-data"

dedicated="$test_root/dedicated"
write_base_files "$dedicated" "ablfeda"
write_data_file "$dedicated" 10
dedicated_output=$(ruby "$validator" --folder "$dedicated" --required-users 10)
assert_contains "$dedicated_output" "TEN_USER_DATA_GATE=PASS"
assert_contains "$dedicated_output" "mode=dedicated"

shared="$test_root/shared"
write_base_files "$shared" "ablfeda"
write_data_file "$shared" 1
if ruby "$validator" --folder "$shared" --required-users 10 >/dev/null 2>&1; then
  echo "Shared data passed without explicit approval" >&2
  exit 1
fi
shared_output=$(ruby "$validator" --folder "$shared" --required-users 10 --allow-shared-data)
assert_contains "$shared_output" "TEN_USER_DATA_GATE=PASS"
assert_contains "$shared_output" "mode=shared-approved"

placeholder="$test_root/placeholder"
write_base_files "$placeholder" "ablfeda"
write_data_file "$placeholder" 10 true
if ruby "$validator" --folder "$placeholder" --required-users 10 >/dev/null 2>&1; then
  echo "Unresolved placeholder was not rejected" >&2
  exit 1
fi

wrong_authority="$test_root/wrong-authority"
write_base_files "$wrong_authority" "ablfhir"
write_data_file "$wrong_authority" 10
if ruby "$validator" --folder "$wrong_authority" --required-users 10 >/dev/null 2>&1; then
  echo "Wrong config authority was not rejected" >&2
  exit 1
fi

wrong_ramp="$test_root/wrong-ramp"
write_base_files "$wrong_ramp" "ablfeda" 600
write_data_file "$wrong_ramp" 10
if ruby "$validator" --folder "$wrong_ramp" --required-users 10 >/dev/null 2>&1; then
  echo "Nonzero ramp duration was not rejected" >&2
  exit 1
fi

for forbidden in \
  'StrictHostKeyChecking=no' \
  'UserKnownHostsFile=/dev/null' \
  'ssh-copy-id' \
  'GATLING_SSH_PASSWORD' \
  '10.44.120.18' \
  'EPINJCERNABL000' \
  'gatling_dns_epinjcernabl000'
do
  if grep -F "$forbidden" "$runner" "$validator" >/dev/null; then
    echo "Forbidden security signature found: $forbidden" >&2
    exit 1
  fi
done

for required in \
  'StrictHostKeyChecking=yes' \
  'IdentitiesOnly=yes' \
  'TEN_USER_DATA_GATE=PASS' \
  'PREPARE_ONLY_OK' \
  '10.44.121.15' \
  'INJABLFEDA001' \
  'id_ed25519_injablfeda001' \
  '/ablpub/OCI/Torq/Gatling' \
  'gatling_dns_mappcernabl010' \
  '172.25.0.2' \
  'mappcernabl010' \
  'sudo -n docker' \
  'iad.ocir.io/idxlj5etbfyf/gatling_docker:gatling_oci_test'
do
  if ! grep -F "$required" "$runner" "$validator" >/dev/null; then
    echo "Required behavior signature is missing: $required" >&2
    exit 1
  fi
done

fake_bin="$test_root/fake-bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -euo pipefail

last_arg=""
uses_bash=false
for arg in "$@"; do
  last_arg=$arg
  if [ "$arg" = "bash" ]; then
    uses_bash=true
  fi
done

if printf '%s' "$last_arg" | grep -F 'printf "USER=' >/dev/null; then
  printf '%s\n' "$*" >> "$FAKE_SSH_CALLS"
  printf 'USER=opc\nHOST=injablfeda001\n'
  exit 0
fi

case "$last_arg" in
  "cat -- "*)
    printf '%s\n' "$*" >> "$FAKE_SSH_CALLS"
    remote_path=${last_arg#cat -- }
    remote_path=${remote_path//\\ / }
    file_name=$(basename "$remote_path")
    cat "$FAKE_REMOTE_FIXTURE/$file_name"
    exit 0
    ;;
esac

if $uses_bash; then
  printf '%s\n' "$*" >> "$FAKE_SSH_CALLS"
  cat > "$FAKE_REMOTE_SCRIPT"
  printf 'REMOTE_DOCKER_GATE=PASS dns_running=true dns_ip=172.25.0.2\n'
  exit 0
fi

echo "Unexpected fake SSH call" >&2
exit 1
FAKE_SSH
chmod 755 "$fake_bin/ssh"
touch "$test_root/fake-key" "$test_root/fake-known-hosts"
chmod 600 "$test_root/fake-key" "$test_root/fake-known-hosts"
fake_ssh_calls="$test_root/fake-ssh-calls.log"
fake_remote_script="$test_root/fake-remote-script.sh"

invalid_path_output="$test_root/invalid-path.out"
if PATH="$fake_bin:$PATH" FAKE_REMOTE_FIXTURE="$dedicated" \
  FAKE_SSH_CALLS="$fake_ssh_calls" FAKE_REMOTE_SCRIPT="$fake_remote_script" \
  "$runner" \
    --test-folder /home/gatling/prepared-test \
    --prepare-only \
    --key-path "$test_root/fake-key" \
    --known-hosts-path "$test_root/fake-known-hosts" \
    >"$invalid_path_output" 2>&1
then
  echo "Out-of-root test folder was accepted" >&2
  exit 1
fi
assert_contains "$(cat "$invalid_path_output")" "--test-folder must be beneath /ablpub/OCI/Torq/Gatling."

prepare_output=$(
  PATH="$fake_bin:$PATH" FAKE_REMOTE_FIXTURE="$dedicated" \
    FAKE_SSH_CALLS="$fake_ssh_calls" FAKE_REMOTE_SCRIPT="$fake_remote_script" \
    "$runner" \
      --test-folder /ablpub/OCI/Torq/Gatling/prepared-test \
      --prepare-only \
      --key-path "$test_root/fake-key" \
      --known-hosts-path "$test_root/fake-known-hosts"
)
assert_contains "$prepare_output" "TEN_USER_DATA_GATE=PASS"
assert_contains "$prepare_output" "REMOTE_DOCKER_GATE=PASS"
assert_contains "$prepare_output" "PREPARE_ONLY_OK"
assert_contains "$(cat "$fake_ssh_calls")" "opc@10.44.121.15"
assert_contains "$(cat "$fake_ssh_calls")" "/ablpub/OCI/Torq/Gatling/prepared-test gatling_dns_mappcernabl010 gatling_dns_mappcernabl010"
assert_contains "$(cat "$fake_remote_script")" "docker_cmd=(sudo -n docker)"
assert_contains "$(cat "$fake_remote_script")" "expected_dns_ip"

skill_file="$skill_dir/SKILL.md"
sop_file="$skill_dir/references/sop.md"
agent_file="$skill_dir/agents/openai.yaml"

for required in \
  'INJABLFEDA001' \
  '10.44.121.15' \
  '/ablpub/OCI/Torq/Gatling' \
  'ablfeda' \
  'rampDurationSeconds: 0' \
  'gatling_dns_mappcernabl010' \
  '172.25.0.2' \
  'sudo -n docker'
do
  assert_file_contains "$skill_file" "$required"
  assert_file_contains "$sop_file" "$required"
done

assert_file_contains "$agent_file" 'INJABLFEDA001'
assert_file_contains "$agent_file" 'ABLFEDA'

for obsolete in \
  'EPINJCERNABL000' \
  '10.44.120.18' \
  'gatling_dns_epinjcernabl000' \
  'authority: ablfhir' \
  'rampDurationSeconds: 600'
do
  if grep -F "$obsolete" "$skill_file" "$sop_file" "$agent_file" "$runner" "$validator" >/dev/null; then
    echo "Obsolete active contract found: $obsolete" >&2
    exit 1
  fi
done

echo "GATLING_DOCKER_TEST_RUNNER_TESTS=PASS"
