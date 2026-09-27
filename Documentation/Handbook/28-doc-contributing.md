# Contributing

This chapter covers the development workflow, coding conventions, and
testing practices for contributing to portage-ng.


## Reporting issues

Please report bugs, feature requests, and other issues through GitHub:

https://github.com/pvdabeel/portage-ng/issues

Do not use email or other informal channels for issue tracking.


## Development workflow

1. **Start from clean committed state.**  Always begin development with
   no uncommitted changes.

2. **Make changes** using the project wrapper for testing:

   ```bash
   ./Source/Application/Wrapper/portage-ng-dev --mode standalone --pretend <target>
   ```

3. **Run tests** to verify correctness:

   ```bash
   make test            # PLUnit tests
   make test-overlay    # Overlay regression tests
   ```

4. **Run compare analysis** to detect regressions. The compare harness
   lives in the [tinderbox-ng](https://github.com/pvdabeel/tinderbox-ng)
   repository and generates its own plan logs in fresh sessions (the
   legacy `--graph` + `.merge` regeneration loop is no longer part of
   this workflow):

   ```sh
   # Whole-tree matrix run (on the tinderbox host):
   sudo tinderbox-ng compare-matrix
   sudo tinderbox-ng analyze

   # Or a quick per-target compare while iterating locally:
   tinderbox-ng compare <category>/<package>
   ```

   `tinderbox-ng analyze` produces `analysis.json` + `analysis.txt` in
   the matrix run directory, replacing the old
   `compare-<date>-<hash>.json.gz` snapshots.

6. **Review the comparison table** for regressions in CN, CN+V, CN+V+U
   match percentages, ordering concordance, and assumption counts.

7. **Commit** when regression-free.


## How to run

### Dev wrapper

Always use the dev wrapper for testing — never run ad-hoc `swipl -g "..."`
snippets, as they miss required operator definitions, libraries, and module
load order:

```bash
./Source/Application/Wrapper/portage-ng-dev --mode standalone --pretend <target>
./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell
```

### Scripted sessions (here-doc pattern)

For reproducible, non-interactive debugging:

```bash
./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell --timeout 60 <<'PL'
resolver:test_stats(portage).
halt.
PL
```

### CI mode

For automated checks:

```bash
./Source/Application/Wrapper/portage-ng-dev --mode standalone --ci --pretend <target>
echo $?  # 0 = no assumptions, 1 = cycle breaks, 2 = domain assumptions
```

Always include `--pretend` to avoid mutating local state.


## Source file documentation style

Every `.pl` source file follows a strict layout.  Use
`Source/Application/System/bonjour.pl` as the canonical reference.

### File header

```prolog
/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/
```

### Module documentation (PlDoc)

```prolog
/** <module> MODULE_NAME_UPPERCASE
Short one-line description.

Optional longer description.
*/
```

Module name in the `<module>` tag is UPPERCASE.

### Module declaration

```prolog
:- module(modulename, []).
```

### Chapter header (one per file)

```prolog
% =============================================================================
% MODULE_NAME_UPPERCASE declarations
% =============================================================================
```

Exactly one `=====` chapter per file, immediately after `:- module`.

### Section headers

```prolog
% -----------------------------------------------------------------------------
% Section title
% -----------------------------------------------------------------------------
```

All subsequent sections use `-----` dashes.

### Predicate documentation

```prolog
%! module:predicate_name(+Arg1, -Arg2)
%
% Short description of what the predicate does.

module:predicate_name(Arg1, Arg2) :-
  body.
```

### Spacing rules

| **Element** | **Blank lines after** |
| :--- | :--- |
| File header `*/` | 1 |
| PlDoc module comment `*/` | 1 |
| `:- module(...)` declaration | 1 |
| `=====` chapter header | 1 |
| `-----` section header | 1 |
| Predicate doc + last clause | 2 |
| Between clauses of same predicate | 0 |
| End of file | 0 (no trailing blank line) |


## Naming conventions

- Source filenames must NOT contain hyphens (`-`) or underscores (`_`).
  Use concatenated lowercase words: `knowledgebase.pl`, not
  `knowledge_base.pl`.

- Exceptions (grandfathered, do not add new ones): `portage-ng.pl`
  (project entry point / name); `binpkg_exec.pl`, `binpkg_index.pl`,
  `binpkg_extract.pl`, `ebuild_exec.pl` and `missing_provider.pl`
  (underscore-named for readability of their prefixes; module names
  match the filenames).  Host-local templates under `Source/Config/Private/`
  are configuration, not source modules, and are also exempt.

- Prolog module names follow the same rule: `:- module(gentoo, [])`.

- Subdirectory names under `Source/` may use CamelCase:
  `Application/`, `Domain/`, `Config/`, `Pipeline/`.


## Comment guidelines

Do not add comments that just narrate what the code does.  Comments should
only explain non-obvious intent, trade-offs, or constraints.  Avoid:

```prolog
% Get the version     ← redundant
version:get(V).
```

Prefer:

```prolog
% Suffix rank maps PMS suffix ordering to integers for compare/3
suffix_rank('_alpha', 1).
```


## Compare tooling

Regression tooling is hosted in two places:

- **Merge-vs-emerge plan comparison** — driven by
  [tinderbox-ng](https://github.com/pvdabeel/tinderbox-ng) via
  `tinderbox-ng compare` / `tinderbox-ng compare-matrix` /
  `tinderbox-ng analyze`. The underlying Python script lives at
  `share/tinderbox-ng/compare-merge-emerge.py` in that repository and
  is invoked automatically by `tinderbox-ng analyze`. Outputs are
  `analysis.json` + `analysis.txt` in the matrix run directory.
- **md5-cache extractor regression** — `md5cache_validate/0,1` in
  `Source/Test/md5cache.pl` (re-extracts metadata via
  `Source/Domain/Gentoo/Ebuild/ebuild-depend.sh --batch` and diffs
  the result key by key against the on-disk md5-cache).

Do not create ad-hoc compare scripts outside these two locations.


## Further reading

- [Chapter 26: Testing and Regression](26-doc-testing.md) — testing methodology
- [Chapter 27: Performance and Profiling](27-doc-performance.md) — performance
  testing
- [Chapter 2: Installation and Quick Start](02-doc-installation.md) — build
  and run instructions
