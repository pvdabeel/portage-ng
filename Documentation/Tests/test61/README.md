# test61 — Mutual recursion with bracketed USE

**Category:** Cycle

This test case checks termination and cycle handling when bracketed USE
dependencies ([foo]) are present in a mutual recursion. The 'a' and 'b' packages
each require the other with a specific USE flag. The prover must ensure that the
build_with_use context does not grow unbounded as it traverses the cycle.

**Expected:** The solver should terminate quickly, either by cycle breaking or by producing a
finite plan. It must not spin or backtrack indefinitely due to accumulating USE
context.

![test61](test61.svg)

**Output:** [emerge -vp](emerge-test61.log) | [portage-ng](portage-ng-test61.log)