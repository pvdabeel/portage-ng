# test26 — Strong blocker !! (runtime) + any-of

**Category:** Blocker

This test case checks the prover's handling of a strong blocker (!!). The 'app-1.0'
package has a strong runtime blocker against 'windows-1.0'. At the same time,
'os-1.0' has an any-of compile dependency that includes 'windows-1.0' as a choice.
The prover must recognize that selecting 'windows-1.0' for the any-of group would
conflict with the strong blocker on 'app-1.0', and should steer the selection
toward 'linux-1.0' or 'bsd-1.0' instead.

**Expected:** The prover should produce a valid plan that avoids 'windows-1.0'. It should select
either 'linux-1.0' or 'bsd-1.0' to satisfy the any-of group on 'os-1.0', since
'windows-1.0' is strongly blocked by 'app-1.0' in the runtime scope.

![test26](test26.svg)

**Output:** [emerge -vp](test26-emerge.log) | [portage-ng](test26-portage-ng.log)