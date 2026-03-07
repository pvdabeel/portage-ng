#!/usr/bin/env python3
"""
Extract timing information from .emerge and .merge files into a JSON database.

Reads all .emerge and .merge files under a graph root directory, parses the
timing metadata lines (% emerge/merge started/ended/wall_time_ms), and writes
a consolidated JSON file mapping each entry to its timing data.

Usage:
    python3 Source/Scripts/extract-timing.py \
        --root /Volumes/Storage/Graph/portage \
        --out Reports/timing.json

Output structure:
{
  "root": "/Volumes/Storage/Graph/portage",
  "entries": {
    "cat/pkg-ver": {
      "emerge_ms": 3524,        // from .emerge file
      "merge_ms": 1200,         // from .merge file
      "emerge_started": 1772248866,
      "emerge_ended": 1772248870,
      "merge_started": ...,
      "merge_ended": ...,
      "ratio": 0.34             // merge_ms / emerge_ms
    },
    ...
  },
  "summary": {
    "total_emerge_files": 32012,
    "total_merge_files": 32012,
    "both_present": 30000,
    "emerge_only": 2012,
    "merge_only": 0,
    "avg_emerge_ms": 2500.0,
    "avg_merge_ms": 800.0,
    "avg_ratio": 0.32,
    "median_emerge_ms": ...,
    "median_merge_ms": ...,
    "median_ratio": ...,
    "p95_emerge_ms": ...,
    "p95_merge_ms": ...,
    "p95_ratio": ...,
    "merge_faster_count": ...,
    "emerge_faster_count": ...
  }
}
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path
from statistics import median


def parse_timing_lines(filepath: str, prefix: str) -> dict:
    """Parse % <prefix> started/ended/wall_time_ms lines from a file.

    Reads only the first 5 and last 5 lines for efficiency (timing lines
    are at the very start and end of each file).
    """
    result = {}
    try:
        with open(filepath, "r", errors="replace") as f:
            lines = f.readlines()
    except (OSError, IOError):
        return result

    check_lines = lines[:5] + lines[-5:] if len(lines) > 10 else lines

    for line in check_lines:
        line = line.strip()
        m = re.match(rf"^%\s+{prefix}\s+started:\s+(\d+)", line)
        if m:
            result["started"] = int(m.group(1))
            continue
        m = re.match(rf"^%\s+{prefix}\s+ended:\s+(\d+)", line)
        if m:
            result["ended"] = int(m.group(1))
            continue
        m = re.match(rf"^%\s+{prefix}\s+wall_time_ms:\s+(\d+)", line)
        if m:
            result["wall_time_ms"] = int(m.group(1))
            continue

    return result


def scan_directory(root: str) -> dict:
    """Walk the graph root and collect timing from all .emerge and .merge files."""
    entries = {}
    root_path = Path(root)

    for dirpath, _dirnames, filenames in os.walk(root):
        rel_dir = Path(dirpath).relative_to(root_path)
        category = str(rel_dir)
        if category == ".":
            continue

        for fname in sorted(filenames):
            if fname.endswith(".emerge"):
                cpv = f"{category}/{fname[:-7]}"  # strip .emerge
                timing = parse_timing_lines(os.path.join(dirpath, fname), "emerge")
                if cpv not in entries:
                    entries[cpv] = {}
                if "wall_time_ms" in timing:
                    entries[cpv]["emerge_ms"] = timing["wall_time_ms"]
                if "started" in timing:
                    entries[cpv]["emerge_started"] = timing["started"]
                if "ended" in timing:
                    entries[cpv]["emerge_ended"] = timing["ended"]

            elif fname.endswith(".merge"):
                cpv = f"{category}/{fname[:-6]}"  # strip .merge
                timing = parse_timing_lines(os.path.join(dirpath, fname), "merge")
                if cpv not in entries:
                    entries[cpv] = {}
                if "wall_time_ms" in timing:
                    entries[cpv]["merge_ms"] = timing["wall_time_ms"]
                if "started" in timing:
                    entries[cpv]["merge_started"] = timing["started"]
                if "ended" in timing:
                    entries[cpv]["merge_ended"] = timing["ended"]

    # Compute ratios where both timings are available
    for cpv, data in entries.items():
        if "emerge_ms" in data and "merge_ms" in data and data["emerge_ms"] > 0:
            data["ratio"] = round(data["merge_ms"] / data["emerge_ms"], 4)

    return entries


def compute_summary(entries: dict) -> dict:
    """Compute aggregate statistics."""
    emerge_only = sum(1 for e in entries.values() if "emerge_ms" in e and "merge_ms" not in e)
    merge_only = sum(1 for e in entries.values() if "merge_ms" in e and "emerge_ms" not in e)
    both = sum(1 for e in entries.values() if "emerge_ms" in e and "merge_ms" in e)

    emerge_times = [e["emerge_ms"] for e in entries.values() if "emerge_ms" in e]
    merge_times = [e["merge_ms"] for e in entries.values() if "merge_ms" in e]
    ratios = [e["ratio"] for e in entries.values() if "ratio" in e]

    def percentile(data, p):
        if not data:
            return 0
        s = sorted(data)
        k = (len(s) - 1) * p / 100
        f = int(k)
        c = f + 1 if f + 1 < len(s) else f
        return s[f] + (s[c] - s[f]) * (k - f)

    summary = {
        "total_emerge_files": len(emerge_times),
        "total_merge_files": len(merge_times),
        "both_present": both,
        "emerge_only": emerge_only,
        "merge_only": merge_only,
    }

    if emerge_times:
        summary["avg_emerge_ms"] = round(sum(emerge_times) / len(emerge_times), 1)
        summary["median_emerge_ms"] = round(median(emerge_times), 1)
        summary["p95_emerge_ms"] = round(percentile(emerge_times, 95), 1)

    if merge_times:
        summary["avg_merge_ms"] = round(sum(merge_times) / len(merge_times), 1)
        summary["median_merge_ms"] = round(median(merge_times), 1)
        summary["p95_merge_ms"] = round(percentile(merge_times, 95), 1)

    if ratios:
        summary["avg_ratio"] = round(sum(ratios) / len(ratios), 4)
        summary["median_ratio"] = round(median(ratios), 4)
        summary["p95_ratio"] = round(percentile(ratios, 95), 4)
        summary["merge_faster_count"] = sum(1 for r in ratios if r < 1.0)
        summary["emerge_faster_count"] = sum(1 for r in ratios if r > 1.0)
        summary["equal_count"] = sum(1 for r in ratios if r == 1.0)

    return summary


def main():
    parser = argparse.ArgumentParser(description="Extract timing from .emerge/.merge files")
    parser.add_argument("--root", required=True, help="Graph root directory")
    parser.add_argument("--out", required=True, help="Output JSON file")
    args = parser.parse_args()

    if not os.path.isdir(args.root):
        print(f"Error: {args.root} is not a directory", file=sys.stderr)
        sys.exit(1)

    print(f"Scanning {args.root} ...", file=sys.stderr)
    entries = scan_directory(args.root)
    summary = compute_summary(entries)

    result = {
        "root": args.root,
        "summary": summary,
        "entries": entries,
    }

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "w") as f:
        json.dump(result, f, indent=2, sort_keys=False)

    print(f"Wrote {len(entries)} entries to {args.out}", file=sys.stderr)
    print(f"Summary:", file=sys.stderr)
    for k, v in summary.items():
        print(f"  {k}: {v}", file=sys.stderr)


if __name__ == "__main__":
    main()
