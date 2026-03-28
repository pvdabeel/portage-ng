# test58 — PROVIDE-based virtual (XFAIL)

**Category:** Virtual

> **XFAIL** — expected to fail.

This test case checks PROVIDE-based virtual satisfaction. The 'linux-1.0' package
claims to provide 'virtualsdk', which is not available as a standalone ebuild. The
resolver must recognize that 'linux-1.0' satisfies the virtual dependency through
its PROVIDE declaration. This is a deprecated PMS mechanism but still appears in
the wild.

**Expected:** Currently expected to fail (XFAIL) until PROVIDE/provider resolution is
implemented. Eventually, proving web-1.0 should pull in linux-1.0 to satisfy the
test58/virtualsdk dependency.

![test58](test58.svg)

**Output:** [emerge -vp](test58-emerge.log) | [portage-ng](test58-portage-ng.log)