# test39 — Negative weak [-linux?]

**Category:** USE dep

This test case checks the handling of a negative weak USE dependency. The dependency `os[-linux?]` means that 'os-1.0' will have the 'linux' flag disabled *only if* 'app-1.0' also has the 'linux' flag disabled.

**Expected:** - If 'app-1.0' is proven with USE="-linux", the prover should enforce USE="-linux" on 'os-1.0'.
- If 'app-1.0' is proven with USE="linux", the 'linux' flag on 'os-1.0' is not constrained by this dependency.
The proof should be valid in both scenarios.

![test39](test39.svg)

**Output:** [emerge -vp](emerge-test39.log) | [portage-ng](portage-ng-test39.log)