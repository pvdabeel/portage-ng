# test60 — Versioned soft blocker !<pkg-ver (XFAIL)

**Category:** Blocker

> **XFAIL** — expected to fail.

This test case checks the handling of versioned soft blockers (!<pkg-version). The
'app-1.0' package blocks any version of 'windows' less than 2.0. The any-of group
on 'os-1.0' offers both windows-1.0 and windows-2.0 as choices. The solver should
avoid windows-1.0 because it falls within the blocker's version range.

**Expected:** Currently expected to fail (XFAIL): the versioned blocker is handled via
assumptions rather than by steering the version choice. When fixed, the solver
should select windows-2.0 and avoid windows-1.0.

![test60](test60.svg)

**Output:** [emerge -vp](emerge-test60.log) | [portage-ng](portage-ng-test60.log)