#!/usr/bin/env bash
# generate-emerge-files.sh — generate/update .emerge files for all ebuilds
#
# Usage:
#   generate-emerge-files.sh [--root DIR] [--repo DIR] [--jobs N]
#                            [--force] [--target-regex REGEX]
#
# Finds every .ebuild in the portage tree and runs emerge-vp for each one,
# writing the output to {root}/{category}/{name-version}.emerge.
# In incremental mode (default), skips ebuilds whose .emerge file is newer
# than the .ebuild source.

set -euo pipefail

GRAPH_ROOT="$HOME/Graph/portage"
REPO_DIR="$HOME/Repository/portage-git"
EMERGE_VP="$HOME/gentoo-prefix/bin/emerge-vp"
JOBS=1
FORCE=0
TARGET_REGEX=""
TIMEOUT=120

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --root DIR          Graph output directory   (default: $GRAPH_ROOT)
  --repo DIR          Portage tree directory    (default: $REPO_DIR)
  --jobs N            Parallel workers          (default: $JOBS)
  --force             Regenerate all files
  --target-regex RE   Only process matching category/name-version entries
  --timeout SECS      Per-ebuild timeout        (default: $TIMEOUT)
  -h, --help          Show this help
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)         GRAPH_ROOT="$2"; shift 2 ;;
    --repo)         REPO_DIR="$2";   shift 2 ;;
    --jobs)         JOBS="$2";       shift 2 ;;
    --force)        FORCE=1;         shift   ;;
    --target-regex) TARGET_REGEX="$2"; shift 2 ;;
    --timeout)      TIMEOUT="$2";    shift 2 ;;
    -h|--help)      usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

if [[ ! -d "$REPO_DIR" ]]; then
  echo "error: repo directory not found: $REPO_DIR" >&2
  exit 1
fi
if [[ ! -x "$EMERGE_VP" ]]; then
  echo "error: emerge-vp not found: $EMERGE_VP" >&2
  exit 1
fi

export GRAPH_ROOT REPO_DIR EMERGE_VP FORCE TIMEOUT

PROGRESS_DIR=$(mktemp -d)
DONE_DIR="$PROGRESS_DIR/done"
SKIP_DIR="$PROGRESS_DIR/skip"
mkdir -p "$DONE_DIR" "$SKIP_DIR"
export PROGRESS_DIR DONE_DIR SKIP_DIR

process_one() {
  local ebuild_path="$1"

  local rel="${ebuild_path#$REPO_DIR/}"
  local category="${rel%%/*}"
  local rest="${rel#*/}"       # name/name-version.ebuild
  local namever="${rest#*/}"   # name-version.ebuild
  namever="${namever%.ebuild}" # name-version

  local cpv="$category/$namever"
  local outfile="$GRAPH_ROOT/$category/$namever.emerge"

  if [[ "$FORCE" -eq 0 && -f "$outfile" && "$outfile" -nt "$ebuild_path" ]]; then
    touch "$SKIP_DIR/$$.$RANDOM"
    return 0
  fi

  mkdir -p "$GRAPH_ROOT/$category"

  local tmpfile="$outfile.tmp.$$"
  local t_start_ms t_end_ms wall_ms t_start_s

  t_start_ms=$(python3 -c "import time; print(int(time.time()*1000))")
  t_start_s=$((t_start_ms / 1000))

  {
    echo "% emerge started: $t_start_s ($(date -r "$t_start_s" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@$t_start_s" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '?'))"
    echo ""

    if command -v gtimeout >/dev/null 2>&1; then
      gtimeout "$TIMEOUT" "$EMERGE_VP" --color y "=$cpv" 2>&1 || true
    elif command -v timeout >/dev/null 2>&1; then
      timeout "$TIMEOUT" "$EMERGE_VP" --color y "=$cpv" 2>&1 || true
    else
      "$EMERGE_VP" --color y "=$cpv" 2>&1 || true
    fi

    t_end_ms=$(python3 -c "import time; print(int(time.time()*1000))")
    local t_end_s=$((t_end_ms / 1000))
    wall_ms=$((t_end_ms - t_start_ms))
    echo ""
    echo "% emerge ended: $t_end_s ($(date -r "$t_end_s" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@$t_end_s" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '?'))"
    echo "% emerge wall_time_ms: $wall_ms"
  } > "$tmpfile"

  mv -f "$tmpfile" "$outfile"
  touch "$DONE_DIR/$$.$RANDOM"
}
export -f process_one

