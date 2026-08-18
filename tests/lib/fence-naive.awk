# fence-naive.awk — the SUPERSEDED fence toggle, kept ONLY as a control. (E99-F131)
#
# ⚠️ DO NOT USE THIS TO SLICE ANYTHING. It is wrong, and it is here on purpose: it exposes
# the same `fence_delim(line)` interface as tests/lib/fence.awk, so one extraction program
# can be run against both and the difference measured. tests/test_change_size.sh R9d does
# exactly that — without a control, R9d would keep passing if fence.awk ever quietly
# degraded back to this rule, since a correct extraction and an accidentally-correct one
# look identical from the outside.
#
# What it gets wrong: everything except a column-0 run of exactly-or-more-than three
# BACKTICKS. It cannot see a tilde fence, an indented fence, or the difference between an
# opening run and a shorter run of the same character inside it — so it mis-tracks the block
# and a `#` line inside is read as a markdown heading. See fence.awk for the real rule.
#
# Spelled with `substr()` rather than the original `/^```/` pattern so that the ban in R9d
# (no suite may hand-roll a fence toggle) needs no exception for its own control.

function fence_delim(line) {
  if (substr(line, 1, 3) != "```") return 0
  fence = !fence
  return 1
}
