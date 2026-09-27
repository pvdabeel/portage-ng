# Policy by example

Curated overlay specimens for learning Gentoo domain policy.
Each entry is a **story** (what policy is being exercised), not a full
regression matrix — for all 80 cases see
[Documentation/Tests/README.md](../../Tests/README.md).

Run a single scenario after loading the overlay (see
[Chapter 26](../26-doc-testing.md)):

```bash
make test-overlay
```

Or open the per-test README under `Documentation/Tests/testNN/`.


## Suggested reading order

Work top-to-bottom the first time; afterwards jump via [cards](README.md)
or the [map](map.md).

| Step | Test | Policy card | One-line lesson |
| ---: | :--- | :--- | :--- |
| 1 | [test01](#test01) | [Install](install.md) / [Run](run.md) | DEPEND + RDEPEND become `:install` / `:run` obligations |
| 2 | [test02](#test02) | [Dependency](dependency.md) | Newest eligible version wins by default |
| 3 | [test12](#test12) | [Visibility](visibility.md) | Keyword reject → positive assumption |
| 4 | [test09](#test09) | [Assumptions](assumption.md) | Missing package → negative assumption |
| 5 | [test13](#test13) | [Dependency](dependency.md) | `=` pin selects exactly one version |
| 6 | [test55](#test55) | [Dependency](dependency.md) | Constraints intersect to one domain |
| 7 | [test14](#test14) | [USE](use.md) | USE-conditional deps gate the body |
| 8 | [test33](#test33) | [USE](use.md) | Bracketed `[flag]` becomes `build_with_use` |
| 9 | [test52](#test52) | [USE](use.md) | Shared child merges USE from two parents |
| 10 | [test40](#test40) | [REQUIRED_USE](requireduse.md) | Package-local `\|\|` USE constraint |
| 11 | [test49](#test49) | [REQUIRED_USE](requireduse.md) | Soft `(+)` loses to hard REQUIRED_USE |
| 12 | [test20](#test20) | [Choice](choice.md) | `\|\|` picks one admitted arm |
| 13 | [test60](#test60) | [Choice](choice.md) / [Blocker](blocker.md) | Ranking + soft blocker prefer newer arm |
| 14 | [test26](#test26) | [Blocker](blocker.md) | Hard `!!` forbids co-install |
| 15 | [test41](#test41) | [Slots](slot.md) | Explicit `:slot` filters candidates |
| 16 | [test48](#test48) | [Slots](slot.md) | Same slot, two versions → conflict |
| 17 | [test03](#test03) | [Cycle](cycle.md) | Self-dep → benign prover cycle-break |
| 18 | [test66](#test66) | [Run](run.md) | PDEPEND resolved in the same prove pass |
| 19 | [test74](#test74) | [Install](install.md) | Constraint can force a downgrade |
| 20 | [test76](#test76) | [USE](use.md) / [Install](install.md) | Wrong installed USE → rebuild |


## Specimens

### test01

**Cards:** [Install](install.md), [Run](run.md), [Target](target.md)  
**Story:** Four-package DAG with compile- and runtime edges; plan orders
leaves first and may parallelize independent installs.  
**Read:** [Documentation/Tests/test01/README.md](../../Tests/test01/README.md)

### test02

**Cards:** [Dependency](dependency.md)  
**Story:** Two versions available; default selection is the newest
eligible.  
**Read:** [test02/README.md](../../Tests/test02/README.md)

### test03

**Cards:** [Cycle](cycle.md)  
**Story:** Direct self-DEPEND; proof completes with a benign
`assumed(rule(…:install))` cycle-break (exit 1 if alone).  
**Read:** [test03/README.md](../../Tests/test03/README.md)

### test05

**Cards:** [Cycle](cycle.md)  
**Story:** Self-dep on both compile and runtime legs; the compile leg
needs a cycle-break assumption on `os:install`, the runtime leg
resolves via the install/run action split.  
**Read:** [test05/README.md](../../Tests/test05/README.md)

### test06

**Cards:** [Cycle](cycle.md)  
**Story:** Indirect compile-time cycle; dissolved by the install/run
action split — no cycle-break assumption needed (unlike self-dep test03).  
**Read:** [test06/README.md](../../Tests/test06/README.md)

### test09

**Cards:** [Assumptions](assumption.md), [Dependency](dependency.md)  
**Story:** Non-existent compile-time dep → **negative**
`non_existent` / missing dependency assumption.  
**Read:** [test09/README.md](../../Tests/test09/README.md)

### test10

**Cards:** [Run](run.md), [Assumptions](assumption.md)  
**Story:** Same as test09 but in RDEPEND / `:run` scope.  
**Read:** [test10/README.md](../../Tests/test10/README.md)

### test12

**Cards:** [Visibility](visibility.md), [Assumptions](assumption.md)  
**Story:** Unstable keyword; acceptance is a **positive** domain
assumption with `suggestion(accept_keyword, …)`.  
**Read:** [test12/README.md](../../Tests/test12/README.md)

### test13

**Cards:** [Dependency](dependency.md)  
**Story:** `=cat/pkg-ver` pin; only that version is admitted.  
**Read:** [test13/README.md](../../Tests/test13/README.md)

### test14

**Cards:** [USE](use.md)  
**Story:** `lib? ( … )` omitted when `lib` is disabled.  
**Read:** [test14/README.md](../../Tests/test14/README.md)

### test17

**Cards:** [Choice](choice.md)  
**Story:** `^^` exactly-one-of among OS flavours.  
**Read:** [test17/README.md](../../Tests/test17/README.md)

### test20

**Cards:** [Choice](choice.md)  
**Story:** Classic `|| ( … )` any-of at compile time.  
**Read:** [test20/README.md](../../Tests/test20/README.md)

### test23

**Cards:** [Choice](choice.md)  
**Story:** `??` at-most-one-of cardinality.  
**Read:** [test23/README.md](../../Tests/test23/README.md)

### test26

**Cards:** [Blocker](blocker.md)  
**Story:** Strong `!!` blocker interacting with an any-of group.  
**Read:** [test26/README.md](../../Tests/test26/README.md)

### test27

**Cards:** [Blocker](blocker.md), [Assumptions](assumption.md)  
**Story:** Weak `!` blocker; may record a positive blocker assumption.  
**Read:** [test27/README.md](../../Tests/test27/README.md)

### test33

**Cards:** [USE](use.md)  
**Story:** Positive bracketed USE dep `[linux]` forces child USE.  
**Read:** [test33/README.md](../../Tests/test33/README.md)

### test35

**Cards:** [USE](use.md)  
**Story:** Equality USE dep `[linux=]` ties parent/child flag state.  
**Read:** [test35/README.md](../../Tests/test35/README.md)

### test40

**Cards:** [REQUIRED_USE](requireduse.md)  
**Story:** Standalone package `REQUIRED_USE="|| ( linux darwin )"`.  
**Read:** [test40/README.md](../../Tests/test40/README.md)

### test41

**Cards:** [Slots](slot.md)  
**Story:** Explicit slot operator `:1`.  
**Read:** [test41/README.md](../../Tests/test41/README.md)

### test42

**Cards:** [Slots](slot.md)  
**Story:** Wildcard `:*` admits any slot (newest preferred).  
**Read:** [test42/README.md](../../Tests/test42/README.md)

### test43

**Cards:** [Slots](slot.md)  
**Story:** Slot operator `:=` (equality / rebuild binding).  
**Read:** [test43/README.md](../../Tests/test43/README.md)

### test47

**Cards:** [Cycle](cycle.md)  
**Story:** Three-way dependency cycle; resolved without any break —
the install/run action split dissolves it.  
**Read:** [test47/README.md](../../Tests/test47/README.md)

### test48

**Cards:** [Slots](slot.md), [Assumptions](assumption.md)  
**Story:** Same slot, incompatible versions → slot conflict (negative).  
**Read:** [test48/README.md](../../Tests/test48/README.md)

### test49

**Cards:** [REQUIRED_USE](requireduse.md), [USE](use.md)  
**Story:** Parent soft `[feature_z(+)]` vs child `REQUIRED_USE="!feature_z"`.  
**Read:** [test49/README.md](../../Tests/test49/README.md)

### test50

**Cards:** [Install](install.md), [Run](run.md)  
**Story:** Compile dep’s RDEPEND must still appear in the plan.  
**Read:** [test50/README.md](../../Tests/test50/README.md)

### test51

**Cards:** [Assumptions](assumption.md), [REQUIRED_USE](requireduse.md)  
**Story:** USE dep vs REQUIRED_USE contradiction (negative / blocking).  
**Read:** [test51/README.md](../../Tests/test51/README.md)

### test52

**Cards:** [USE](use.md)  
**Story:** Two parents force different flags on one `os`; single install
with merged USE.  
**Read:** [test52/README.md](../../Tests/test52/README.md)

### test55

**Cards:** [Dependency](dependency.md)  
**Story:** Direct `>3` and `<6` intersect; one version selected.  
**Read:** [test55/README.md](../../Tests/test55/README.md)

### test59

**Cards:** [Choice](choice.md)  
**Story:** Regression lock for `||` arm selection vs emerge.  
**Read:** [test59/README.md](../../Tests/test59/README.md)

### test60

**Cards:** [Choice](choice.md), [Blocker](blocker.md)  
**Story:** `!<windows-2.0` + `||` → prefer `windows-2.0` (newest admitted).  
**Read:** [test60/README.md](../../Tests/test60/README.md)

### test61

**Cards:** [Cycle](cycle.md), [USE](use.md)  
**Story:** Mutual recursion with bracketed USE must terminate.  
**Read:** [test61/README.md](../../Tests/test61/README.md)

### test63

**Cards:** [REQUIRED_USE](requireduse.md)  
**Story:** OpenMPI-style REQUIRED_USE loop; must not timeout.  
**Read:** [test63/README.md](../../Tests/test63/README.md)

### test65

**Cards:** [Install](install.md), [USE](use.md)  
**Story:** `build_with_use` reinstall / update semantics vs VDB.  
**Read:** [test65/README.md](../../Tests/test65/README.md)

### test66

**Cards:** [Run](run.md)  
**Story:** Transitive PDEPEND resolved in-prove (always enabled).  
**Read:** [test66/README.md](../../Tests/test66/README.md)

### test67

**Cards:** [Install](install.md)  
**Story:** BDEPEND is build-only; distinct from DEPEND in obligations.  
**Read:** [test67/README.md](../../Tests/test67/README.md)

### test68

**Cards:** [Slots](slot.md)  
**Story:** Same CN, different slots may co-install.  
**Read:** [test68/README.md](../../Tests/test68/README.md)

### test69

**Cards:** [Dependency](dependency.md)  
**Story:** Operator `>=`.  
**Read:** [test69/README.md](../../Tests/test69/README.md)

### test70

**Cards:** [Dependency](dependency.md)  
**Story:** Operator `~` (revision match).  
**Read:** [test70/README.md](../../Tests/test70/README.md)

### test71

**Cards:** [Target](target.md)  
**Story:** `--fetchonly` is a print/execute filter on the `:run` plan.  
**Read:** [test71/README.md](../../Tests/test71/README.md)

### test74

**Cards:** [Install](install.md), [Dependency](dependency.md)  
**Story:** Installed newer version; atom forces downgrade.  
**Read:** [test74/README.md](../../Tests/test74/README.md)

### test76

**Cards:** [USE](use.md), [Install](install.md)  
**Story:** Installed with wrong USE → rebuild / newuse.  
**Read:** [test76/README.md](../../Tests/test76/README.md)

### test78

**Cards:** [Target](target.md)  
**Story:** `--onlydeps` / skip target, install deps only.  
**Read:** [test78/README.md](../../Tests/test78/README.md)

### test79

**Cards:** [Run](run.md), [Cycle](cycle.md)  
**Story:** PDEPEND cycle A↔B; resolved via the proof-obligation hook with
no assumptions — PDEPEND is never disabled to avoid it.  
**Read:** [test79/README.md](../../Tests/test79/README.md)

### test80

**Cards:** [Dependency](dependency.md)  
**Story:** Operator `<=`.  
**Read:** [test80/README.md](../../Tests/test80/README.md)


## PLUnit companions

Overlay stories cover end-to-end policy. For isolated primitives, prefer
PLUnit under `Source/Test/Unit/`:

| Area | Where to look |
| :--- | :--- |
| Version parse / PMS order | `begin_tests` version / compare groups |
| Version domains / meet | domain-related tests + [Chapter 10](../10-doc-version-domains.md) |
| EAPI / md5-cache extract | `md5cache_validate/0` |
| GLSA match / `@security` | `begin_tests(glsa)` |

These are **not** substitutes for the overlay curriculum; they back the
atoms the cards mention.
