# Upstream and Bug Tracking

portage-ng integrates with external services to check upstream versions
and search for known issues, helping users identify outdated packages and
known dependency bugs.


## Git repository integration

portage-ng can connect directly to a Git repository and turn Git
metadata into Prolog facts.  This means it can inspect commit
history, changelogs, and file-level changes for any ebuild without
relying on separate tools.  The Git metadata is ingested alongside
the regular cache data, so queries like "when was this ebuild last
updated?" or "which ebuilds changed in the last sync?" can be
answered from within the resolver.


## Upstream version checking

The upstream module (`Source/Domain/Gentoo/upstream.pl`) checks package
versions against upstream releases via the Repology API.

### Usage

```bash
portage-ng --upstream sys-apps/portage
portage-ng --upstream @world
```

### How it works

1. For each target package, the module queries the Repology API
   (`https://repology.org/api/v1/project/<name>`) for version information.

2. The response includes version data across multiple distributions,
   which is compared against the version in the local Portage tree.

3. Results are categorized:
   - **Up to date** — local version matches or exceeds upstream
   - **Outdated** — a newer upstream version exists
   - **Unknown** — package not tracked by Repology

### Output

The upstream check displays a comparison table showing the local version,
the latest upstream version, and the status for each package.


## Gentoo Bugzilla integration

The bugs module (`Source/Domain/Gentoo/bugs.pl`) searches Gentoo's
Bugzilla instance for known issues related to packages.

### Usage

```bash
portage-ng --bugs sys-apps/portage
```

### How it works

1. The module queries Gentoo Bugzilla's REST API for bugs matching the
   package atom.

2. Results are filtered and displayed with bug number, summary, status,
   and assignee.

This helps users identify whether a dependency resolution failure is due
to a known upstream bug rather than a portage-ng issue.


## Automatic bug report drafts

The issue module (`Source/Domain/Gentoo/issue.pl`) generates structured
Gentoo Bugzilla bug report drafts when the prover detects unsatisfiable
dependencies.

A generated report includes:

- **Summary** — one-line description of the issue
- **Affected package** — the package atom
- **Unsatisfiable constraints** — the specific dependency that cannot be
  met
- **Observed state** — what the prover found (missing package, version
  conflict, REQUIRED_USE violation)
- **Suggested fix** — recommended action (add keyword, unmask, fix
  dependency)

These drafts can be used as starting points for filing bugs with the
Gentoo bug tracker.


## Further reading

- [Chapter 14: Command-Line Interface](14-doc-cli.md) — `--upstream` and
  `--bugs` flags
- [Chapter 9: Assumptions and Constraint Learning](09-doc-prover-assumptions.md) —
  how unsatisfiable dependencies are detected
