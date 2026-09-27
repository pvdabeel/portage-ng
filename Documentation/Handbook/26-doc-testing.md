# Testing and Regression

portage-ng uses multiple testing strategies: PLUnit tests for unit logic,
overlay regression tests for end-to-end scenario validation, and
merge-vs-emerge comparison for correctness measurement against Portage.


## PLUnit tests

Standard SWI-Prolog unit tests, one file per subject under
`Source/Test/Unit/` (loaded together by `Source/Test/unittest.pl`):

```bash
make test
```

These test individual predicates in isolation — version comparison,
domain operations, context merging, EAPI parsing, etc.


## Overlay regression tests

The overlay test suite (`make test-overlay`) runs 80 curated scenarios
against a test overlay in `Repository/Overlay/`.  Each scenario has a
specific dependency story and expected behavior.

For onboarding, treat a subset as **policy specimens** (not only CI):
see [Policy by example](Policy/examples.md) and the
[policy cards](Policy/README.md).

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
| Fetch-only (`:run` proof + print filter) | 71 |
| Onlydeps | 78 |

### Failure testing

Test 58 is explicitly marked as an expected failure (XFAIL) via
`test:xfail/2` — it exercises PROVIDE-based virtuals, deprecated in
PMS; a documented limitation that will not be fixed.


## Merge vs emerge comparison

The primary correctness metric is comparison against Portage's `emerge`
output across the entire Portage tree. The comparison harness now lives
in the [tinderbox-ng](https://github.com/pvdabeel/tinderbox-ng)
repository, which drives both engines through identical sessions and
analyses the resulting plan logs.

### Running a comparison

Per-target compare (plan only, fresh sessions on both sides):

```sh
tinderbox-ng compare www-servers/apache
```

Whole-tree matrix run plus aggregate analysis:

```sh
tinderbox-ng new regress
tinderbox-ng exec regress -- \
  tinderbox-matrix resolver \
  /usr/local/share/tinderbox-ng/share/tinderbox-ng/manifest-1000.txt
tinderbox-ng analyze \
  --md5-cache /srv/tinderbox-ng/baseline/var/db/repos/gentoo/metadata/md5-cache
```

`tinderbox-ng analyze` feeds each `portage-ng.plan.log` / `emerge.plan.log`
pair through `share/tinderbox-ng/compare-merge-emerge.py` (inside the
tinderbox-ng repo) and writes `analysis.json` + `analysis.txt` into the
matrix run directory.

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

For a single package, use `--target-regex` on `tinderbox-ng analyze`:

```sh
sudo tinderbox-ng analyze --target-regex '^sys-apps/portage-3.0.77-r3$'
```

Or run a one-off per-target compare directly:

```sh
tinderbox-ng compare sys-apps/portage
```


## Bulk plan fingerprint comparison

`Source/Test/plancompare.pl` fingerprints the full pipeline (resolve +
order) for every ebuild in a repository.  Use it to verify that a
resolver change produces identical plans before committing:

```sh
./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell <<'PL'
load_files(portage('Source/Test/plancompare'), [if(true)]).
plancompare:run(portage, '/tmp/plan-compare.tsv').
halt.
PL
```

Compare two TSV files from before/after runs:

```sh
plancompare:diff('/tmp/before.tsv', '/tmp/after.tsv').
```


## md5-cache extractor regression

`md5cache_validate/0,1` (in `Source/Test/md5cache.pl`) runs the
standalone bash extractor at
`Source/Domain/Gentoo/Ebuild/ebuild-depend.sh --batch` over every
md5-cache entry in the configured Portage tree and diffs the produced
metadata against the on-disk cache, key by key.

```sh
./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell <<'PL'
load_files(portage('Source/Test/md5cache'), [if(true)]).
md5cache_validate([limit(50), verbose(true)]).
halt.
PL
```

Options: `repo(Atom)` (default `portage`), `limit(N)` (0 = all),
`verbose(Bool)`, `out(Path)` (writes a Prolog-term report).


## Further reading

- [Chapter 2: Installation and Quick Start](02-doc-installation.md) — `make test`
  commands
- [Chapter 27: Performance and Profiling](27-doc-performance.md) —
  `resolver:test_stats` for bulk testing
- [Chapter 28: Contributing](28-doc-contributing.md) — development workflow
  with regression testing
