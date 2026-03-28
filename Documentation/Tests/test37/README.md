# test37 — Inverse equality [!linux=]

**Category:** USE dep

This test case checks the handling of an inverse conditional USE dependency. The dependency `os[!linux=]` means that the 'linux' flag on 'os-1.0' must be the inverse of the setting on 'app-1.0'.

**Expected:** - If 'app-1.0' is proven with USE="linux", the prover must enforce USE="-linux" on 'os-1.0'.
- If 'app-1.0' is proven with USE="-linux", the prover must enforce USE="linux" on 'os-1.0'.
The proof should be valid in both scenarios.

![test37](test37.svg)

**Output:** [emerge -vp](test37-emerge.log) | [portage-ng](test37-portage-ng.log)