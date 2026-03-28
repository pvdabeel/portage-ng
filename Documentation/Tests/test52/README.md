# test52 — Multiple USE flags on shared dep

**Category:** USE merge

The prover will first prove os-1.0 through the liba path. This means os-1.0 will have 'threads' enabled. Later prover needs to enable 'hardened' through the libb path. The prover should be able to produce a proof with just one os install, for both 'threads' and 'hardeded'. This should also be reflected in the download for os-1.0

**Expected:** The prover should correctly identify the need for building os-1.0 only once with the two use flags.

![test52](test52.svg)

**Output:** [emerge -vp](emerge-test52.log) | [portage-ng](portage-ng-test52.log)