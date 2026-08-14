#!/usr/bin/env python3
"""Run prepared Gatling workflow folders sequentially with the approved Docker command."""

import argparse
import csv
import os
import re
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple


ROOT = Path("/ablpub/OCI/Torq/Gatling")
CSV_PATH = ROOT / "gatling-workflow-results.csv"
PID_PATH = ROOT / "gatling-workflow-batch.pid"
STATE_PATH = ROOT / "gatling-workflow-batch.state"
IMAGE = "iad.ocir.io/idxlj5etbfyf/gatling_docker:gatling_oci_test"
NETWORK = "gatling_dns_mappcernabl010"
DNS_CONTAINER = "gatling_dns_mappcernabl010"
DNS_IP = "172.25.0.2"
SUFFIX = "mappcernabl010"
COOLDOWN_SECONDS = 300
REQUIRED_FILES = ("config.yaml", "scenario.yaml", "scenario-data.yaml")
CSV_FIELDS = ("workflow_name", "begin_time", "end_time", "ok_count", "ko_count")
WORKFLOW_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
PLACEHOLDER_PATTERN = re.compile(r"Change_Me|REPLACE_ME", re.IGNORECASE)
SUMMARY_PATTERN = re.compile(r">\s*Global.*\(OK=\s*(\d+)\s+KO=\s*(\d+)\s*\)")
STOP_REQUESTED = False


def timestamp() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def run_checked(args):
    # Python 3.6 compatibility: capture_output and text are not available.
    return subprocess.run(
        args,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
    )


def scalar_values(text, key):
    pattern = re.compile(
        rf"^\s*{re.escape(key)}\s*:\s*['\"]?([^'\"#\s]+)['\"]?\s*(?:#.*)?$",
        re.MULTILINE,
    )
    return [match.group(1).strip() for match in pattern.finditer(text)]


def paired_param_values(text, param_name):
    lines = text.splitlines()
    values = []
    name_pattern = re.compile(
        rf"^\s*-?\s*name\s*:\s*['\"]?{re.escape(param_name)}['\"]?\s*$",
        re.IGNORECASE,
    )
    value_pattern = re.compile(r"^\s*value\s*:\s*(.*?)\s*$", re.IGNORECASE)
    next_name_pattern = re.compile(r"^\s*-?\s*name\s*:", re.IGNORECASE)
    for index, line in enumerate(lines):
        if not name_pattern.match(line):
            continue
        for candidate in lines[index + 1 : index + 8]:
            if next_name_pattern.match(candidate):
                break
            match = value_pattern.match(candidate)
            if match:
                values.append(match.group(1).strip().strip("'\""))
                break
    return values


def validate_expected_values(workflow, text, key, expected):
    values = scalar_values(text, key)
    if not values:
        return [f"{workflow}: scenario.yaml missing {key}"]
    actual = [value for value in values if value != expected]
    if actual:
        return [f"{workflow}: scenario.yaml {key} expected {expected}, found {','.join(actual)}"]
    return []


def validate_workflow(folder):
    errors = []
    workflow = folder.name
    if not WORKFLOW_PATTERN.fullmatch(workflow):
        return [f"{workflow}: unsafe workflow name"]

    contents = {}
    for filename in REQUIRED_FILES:
        path = folder / filename
        if not path.is_file() or not os.access(path, os.R_OK):
            errors.append(f"{workflow}: missing or unreadable {filename}")
            continue
        contents[filename] = path.read_text(encoding="utf-8", errors="replace")

    if errors:
        return errors

    for filename, text in contents.items():
        if PLACEHOLDER_PATTERN.search(text):
            errors.append(f"{workflow}: unresolved placeholder in {filename}")

    scenario = contents["scenario.yaml"]
    for key, expected in (
        ("startUsers", "1"),
        ("endUsers", "10"),
        ("durationSeconds", "600"),
        ("rampDurationSeconds", "0"),
    ):
        errors.extend(validate_expected_values(workflow, scenario, key, expected))

    config_authorities = scalar_values(contents["config.yaml"], "authority")
    if not config_authorities or any(value.casefold() != "ablfeda" for value in config_authorities):
        errors.append(
            f"{workflow}: config.yaml authority expected ablfeda, found {config_authorities or ['MISSING']}"
        )

    scenario_data = contents["scenario-data.yaml"]
    direct_authorities = scalar_values(scenario_data, "authority")
    if any(value.casefold() != "ablfeda" for value in direct_authorities):
        errors.append(
            f"{workflow}: scenario-data.yaml direct authority expected ablfeda, found {direct_authorities}"
        )

    return errors


def discover_workflows():
    workflows = []
    for folder in sorted((path for path in ROOT.iterdir() if path.is_dir()), key=lambda p: p.name.casefold()):
        if all((folder / filename).is_file() for filename in REQUIRED_FILES):
            workflows.append(folder)
    return workflows


def read_pid():
    try:
        value = PID_PATH.read_text(encoding="ascii").strip()
        return int(value)
    except (FileNotFoundError, ValueError):
        return None


