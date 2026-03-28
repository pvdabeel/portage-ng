# test35 — Equality [linux=]

**Category:** USE dep

This test case checks the handling of conditional USE propagation. The dependency `os[linux=]` means that if 'app-1.0' is built with USE="linux", then 'os-1.0' must also be built with USE="linux". If 'app-1.0' is built with USE="-linux", then 'os-1.0' must be built with USE="-linux".

**Expected:** - If 'app-1.0' is proven with USE="linux", the prover should enforce USE="linux" on 'os-1.0'.
- If 'app-1.0' is proven with USE="-linux" (or it's disabled by default), the prover should enforce USE="-linux" on 'os-1.0'.
In both cases, the proof should be valid.

![test35](test35.svg)

**Output:** [emerge -vp](test35-emerge.log) | [portage-ng](test35-portage-ng.log)