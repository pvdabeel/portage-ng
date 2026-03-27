# Contributing to portage-ng

## Getting started

1. **Clone the repository:**

   ```bash
   git clone <repo-url>
   cd portage-ng
   ```

2. **Prerequisites:**

   | Dependency | Required | Used for |
   |------------|----------|----------|
   | SWI-Prolog >= 9.3 | Yes | Runtime (development version recommended) |
   | Bash >= 5 | Yes | Shell completions, wrapper scripts |
   | Git | Yes | Version detection, worker snapshot sync |
   | curl | Yes | Distfile downloading (`download.pl`) |
   | OpenSSL CLI | Yes | Manifest hash verification (`mirror.pl`) |
   | Python 3 | Recommended | Hard timeout watchdog, report scripts (`Reports/Scripts/`) |
   | dns-sd | Optional | Bonjour/Zeroconf service discovery (distributed mode) |
   | ldd / otool | Optional | ELF linkage analysis (`linkage.pl`; otool on macOS, ldd on Linux) |

3. **Host configuration:** Copy the template to match your hostname:

   ```bash
   cp Source/Config/Template/example.pl "Source/Config/$(hostname).pl"
   ```

   Edit the new file to set your local Portage tree path, VDB location,
   and distfiles directory. See `Source/Config/default.pl` for reference.

4. **Set up shell aliases.** Add the following to your `~/.zshrc` or
   `~/.bash_profile`, adjusting the paths to match your checkout location:

   ```bash
   # Main alias (replace /path/to/prolog with your checkout directory)
   alias portage-ng-dev="swipl -O \
     --stack-limit=256G --table-space=256G --shared-table-space=256G \
     -f /path/to/prolog/portage-ng.pl \
     -p portage=/path/to/prolog \
     -Dverbose_autoload=false \
     -g main --"

   # Debug alias (enables debug-level tracing)
   alias portage-ng-debug="swipl -O \
     --stack-limit=256G --table-space=256G --shared-table-space=256G \
     -f /path/to/prolog/portage-ng.pl \
     -p portage=/path/to/prolog \
     -Dverbose_autoload=false -Ddebug=true \
     -g main --"
   ```

   Then reload your shell (`source ~/.zshrc`) or open a new terminal.

5. **Verify** by running a quick pretend:

   ```bash
   portage-ng-dev --mode standalone --pretend app-editors/neovim
   ```

> **Note:** The repository also ships a
> `./Source/Scripts/Wrapper/portage-ng-dev` script for CI and automated
> tooling. For day-to-day development the shell alias above is preferred
> because it uses your local SWI-Prolog build and avoids hard-coded paths.

## Development workflow

### Running the application

Always use `portage-ng-dev` (never raw `swipl` with ad-hoc goals):

```bash
# Interactive shell
portage-ng-dev --mode standalone --shell

# Scripted session (preferred for debugging)
portage-ng-dev --mode standalone --shell --timeout 60 <<'PL'
prover:test_stats(portage).
halt.
PL

# CI mode (non-interactive, exit codes for automation)
portage-ng-dev --mode standalone --ci --pretend sys-apps/portage
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
