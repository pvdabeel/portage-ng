# test01 — Simple dependency ordering

**Category:** Basic

This test case checks basic dependency resolution with both compile-time and
runtime dependencies. The prover must correctly order all four packages and
identify opportunities for parallel execution.

**Expected:** The prover should produce a valid plan installing all four packages. Packages with
no unsatisfied dependencies (os-1.0) should come first. Packages that share the
same set of resolved dependencies (app-1.0, db-1.0) can be grouped into a parallel
step. The final step installs web-1.0.

![test01](test01.svg)

**Output:** [emerge -vp](emerge-test01.log) | [portage-ng](portage-ng-test01.log)