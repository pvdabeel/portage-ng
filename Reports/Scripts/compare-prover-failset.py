#!/usr/bin/env python3
"""
Compare failed package sets between two prover:test(portage) logs.

Expected input logs are plain terminal captures of:
  ./Source/Scripts/portage-ng-dev --mode standalone --shell <<'PL'
  prover:test(portage).
  halt.
  PL

The script extracts package atoms from lines like:
  "... app-arch/unar-1.10.8 (failed)"

It also counts "Time limit exceeded" occurrences.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Dict, List, Set


ANSI_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
FAILED_RE = re.compile(r"([A-Za-z0-9+_.-]+/[A-Za-z0-9+_.@-]+-[^\s()]+)\s+\(failed\)")
TIMEOUT_RE = re.compile(r"Time limit exceeded", re.IGNORECASE)


def strip_ansi(s: str) -> str:
    return ANSI_RE.sub("", s)


def parse_log(path: Path) -> Dict[str, object]:
    raw = path.read_text(encoding="utf-8", errors="ignore")
    txt = strip_ansi(raw)
    failed: Set[str] = set()
    timeout_count = 0

    for line in txt.splitlines():
        m = FAILED_RE.search(line)
        if m:
            failed.add(m.group(1))
        if TIMEOUT_RE.search(line):
            timeout_count += 1

    return {
        "path": str(path),
        "failed": sorted(failed),
        "failed_count": len(failed),
        "timeout_count": timeout_count,
    }


def diff_sets(base_failed: Set[str], cand_failed: Set[str]) -> Dict[str, List[str]]:
    resolved = sorted(base_failed - cand_failed)
    new = sorted(cand_failed - base_failed)
    common = sorted(base_failed & cand_failed)
    return {
        "resolved_failures": resolved,
        "new_failures": new,
        "common_failures": common,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--baseline", required=True, help="Path to baseline log")
    ap.add_argument("--candidate", required=True, help="Path to candidate log")
    ap.add_argument(
        "--out",
        default="Reports/prover_failset_compare.json",
        help="Output JSON path",
    )
    ap.add_argument(
        "--show-limit",
        type=int,
        default=40,
        help="How many package names to show in console per section",
    )
    args = ap.parse_args()

    baseline = parse_log(Path(args.baseline))
    candidate = parse_log(Path(args.candidate))

    base_set = set(baseline["failed"])  # type: ignore[arg-type]
    cand_set = set(candidate["failed"])  # type: ignore[arg-type]
    delta = diff_sets(base_set, cand_set)

    out = {
        "baseline": baseline,
        "candidate": candidate,
        "delta": {
            "resolved_failures_count": len(delta["resolved_failures"]),
            "new_failures_count": len(delta["new_failures"]),
            "common_failures_count": len(delta["common_failures"]),
            **delta,
        },
    }

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(out, indent=2, sort_keys=True), encoding="utf-8")

    limit = max(0, args.show_limit)

    def preview(xs: List[str]) -> List[str]:
        return xs[:limit] if limit > 0 else []

    print("PROVER FAIL-SET COMPARISON")
    print(f"  baseline:  {baseline['path']}")
    print(f"  candidate: {candidate['path']}")
    print("")
    print(
        f"  baseline_failed={baseline['failed_count']} "
        f"baseline_timeouts={baseline['timeout_count']}"
    )
    print(
        f"  candidate_failed={candidate['failed_count']} "
        f"candidate_timeouts={candidate['timeout_count']}"
    )
    print("")
    print(
        f"  resolved_failures={len(delta['resolved_failures'])} "
        f"new_failures={len(delta['new_failures'])} "
        f"common_failures={len(delta['common_failures'])}"
    )

    if limit > 0:
        print("")
        print(f"RESOLVED (first {limit})")
        for x in preview(delta["resolved_failures"]):
            print(f"  - {x}")
        print("")
        print(f"NEW (first {limit})")
        for x in preview(delta["new_failures"]):
            print(f"  - {x}")

    print("")
    print(f"wrote: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

