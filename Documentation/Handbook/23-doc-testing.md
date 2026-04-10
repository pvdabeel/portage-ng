# Testing and Regression

portage-ng uses multiple testing strategies: PLUnit tests for unit logic,
overlay regression tests for end-to-end scenario validation, and
merge-vs-emerge comparison for correctness measurement against Portage.


## PLUnit tests

Standard SWI-Prolog unit tests in `Source/Test/unittest.pl`:

```bash
make test
```

These test individual predicates in isolation — version comparison,
domain operations, context merging, EAPI parsing, etc.


## Overlay regression tests

The overlay test suite (`make test-overlay`) runs 80 curated scenarios
against a test overlay in `Repository/Overlay/`.  Each scenario has a
specific dependency story and expected behavior.

### Running

```bash
make test-overlay
```

Or from the interactive shell:

```prolog
test:run(cases).
```

### Test scenario anatomy

Each test under `Documentation/Tests/testNN/` contains:

- **`README.md`** — description of the dependency story and expected
  outcome
- **`testNN.svg`** — dependency graph visualization
- **Collapsible transcripts** — `emerge -vp` vs `portage-ng --pretend`
  output for comparison

### Coverage areas

| **Area** | **Tests** |
| :--- | :--- |
| Basic ordering / default version | 01-02 |
| Cycles (self, indirect, 3-way, PDEPEND) | 03-08, 47, 61-64, 79 |
| Missing dependencies | 09-11 |
| Keywords (stable vs unstable) | 12 |
| Version operators (`=`, `>=`, `~`, `<=`) | 13, 55-56, 69-70, 80 |
| USE conditionals | 14-15 |
| Choice groups (`^^`, `||`, `??`) | 17-25 |
| Blockers (strong/weak) | 26-31, 60 |
| REQUIRED_USE | 32, 40 |
| USE dependencies (`[flag]`, `[-flag]`, `=`) | 33-39 |
| Slots (`:*`, `:=`, sub-slot) | 41-44 |
| Conflicts (USE, slot, diamond) | 45-46, 48-49, 51 |
| USE merge (shared deps) | 52-53 |
| Virtuals | 57-58 |
| Installed / VDB operations | 65, 73-77 |
| PDEPEND | 66, 79 |
| BDEPEND / IDEPEND | 67, 72 |
| Multi-slot co-install | 68 |
| Fetch-only | 71 |
| Onlydeps | 78 |

### XFAIL tests

Tests 58, 59, and 60 are explicitly marked as expected failures (XFAIL)
in the test matrix — known limitations that are documented but not yet
fixed.


## Merge vs emerge comparison

The primary correctness metric is comparison against Portage's `emerge`
output across the entire Portage tree.

### Running a comparison

```bash
python3 -u Reports/Scripts/compare-merge-emerge.py \
  --root /Volumes/Storage/Graph/portage \
  --full-lists \
  --out Reports/compare-$(date +%Y-%m-%d)-$(git rev-parse --short HEAD).json
```

### Metrics

The comparison produces several accuracy metrics:

| **Metric** | **Formula** | **Meaning** |
| :--- | :--- | :--- |
| **CN** | `100 * inter_cn / union_cn` | Category/Name match (ignoring version) |
| **CN+V** | `100 * inter_cnv / union_cnv` | Category/Name+Version match |
| **CN+V+U** | `100 * inter_cnvu / union_cnvu` | Full match including USE flags |
| **Order%** | `100 * (pairs - inversions) / pairs` | Ordering concordance |

Additional counts (from `emerge_ok` pairs only):

- `#blockers` — total blocker assumptions
- `#cycle breaks` — total prover cycle-break assumptions
- `#domain assumptions` — total domain assumptions

### Targeted comparison

For a single package:

```bash
python3 -u Reports/Scripts/compare-merge-emerge.py \
  --root /Volumes/Storage/Graph/portage \
  --target-regex '^sys-apps/portage-3.0.77-r3$' \
  --full-lists \
  --out Reports/compare-targeted.json
```


## Prover fail-set comparison

Compare two `prover:test(portage)` logs to detect regressions:

```bash
python3 Reports/Scripts/compare-prover-failset.py \
  --baseline baseline.log \
  --candidate candidate.log \
  --out Reports/prover_failset_compare.json
```


## Further reading

- [Chapter 2: Installation and Quick Start](02-doc-installation.md) — `make test`
  commands
- [Chapter 24: Performance and Profiling](24-doc-performance.md) —
  `prover:test_stats` for bulk testing
- [Chapter 25: Contributing](25-doc-contributing.md) — development workflow
  with regression testing
