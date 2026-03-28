# test38 — Weak conditional [linux?]

**Category:** USE dep

This test case checks the handling of a weak USE dependency. The dependency `os[linux?]` means that 'os-1.0' will have the 'linux' flag enabled *only if* 'app-1.0' also has the 'linux' flag enabled. It does not force the flag to be enabled on 'app-1.0'.

**Expected:** - If 'app-1.0' is proven with USE="linux", the prover should enforce USE="linux" on 'os-1.0'.
- If 'app-1.0' is proven with USE="-linux", the 'linux' flag on 'os-1.0' is not constrained by this dependency and can be either on or off (defaulting to off).
The proof should be valid in both scenarios.

![test38](test38.svg)

**Output:** [emerge -vp](test38-emerge.log) | [portage-ng](test38-portage-ng.log)