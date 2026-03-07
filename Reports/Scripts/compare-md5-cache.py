#!/usr/bin/env python3
"""
Validate ebuild-depend.sh output against existing md5-cache entries.

Usage:
    python3 validate-md5-cache.py --repo <portage-tree> [--limit N] [--verbose]

Runs ebuild-depend.sh in --batch mode over all (or N) ebuilds that have
corresponding md5-cache entries, then compares the produced metadata against
the cached version.

Keys compared (intersection of both outputs, ignoring _md5_ and _eclasses_):
    BDEPEND DEFINED_PHASES DEPEND DESCRIPTION EAPI HOMEPAGE IDEPEND
    INHERIT IUSE KEYWORDS LICENSE PDEPEND PROPERTIES RDEPEND
    REQUIRED_USE RESTRICT SLOT SRC_URI

Keys intentionally skipped:
    _md5_      – portage-internal hash
    _eclasses_ – portage-internal eclass tracking
    INHERITED  – only in our output (md5-cache doesn't carry it)
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

SKIP_KEYS = {"_md5_", "_eclasses_", "INHERITED"}

METADATA_KEYS = [
    "BDEPEND", "DEFINED_PHASES", "DEPEND", "DESCRIPTION", "EAPI",
    "HOMEPAGE", "IDEPEND", "INHERIT", "IUSE", "KEYWORDS", "LICENSE",
    "PDEPEND", "PROPERTIES", "RDEPEND", "REQUIRED_USE", "RESTRICT",
    "SLOT", "SRC_URI",
]


def parse_kv_block(lines):
    """Parse KEY=VALUE lines into a dict. Handles multi-line values (continuation)."""
    result = {}
    for line in lines:
        line = line.rstrip("\n")
        if not line:
            continue
        eq = line.find("=")
        if eq < 0:
            continue
        key = line[:eq]
        val = line[eq + 1:]
        result[key] = val
    return result


def read_md5_cache(path):
    """Read an md5-cache file and return a dict of KEY=VALUE pairs."""
    with open(path, "r") as f:
        return parse_kv_block(f.readlines())


def find_ebuild_for_cache(repo, category, pf):
    """Given category and PF (e.g. portage-3.0.77-r3), find the ebuild path."""
    cat_dir = os.path.join(repo, category)
    if not os.path.isdir(cat_dir):
        return None
    for pn_dir in os.listdir(cat_dir):
        ebuild = os.path.join(cat_dir, pn_dir, pf + ".ebuild")
        if os.path.isfile(ebuild):
            return ebuild, pn_dir
    return None


def split_pf(pn, pf):
    """Split PF into PV, PR, PVR given PN."""
    pvr = pf[len(pn) + 1:]  # strip "PN-"
    m = re.match(r"^(.*?)(-r\d+)$", pvr)
    if m:
        pv = m.group(1)
        pr = m.group(2)[1:]  # strip leading '-'
    else:
        pv = pvr
        pr = ""
    return pv, pr, pvr


def build_batch_line(category, pn, pf, ebuild, repo):
    """Build a batch input descriptor line."""
    pv, pr, pvr = split_pf(pn, pf)
    p = f"{pn}-{pv}"
    return (
        f"CATEGORY={category} PN={pn} PV={pv} PR={pr} "
        f"PVR={pvr} PF={pf} P={p} EBUILD={ebuild}"
    )


def normalize_value(val):
    """Normalize whitespace in a metadata value for comparison."""
    return " ".join(val.split())


def compare_entry(cache_kv, our_kv, pf_id):
    """Compare two key-value dicts. Returns list of (key, cache_val, our_val) diffs."""
    diffs = []
    for key in METADATA_KEYS:
        if key in SKIP_KEYS:
            continue
        cache_val = normalize_value(cache_kv.get(key, ""))
        our_val = normalize_value(our_kv.get(key, ""))
        if cache_val != our_val:
            diffs.append((key, cache_val, our_val))
    return diffs


def main():
    parser = argparse.ArgumentParser(description="Validate ebuild-depend.sh vs md5-cache")
    parser.add_argument("--repo", required=True, help="Path to portage tree")
    parser.add_argument("--limit", type=int, default=0, help="Limit to first N ebuilds (0=all)")
    parser.add_argument("--verbose", action="store_true", help="Show per-ebuild diffs")
    parser.add_argument("--out", help="Write JSON report to this file")
    parser.add_argument("--script", help="Path to ebuild-depend.sh",
                        default=os.path.join(os.path.dirname(__file__), "../../Source/Ebuild/ebuild-depend.sh"))
    args = parser.parse_args()

    repo = os.path.abspath(args.repo)
    cache_dir = os.path.join(repo, "metadata", "md5-cache")

    if not os.path.isdir(cache_dir):
        print(f"error: md5-cache not found at {cache_dir}", file=sys.stderr)
        sys.exit(1)

    if not os.path.isfile(args.script):
        print(f"error: ebuild-depend.sh not found at {args.script}", file=sys.stderr)
        sys.exit(1)

    # Discover all cache entries and prepare batch input
    print("Discovering md5-cache entries...", flush=True)
    entries = []  # (category, pf, cache_path)
    for category in sorted(os.listdir(cache_dir)):
        cat_path = os.path.join(cache_dir, category)
        if not os.path.isdir(cat_path):
            continue
        for pf in sorted(os.listdir(cat_path)):
            fp = os.path.join(cat_path, pf)
            if os.path.isfile(fp):
                entries.append((category, pf, fp))

    total = len(entries)
    if args.limit > 0:
        entries = entries[:args.limit]
    print(f"Found {total} md5-cache entries, processing {len(entries)}.", flush=True)

    # Build batch input
    print("Building batch descriptors...", flush=True)
    batch_lines = []
    entry_map = {}  # index -> (category, pf, cache_path)
    skipped_no_ebuild = 0
    for i, (category, pf, cache_path) in enumerate(entries):
        result = find_ebuild_for_cache(repo, category, pf)
        if result is None:
            skipped_no_ebuild += 1
            continue
        ebuild, pn = result
        line = build_batch_line(category, pn, pf, ebuild, repo)
        idx = len(batch_lines)
        batch_lines.append(line)
        entry_map[idx] = (category, pf, cache_path, f"{category}/{pf}")

    print(f"  {len(batch_lines)} ebuilds matched, {skipped_no_ebuild} skipped (no ebuild found).", flush=True)

    # Run batch
    print(f"Running ebuild-depend.sh --batch ({len(batch_lines)} ebuilds)...", flush=True)
    batch_input = "\n".join(batch_lines) + "\n"
    t0 = time.time()
    proc = subprocess.run(
        [args.script, "--batch", repo],
        input=batch_input, capture_output=True, text=True, timeout=1800,
    )
    elapsed = time.time() - t0
    print(f"  Batch completed in {elapsed:.1f}s (exit={proc.returncode}).", flush=True)

    if proc.returncode != 0:
        print(f"  stderr (last 500 chars): ...{proc.stderr[-500:]}", file=sys.stderr)

    # Parse batch output into blocks (delimited by ---END---)
    blocks = []
    current = []
    for line in proc.stdout.split("\n"):
        if line == "---END---":
            blocks.append(current)
            current = []
        else:
            current.append(line)

    print(f"  Parsed {len(blocks)} output blocks.", flush=True)

    # Compare
    print("Comparing output vs md5-cache...", flush=True)
    match_count = 0
    diff_count = 0
    missing_output = 0
    key_diff_counts = Counter()
    diff_details = []

    for idx in range(len(batch_lines)):
        cat, pf, cache_path, pf_id = entry_map[idx]
        cache_kv = read_md5_cache(cache_path)

        if idx < len(blocks):
            our_kv = parse_kv_block(blocks[idx])
        else:
            missing_output += 1
            continue

        if not our_kv:
            missing_output += 1
            continue

        diffs = compare_entry(cache_kv, our_kv, pf_id)
        if diffs:
            diff_count += 1
            detail = {"ebuild": pf_id, "diffs": []}
            for key, cache_val, our_val in diffs:
                key_diff_counts[key] += 1
                detail["diffs"].append({
                    "key": key,
                    "expected": cache_val[:200],
                    "got": our_val[:200],
                })
            diff_details.append(detail)
            if args.verbose:
                print(f"\n  DIFF: {pf_id}")
                for key, cv, ov in diffs:
                    print(f"    {key}:")
                    print(f"      expected: {cv[:120]}")
                    print(f"           got: {ov[:120]}")
        else:
            match_count += 1

    # Summary
    print("\n" + "=" * 60)
    print("VALIDATION SUMMARY")
    print("=" * 60)
    print(f"Total md5-cache entries:   {total}")
    print(f"Processed:                 {len(batch_lines)}")
    print(f"Skipped (no ebuild):       {skipped_no_ebuild}")
    print(f"Missing output:            {missing_output}")
    print(f"Exact match:               {match_count}")
    print(f"Mismatched:                {diff_count}")
    pct = 100.0 * match_count / max(match_count + diff_count, 1)
    print(f"Match rate:                {pct:.2f}%")
    print(f"Batch time:                {elapsed:.1f}s")
    print(f"Per-ebuild avg:            {1000*elapsed/max(len(batch_lines),1):.1f}ms")

    if key_diff_counts:
        print(f"\nMismatches by key:")
        for key, cnt in key_diff_counts.most_common():
            print(f"  {key}: {cnt}")

    if diff_details and not args.verbose:
        print(f"\nFirst 10 mismatches (use --verbose for all):")
        for d in diff_details[:10]:
            print(f"  {d['ebuild']}:")
            for dd in d["diffs"]:
                print(f"    {dd['key']}: expected={dd['expected'][:80]!r}")
                print(f"    {dd['key']}:      got={dd['got'][:80]!r}")

    # JSON report
    if args.out:
        report = {
            "total_cache": total,
            "processed": len(batch_lines),
            "skipped_no_ebuild": skipped_no_ebuild,
            "missing_output": missing_output,
            "exact_match": match_count,
            "mismatched": diff_count,
            "match_rate_pct": round(pct, 2),
            "batch_time_s": round(elapsed, 1),
            "per_ebuild_ms": round(1000 * elapsed / max(len(batch_lines), 1), 1),
            "key_diff_counts": dict(key_diff_counts.most_common()),
            "diff_details": diff_details[:100],
        }
        with open(args.out, "w") as f:
            json.dump(report, f, indent=2)
        print(f"\nReport written to {args.out}")

    sys.exit(0 if diff_count == 0 else 1)


if __name__ == "__main__":
    main()
