# Policy: Target resolution

**Concern:** How does a user / set atom become a concrete ebuild action?

**PMS / Portage:** CLI atoms (`cat/pkg`, versioned atoms, `@sets`) resolve
to one or more package versions; emerge then plans install/run for that
selection. Sets expand before resolution.

**Literals:**

- `target(Q, Arg):run|uninstall?{Ctx}` (CLI `--fetchonly` / `-F` also prove `:run`)
- Expands to `Repo://Ebuild:Action?{Ctx}` (and optional `world/1` side effects)

**Owns:** `Rules/Resolving/target.pl`, `resolving.pl` TARGET section, `Preference/sets.pl`
(set expansion before prove).

**Invariants:**

- Unconstrained CN targets prefer **visible** candidates before unmasking.
- Explicit versions try candidates in standard order (user pin wins).
- CLI `--fetchonly` / `-F` prove `:run` then filter print/execute; they do
  not write `@world` even though the plan may contain `world:register`.
- `:uninstall` may unregister unless `--oneshot`.
- Set atoms (`@world`, `@security`, `@preserved-rebuild`, `@changed-deps`,
  …) expand to ordinary package atoms before target rules run
  (`sets:expand/2` for computed sets). File-backed / world members that
  are themselves `@name` references are expanded recursively (cycle or
  unknown name from inside a set is a hard error).

**Examples:** [test01](examples.md#test01), [test71](examples.md#test71),
[test78](examples.md#test78).  
**See also:** [Visibility](visibility.md), [Install](install.md).
