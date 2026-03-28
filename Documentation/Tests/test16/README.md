# test16 — Explicit all-of group ( ) syntax

**Category:** Parser

This test case checks the parser's handling of explicit all-of group
parenthesization in dependency specifications. The 'web-1.0' package wraps two of
its runtime dependencies in an explicit all-of group: ( db-1.0 os-1.0 ). In PMS,
this is semantically equivalent to listing them flat (as in test01), but the parser
must correctly handle the parenthesized form without treating it as a choice group.

**Expected:** The prover should successfully resolve the dependencies and generate the same valid
proof as test01. The all-of group should be transparent to the resolver: app-1.0,
db-1.0, and os-1.0 should all appear in the plan in the correct order.

![test16](test16.svg)

**Output:** [emerge -vp](test16-emerge.log) | [portage-ng](test16-portage-ng.log)