def pid_is_live(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def preflight():
    if os.uname().nodename.split(".", 1)[0].casefold() != "injablfeda001":
        raise RuntimeError(f"hostname expected INJABLFEDA001, found {os.uname().nodename}")
    if not ROOT.is_dir():
        raise RuntimeError(f"missing root {ROOT}")

    existing_pid = read_pid()
    if existing_pid is not None and pid_is_live(existing_pid):
        raise RuntimeError(f"batch PID already active: {existing_pid}")

    run_checked(["docker", "info"])
    run_checked(["docker", "image", "inspect", IMAGE])
    run_checked(["docker", "network", "inspect", NETWORK])
    dns_running = run_checked(["docker", "inspect", "-f", "{{.State.Running}}", DNS_CONTAINER]).stdout.strip()
    if dns_running != "true":
        raise RuntimeError(f"DNS container is not running: {DNS_CONTAINER}")
    dns_ip = run_checked(
        [
            "docker",
            "inspect",
            "-f",
            f'{{{{with index .NetworkSettings.Networks "{NETWORK}"}}}}{{{{.IPAddress}}}}{{{{end}}}}',
            DNS_CONTAINER,
        ]
    ).stdout.strip()
    if dns_ip != DNS_IP:
        raise RuntimeError(f"DNS IP expected {DNS_IP}, found {dns_ip or 'MISSING'}")

    workflows = discover_workflows()
    if not workflows:
        raise RuntimeError("no prepared workflow folders found")

    errors: list[str] = []
    for folder in workflows:
        errors.extend(validate_workflow(folder))
    if errors:
        raise RuntimeError("workflow validation failed:\n" + "\n".join(errors))

    all_names = set(run_checked(["docker", "ps", "-a", "--format", "{{.Names}}"]).stdout.splitlines())
    active_names = set(run_checked(["docker", "ps", "--format", "{{.Names}}"]).stdout.splitlines())
    unexpected_active = sorted(
        name for name in active_names if name.endswith(f"_{SUFFIX}") and name != DNS_CONTAINER
    )
    if unexpected_active:
        raise RuntimeError(f"active Gatling containers already exist: {','.join(unexpected_active)}")
    collisions = [f"{folder.name}_{SUFFIX}" for folder in workflows if f"{folder.name}_{SUFFIX}" in all_names]
    if collisions:
        raise RuntimeError(f"container name collisions: {','.join(collisions)}")

    return workflows


def backup_and_initialize_csv():
    backup = "NONE"
    if CSV_PATH.exists():
        stamp = datetime.now().astimezone().strftime("%Y%m%d-%H%M%S")
        candidate = ROOT / f"gatling-workflow-results.backup-{stamp}.csv"
        sequence = 1
        while candidate.exists():
            candidate = ROOT / f"gatling-workflow-results.backup-{stamp}-{sequence}.csv"
            sequence += 1
        CSV_PATH.replace(candidate)
        backup = str(candidate)
    with CSV_PATH.open("x", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(CSV_FIELDS)
        handle.flush()
        os.fsync(handle.fileno())
    return backup


def write_state(phase, workflow, container, completed, total):
    temp = STATE_PATH.with_suffix(".state.tmp")
    temp.write_text(
        "\n".join(
            (
                f"phase={phase}",
                f"workflow={workflow}",
                f"container={container}",
                f"completed={completed}",
                f"total={total}",
            )
        )
        + "\n",
        encoding="utf-8",
    )
    temp.replace(STATE_PATH)


def parse_summary(log_path):
    last = None
    with log_path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = SUMMARY_PATTERN.search(line)
            if match:
                last = (match.group(1), match.group(2))
    return last if last is not None else ("UNKNOWN", "UNKNOWN")


def append_result(workflow, begin, end, ok, ko):
    with CSV_PATH.open("a", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow((workflow, begin, end, ok, ko))
        handle.flush()
        os.fsync(handle.fileno())


def request_stop(_signum, _frame):
    global STOP_REQUESTED
    STOP_REQUESTED = True


def run_batch(workflows):
    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    PID_PATH.write_text(f"{os.getpid()}\n", encoding="ascii")
    completed = 0
    try:
        for index, folder in enumerate(workflows):
            if STOP_REQUESTED:
                return 130
            workflow = folder.name
            container = f"{workflow}_{SUFFIX}"
            log_path = folder / "gatling.out"
            (folder / "Report").mkdir(exist_ok=True)
            write_state("RUNNING", workflow, container, completed, len(workflows))
            begin = timestamp()
            args = [
                "docker",
                "run",
                "--rm",
                "--log-opt",
                "max-size=10m",
                "--log-opt",
                "max-file=3",
                "--network",
                NETWORK,
                "--dns",
                DNS_IP,
                "--name",
                container,
                "-e",
                "MAVEN_GOAL=gatling-crank:crank",
                "-e",
                "MAVEN_OFFLINE=true",
                "-e",
                "GATLING_MAX_HEAP=4g",
                "-v",
                f"{folder}:/gatling/dataDirectory",
                "-v",
                f"{folder / 'Report'}:/gatling/results",
                IMAGE,
            ]
            with log_path.open("w", encoding="utf-8") as log_handle:
                process = subprocess.Popen(args, stdout=log_handle, stderr=subprocess.STDOUT)
                while process.poll() is None:
                    if STOP_REQUESTED:
                        subprocess.run(["docker", "stop", container], check=False)
                        process.wait()
                        break
                    time.sleep(1)
            end = timestamp()
            ok, ko = parse_summary(log_path)
            append_result(workflow, begin, end, ok, ko)
            completed += 1
            if STOP_REQUESTED:
                return 130
            if index + 1 < len(workflows):
                write_state("COOLDOWN", "", "", completed, len(workflows))
                for _ in range(COOLDOWN_SECONDS):
                    if STOP_REQUESTED:
                        return 130
                    time.sleep(1)
        return 0
    finally:
        if read_pid() == os.getpid():
            for path in (PID_PATH, STATE_PATH):
                try:
                    path.unlink()
                except FileNotFoundError:
                    pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preflight", action="store_true")
    args = parser.parse_args()
    try:
        workflows = preflight()
        print(f"PREFLIGHT_OK workflows={len(workflows)}", flush=True)
        if args.preflight:
            return 0
        backup = backup_and_initialize_csv()
        print(f"CSV_READY path={CSV_PATH} backup={backup}", flush=True)
        return run_batch(workflows)
    except Exception as exc:
        print(f"BATCH_START_FAILED {exc}", file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
