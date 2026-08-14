#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {Path(sys.argv[0]).name} <domain>", file=sys.stderr)
        return 64

    domain = sys.argv[1]
    if re.fullmatch(r"[A-Za-z0-9_-]+", domain) is None:
        print("Unsafe domain", file=sys.stderr)
        return 64

    policy_path = Path(__file__).resolve().parent.parent / "vars" / "expected-not-queued.json"
    with policy_path.open(encoding="utf-8") as policy_file:
        policy = json.load(policy_file)

    defaults = policy["stale_stats_expected_not_queued_defaults"]
    domain_additions = policy["stale_stats_expected_not_queued_by_domain"].get(
        domain.lower(), []
    )
    print(",".join(defaults + domain_additions))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
