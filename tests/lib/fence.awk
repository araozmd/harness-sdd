# fence.awk — the CommonMark fenced-code-block rule, as an awk function. (E99-F131)
#
# THE ONE COPY. Every suite that slices a markdown section by heading loads this file and
# concatenates it in front of its own rules:
#
#     FENCE_AWK="$(cat "$SRC/tests/lib/fence.awk")"
#     awk "$FENCE_AWK"'
#       fence_delim($0) { if (keep) print; next }
#       !fence && /^#+ / { keep = (index($0, h) > 0); next }
#       keep
#     ' file
#
# (Command substitution captures the file verbatim and a parameter expansion is not
# re-scanned, so the backticks and `$0` below survive the double quotes intact.)
#
# Call `fence_delim($0)` as the FIRST rule of the program, once per line. It returns:
#   1  the line is a fence DELIMITER (opening or closing) — the caller decides whether to
#      print it, then must `next`, so the delimiter never reaches a heading pattern;
#   0  otherwise, having set the global `fence` to 1 for every line INSIDE a fenced block.
#      Guard every heading pattern with `!fence`.
#
# WHY A FUNCTION AND NOT `/^```/ { fence = !fence }`. That toggle is not the rule. Per
# CommonMark 0.31 §4.5 a fence:
#   * may be a run of BACKTICKS **or** TILDES (`~~~`);
#   * may be INDENTED 0-3 spaces (4+ is an indented code block, and never a fence);
#   * opens with a run of 3 OR MORE, and is closed only by a run of the SAME character that
#     is AT LEAST AS LONG — so a shorter run inside a ```` ```` ```` block is content;
#   * closes only on a delimiter with no info string after it;
#   * (backtick openers only) may not carry a backtick in the info string.
# Under any of those forms the naive toggle mis-tracks the block, a `#`/`##` line inside it
# is read as a heading, and the slice TRUNCATES (green, enforcing a prefix) or OVER-INCLUDES
# (a scope so wide the assertion cannot fail). That is the whole defect E99-F131 closes, so
# closing it for one delimiter spelling and not the others would be the same bug wearing a
# different hat. tests/test_change_size.sh R9d exercises each form.
#
# NOT MODELLED, deliberately: tab indentation (CommonMark expands tabs to 4-column stops, so
# a tab-indented fence is an indented code block, not a fence), and fences nested inside list
# items or block quotes. Neither occurs in the harness's own markdown; if one appears, extend
# this file — do not hand-roll a second toggle beside it.

function fence_delim(line,   ind, ch, run, tail) {
  ind = 0
  while (ind < 4 && substr(line, ind + 1, 1) == " ") ind++
  if (ind > 3) return 0                      # 4+ spaces: an indented code block, not a fence
  ch = substr(line, ind + 1, 1)
  if (ch != "`" && ch != "~") return 0
  run = 0
  while (substr(line, ind + run + 1, 1) == ch) run++
  if (run < 3) return 0
  tail = substr(line, ind + run + 1)
  if (fence) {
    # A closer must match the OPENER's character and be at least as long; anything shorter,
    # or of the other character, is ordinary content inside the block.
    if (ch != fence_char || run < fence_len) return 0
    if (tail ~ /[^ \t]/) return 0            # a closing delimiter carries no info string
    fence = 0
    return 1
  }
  if (ch == "`" && index(tail, "`") > 0) return 0
  fence = 1
  fence_char = ch
  fence_len = run
  return 1
}
