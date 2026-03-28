# test28 — Strong blocker !! (compile) + any-of

**Category:** Blocker

This test case is a variation of test26 where the strong blocker (!!) is in the
compile-time scope (DEPEND) rather than the runtime scope (RDEPEND). The 'app-1.0'
package strongly blocks 'windows-1.0' at compile time, while 'os-1.0' has an
any-of compile dependency that includes 'windows-1.0'.

**Expected:** The prover should produce a valid plan that avoids 'windows-1.0'. It should select
either 'linux-1.0' or 'bsd-1.0' to satisfy the any-of group on 'os-1.0', since
'windows-1.0' is strongly blocked by 'app-1.0' in the compile scope.

![test28](test28.svg)

**Output:** [emerge -vp](emerge-test28.log) | [portage-ng](portage-ng-test28.log)