# Build list of ebuilds
mapfile -t EBUILDS < <(find "$REPO_DIR" -name '*.ebuild' -type f | sort)
TOTAL=${#EBUILDS[@]}

if [[ -n "$TARGET_REGEX" ]]; then
  FILTERED=()
  for eb in "${EBUILDS[@]}"; do
    rel="${eb#$REPO_DIR/}"
    cat="${rel%%/*}"
    rest="${rel#*/}"
    nv="${rest#*/}"
    nv="${nv%.ebuild}"
    cpv="$cat/$nv"
    if [[ "$cpv" =~ $TARGET_REGEX ]]; then
      FILTERED+=("$eb")
    fi
  done
  EBUILDS=("${FILTERED[@]}")
  TOTAL=${#EBUILDS[@]}
fi

echo "Generating .emerge files: $TOTAL ebuilds, $JOBS parallel jobs"
echo "  repo:  $REPO_DIR"
echo "  root:  $GRAPH_ROOT"
echo ""

GLOBAL_START=$(date +%s)

fmt_duration() {
  local secs=$1
  local h=$((secs / 3600))
  local m=$(( (secs % 3600) / 60 ))
  local s=$((secs % 60))
  if [[ $h -gt 0 ]]; then
    printf "%dh%02dm%02ds" "$h" "$m" "$s"
  elif [[ $m -gt 0 ]]; then
    printf "%dm%02ds" "$m" "$s"
  else
    printf "%ds" "$s"
  fi
}

# Feed ebuild paths to xargs in background
printf '%s\n' "${EBUILDS[@]}" | xargs -P "$JOBS" -I{} bash -c 'process_one "$@"' _ {} &
XARGS_PID=$!

# Monitor loop: count marker files for race-free progress
while kill -0 "$XARGS_PID" 2>/dev/null; do
  sleep 1
  local_done=$(find "$DONE_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
  local_skip=$(find "$SKIP_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
  processed=$((local_done + local_skip))
  now=$(date +%s)
  elapsed=$((now - GLOBAL_START))
  elapsed_str=$(fmt_duration $elapsed)

  if [[ $local_done -gt 0 && $processed -lt $TOTAL ]]; then
    avg_s=$(( elapsed * 1000 / local_done ))
    remaining=$((TOTAL - processed))
    eta_s=$(( remaining * avg_s / 1000 ))
    eta_str=$(fmt_duration $eta_s)
    printf "\r  [%d/%d] done:%d skip:%d | elapsed: %s | eta: ~%s        " \
      "$processed" "$TOTAL" "$local_done" "$local_skip" "$elapsed_str" "$eta_str" >&2
  else
    printf "\r  [%d/%d] done:%d skip:%d | elapsed: %s        " \
      "$processed" "$TOTAL" "$local_done" "$local_skip" "$elapsed_str" >&2
  fi
done

wait "$XARGS_PID" || true

# Final stats
local_done=$(find "$DONE_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
local_skip=$(find "$SKIP_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
now=$(date +%s)
elapsed=$((now - GLOBAL_START))
elapsed_str=$(fmt_duration $elapsed)

printf "\r  [%d/%d] done:%d skip:%d | elapsed: %s              \n" \
  "$TOTAL" "$TOTAL" "$local_done" "$local_skip" "$elapsed_str" >&2
echo ""
echo "Done. $local_done generated, $local_skip skipped (up-to-date), total elapsed: $elapsed_str."

rm -rf "$PROGRESS_DIR"
