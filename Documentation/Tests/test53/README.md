# test53 — USE merge + conditional extra dep

**Category:** USE merge

The prover will first prove os-1.0 through the liba path. This means os-1.0 will have 'threads' enabled. Later prover needs to enable 'hardened' through the libb path. The prover should be able to produce a proof with just one os install, for both 'threads' and 'hardeded'. This should also be reflected in the download for os-1.0. Introducing 'hardened' on the already proven os-1.0 should pull in a new dependency on libhardened-1.0

**Expected:** The prover should correctly identify the need for building os-1.0 only once with the two use flags, and the libhardened-1.0 dependency

![test53](test53.svg)

**Output:** [emerge -vp](emerge-test53.log) | [portage-ng](portage-ng-test53.log)