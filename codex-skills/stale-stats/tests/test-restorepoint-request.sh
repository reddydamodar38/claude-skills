#!/usr/bin/env bash
set -u

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <taco-repo> <skill-dir>" >&2
  exit 64
fi

taco_repo=$1
skill_dir=$2
cases=(
  restorepoint-create.json
  restorepoint-replace-confirmed.json
  restorepoint-replace-unconfirmed.json
  restorepoint-unsafe-name.json
)
expected=(success success failure failure)
failures=0

for i in "${!cases[@]}"; do
  case_file=${cases[$i]}
  output=$(cd "$taco_repo" && docker compose run --rm \
    -v "$skill_dir:/skill:ro" taco \
    ansible-playbook /skill/tests/test-restorepoint-request.yml \
    -e "@/skill/tests/cases/$case_file" 2>&1)
  rc=$?

  if [[ ${expected[$i]} == success && $rc -ne 0 ]]; then
    echo "FAIL $case_file expected success, rc=$rc" >&2
    echo "$output" >&2
    failures=$((failures + 1))
  elif [[ ${expected[$i]} == failure && $rc -eq 0 ]]; then
    echo "FAIL $case_file expected rejection" >&2
    echo "$output" >&2
    failures=$((failures + 1))
  else
    echo "PASS $case_file ${expected[$i]}"
  fi
done

if [[ $failures -ne 0 ]]; then
  exit 1
fi

echo "${#cases[@]} restore-point request tests passed"
