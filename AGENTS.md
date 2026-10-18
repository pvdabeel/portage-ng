# AGENTS.md

General architecture, coding conventions, and the canonical run/test/regression
workflow live in `.cursorrules` and `CONTRIBUTING.md`. Read those first. This
file only records durable, non-obvious guidance for cloud agents.

## Cursor Cloud specific instructions

### Environment
- Runtime is **SWI-Prolog** (installed system-wide via `ppa:swi-prolog/devel`,
  `swipl` on `PATH`). It persists in the VM snapshot, so the update script does
  not reinstall it. `portage-ng` has no package-manager (npm/pip/uv)
  dependencies — SWI-Prolog plus the standard CLI tools (bash, git, python3)
  are all that is needed.
- The startup/update script recreates the two gitignored private config files
  from their templates (`Source/Config/Private/{api_key,passwords}.pl`). These
  are optional (config guards them with `exists_source/1` and falls back to
  empty values), so their absence is not fatal; recreating them just mirrors CI
  and enables LLM/server features.

### Sandbox scope (read this before running anything heavy)
Cloud agents **cannot** do full-tree Gentoo proving or regression. Two
independent limits stack:

1. **No Portage knowledge base on disk.** There is no Gentoo tree
   (`Repository/portage-git` is absent), and no checked-in
   `Knowledge/{kb,profile,preference}.{raw,qlf}`. Hostname resolves to
   `cursor`, so `Source/Config/default.pl` points the `portage` repo at a
   path that does not exist. Real `--pretend <category/package>` against
   `portage` finds no candidates.
2. **Not enough CPU for whole-tree resolver work anyway.** Even if a
   `kb.qlf` (+ `profile.qlf` + `preference.qlf`) snapshot were committed,
   workloads like `resolver:test(portage)`, `resolver:test_stats(portage)`,
   whole-tree `--graph`, and tinderbox-ng matrix runs need a powerful local
   machine (or `vm-linux.local`). Do **not** attempt them in the cloud VM.

Local-only / external (ask the user; do not run here):
- `--sync`, `--graph`
- `resolver:test(portage)`, `resolver:test_stats(portage)` (and other
  whole-tree harnesses)
- tinderbox-ng regression on `vm-linux.local` (see `.cursorrules`)

Note on a hypothetical committed KB: proving against cached facts would also
need `profile.qlf` (masks/keywords/USE) **and** `preference.qlf` (materialized
`/etc/portage` + profile preferences). That path is intentionally **not**
set up for cloud agents; use the overlay instead.

### What to run in the sandbox
Everything goes through `./Source/Application/Wrapper/portage-ng-dev` (never
raw `swipl`). The in-repo synthetic overlay (`Repository/Overlay`, ships its
own md5-cache) is the substitute for a real tree:

- Boot check: `--mode standalone --shell` then `halt.`
- PLUnit (fast, no tree): `make test`
- Overlay regression (full resolve+order+print, 80 cases):
  ```sh
  ./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell --timeout 900 <<'PL'
  loader:load_test_modules.
  ( catch(test:run(cases,batch),E,(print_message(error,E),fail)) -> halt(0) ; halt(1) ).
  PL
  ```
- Spot prove against the overlay (hello-world style):
  ```sh
  ./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell --timeout 120 <<'PL'
  test:ensure_overlay,
  Target = overlay://'test47/api-docs-1.0':run?{[]},
  pipeline:prove_plan_with_fallback([Target],Proof,Model,Plan,Triggers,_),
  printer:print([Target],Model,Proof,Plan,Triggers),
  halt.
  PL
  ```
- Small scripted queries via `--shell` + here-doc are fine; keep timeouts
  modest and avoid anything that walks the full `portage` repo.

### Building
- `make build` produces the standalone `portage-ng` binary (`make clean`
  removes it); day-to-day development uses the wrapper, not the binary.
