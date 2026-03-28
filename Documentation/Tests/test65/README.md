# test65 — build_with_use reinstall semantics

**Category:** Installed

This test case is a regression test for rules:installed_entry_satisfies_build_with_use/2.
It ensures that an installed VDB entry cannot be treated as satisfying a dependency
if incoming build_with_use requires a flag that the installed package was not built
with. The test uses an always-false flag requirement (__portage_ng_test_flag__)
against an arbitrary installed package.

**Expected:** The test validation checks that the rule correctly identifies unsatisfied
build_with_use requirements on installed packages. The prover should find that no
installed entry satisfies the synthetic flag requirement, and the rule should
produce non-empty conditions.

![test65](test65.svg)

**Output:** [emerge -vp](test65-emerge.log) | [portage-ng](test65-portage-ng.log)