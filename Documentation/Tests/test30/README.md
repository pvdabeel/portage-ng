# test30 — Weak blocker ! (compile) + any-of

**Category:** Blocker

This test case is a variation of test27 where the weak blocker (!) is in the
compile-time scope (DEPEND) rather than the runtime scope (RDEPEND). The 'app-1.0'
package weakly blocks 'windows-1.0' at compile time, while 'os-1.0' has an any-of
compile dependency that includes 'windows-1.0'.

**Expected:** The prover should produce a valid plan. The weak blocker is recorded as a domain
assumption. The any-of group resolution may or may not select 'windows-1.0',
depending on blocker handling strategy.

![test30](test30.svg)

**Output:** [emerge -vp](test30-emerge.log) | [portage-ng](test30-portage-ng.log)