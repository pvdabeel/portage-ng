# Contributing

This chapter covers the development workflow, coding conventions, and
testing practices for contributing to portage-ng.


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

4. **Regenerate `.merge` files** by asking the maintainer to run `--graph`
   to produce updated `.merge` output for the graph directory.

5. **Run compare analysis** to detect regressions:

   ```bash
   python3 -u Reports/Scripts/compare-merge-emerge.py \
     --root /Volumes/Storage/Graph/portage \
     --full-lists \
     --out Reports/compare-$(date +%Y-%m-%d)-$(git rev-parse --short HEAD).json
   ```

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
prover:test_stats(portage).
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

- Exception: `portage-ng.pl` (project entry point).

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

Comparison scripts live in `Reports/Scripts/`:

- `compare-merge-emerge.py` — merge-vs-emerge plan comparison
- `compare-prover-failset.py` — prover fail-set regression detection

Report filenames follow the format:
`compare-<YYYY-MM-DD>-<short-commit-hash>.json`

Do not create ad-hoc compare scripts outside `Reports/Scripts/`.


## Further reading

- [Chapter 23: Testing and Regression](23-doc-testing.md) — testing methodology
- [Chapter 24: Performance and Profiling](24-doc-performance.md) — performance
  testing
- [Chapter 2: Installation and Quick Start](02-doc-installation.md) — build
  and run instructions
