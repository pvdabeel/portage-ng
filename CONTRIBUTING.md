# Contributing to portage-ng

## Getting started

1. **Clone the repository:**

   ```bash
   git clone <repo-url>
   cd portage-ng
   ```

2. **Prerequisites:** SWI-Prolog >= 9.3 (development version recommended).

3. **Host configuration:** Copy the template to match your hostname:

   ```bash
   cp Source/Config/Template/example.pl "Source/Config/$(hostname).pl"
   ```

   Edit the new file to set your local Portage tree path, VDB location,
   and distfiles directory. See `Source/Config/default.pl` for reference.

4. **Run from source** using the dev wrapper (never `swipl` directly):

   ```bash
   ./Source/Scripts/Wrapper/portage-ng-dev --mode standalone --pretend app-editors/neovim
   ```

## Development workflow

### Running the application

Always use `portage-ng-dev` from the project root:

```bash
# Interactive shell
./Source/Scripts/Wrapper/portage-ng-dev --mode standalone --shell

# Scripted session (preferred for debugging)
./Source/Scripts/Wrapper/portage-ng-dev --mode standalone --shell --timeout 60 <<'PL'
prover:test_stats(portage).
halt.
PL

# CI mode (non-interactive, exit codes for automation)
./Source/Scripts/Wrapper/portage-ng-dev --mode standalone --ci --pretend sys-apps/portage
```

### Exit codes (`--ci` mode)

| Code | Meaning |
|------|---------|
| 0 | Plan completed with no assumptions |
| 1 | Plan completed with prover cycle-break assumptions only |
| 2 | Plan completed with domain assumptions (e.g. missing deps) |

### Running tests

```bash
make test            # PLUnit tests (fast, no Portage tree needed)
make test-overlay    # Overlay regression tests (requires loaded overlay)
```

### Regression testing

After making resolver changes:

1. Ask the user to regenerate `.merge` files.
2. Run the compare analysis:

   ```bash
   python3 -u Reports/Scripts/compare-merge-emerge.py \
     --root /Volumes/Storage/Graph/portage \
     --full-lists \
     --out Reports/compare-$(date +%Y-%m-%d)-$(git rev-parse --short HEAD).json
   ```

3. Compare the new report against the previous baseline to detect regressions.
4. Ask the user for permission before committing.

## Naming conventions

- Source filenames: concatenated lowercase words (e.g. `knowledgebase.pl`), no
  hyphens or underscores. Exception: `portage-ng.pl`.
- Module names follow the same rule (e.g. `:- module(gentoo, [])`).
- Subdirectory names under `Source/` may use CamelCase (e.g. `Rules/`, `Config/`).

## Code style

See `Source/bonjour.pl` as the canonical reference for file layout, PlDoc
documentation, section headers, and spacing conventions.
