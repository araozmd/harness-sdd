#!/bin/sh
set -eu
. "$(dirname "$0")/lib/umbrella/common.sh"
. "$SRC/tests/lib/umbrella/audit.sh"

# ── R1/R2/R3/R4: an unlanded cascade is audited, named, counted, and exits 3 ────────────
# R1_audit_covers_all_targets / R2_unlanded_exits_nonzero / R3_unlanded_code_is_distinct /
# R4_summary_names_and_counts
mk_umb "$AU/u1" child-a child-b
cascade "$AU/u1"
[ "$AU_RC" = "3" ] \
  || fail "R2/R3: an unlanded cascade exited $AU_RC, want 3 (distinct from the generic failure code 1)"
printf '%s' "$AU_OUT" | grep -q "landing audit" || fail "R1: no landing audit ran: $AU_OUT"
for _c in child-a child-b; do
  printf '%s' "$AU_OUT" | grep -qE "unlanded +$_c +[0-9]+ harness-owned path" \
    || fail "R4: the summary does not name $_c with a drifted-path count: $AU_OUT"
done
pass "an unlanded cascade names every child with a count and exits 3 (R1-R4) [R1_audit_covers_all_targets/R2_unlanded_exits_nonzero/R3_unlanded_code_is_distinct/R4_summary_names_and_counts]"

# ── R6: committing the harness makes the same cascade pass ─────────────────────────────
# R6_all_landed_exits_zero — paired with R2 above ON THE SAME FIXTURE, so "exit 0" cannot be
# reached by an audit that simply never runs.
land "$AU/u1/child-a"; land "$AU/u1/child-b"
cascade "$AU/u1"
[ "$AU_RC" = "0" ] || fail "R6: a fully landed cascade exited $AU_RC, want 0: $AU_OUT"
# The confirming line states what was ESTABLISHED. The default umbrella root is non-git, so
# it is unverifiable and the honest form is "N of M verified committed, K not verifiable" —
# "every target committed" is reserved for a cascade where every target really was checked.
# Asserting the generic "cascade complete" plus the per-child `landed` rows below keeps this
# case about the verdict rather than about which of the two accurate wordings applies.
printf '%s' "$AU_OUT" | grep -q "cascade complete" \
  || fail "R6: no confirming line on a fully landed cascade: $AU_OUT"
printf '%s' "$AU_OUT" | grep -qE "verified committed|every target committed" \
  || fail "R6: the confirming line does not state what was verified: $AU_OUT"
printf '%s' "$AU_OUT" | grep -qE "landed +child-a" \
  || fail "R6: child-a not reported as landed: $AU_OUT"
pass "a fully landed cascade prints the confirming line and exits 0 (R6) [R6_all_landed_exits_zero]"

# ── R5: a non-git target is reported, never counted as unlanded ─────────────────────────
# R5_non_git_reported_not_failed — the umbrella ROOT is non-git by default, which is exactly
# this case. Control: a git child in the SAME cascade is still audited and still fails, so a
# pass here cannot come from an audit that skips everything.
mk_umb "$AU/u2" child-c
cascade "$AU/u2"
printf '%s' "$AU_OUT" | grep -qE "no git +\(coordinator\)" \
  || fail "R5: the non-git umbrella root was not reported as 'no git': $AU_OUT"
[ "$AU_RC" = "3" ] || fail "R5 control: the unlanded git child did not fail the cascade (rc=$AU_RC)"
land "$AU/u2/child-c"
cascade "$AU/u2"
[ "$AU_RC" = "0" ] \
  || fail "R5: the non-git coordinator was counted as unlanded — a non-git target cannot be unlanded (rc=$AU_RC): $AU_OUT"
pass "a non-git target is reported and never counted as unlanded (R5) [R5_non_git_reported_not_failed]"

# ── R7: --dry-run writes nothing and never audits ───────────────────────────────────────
# R7_dry_run_skips_audit — control: the same umbrella WITHOUT --dry-run does audit and exits 3.
mk_umb "$AU/u3" child-d
cascade "$AU/u3" --dry-run
[ "$AU_RC" = "0" ] || fail "R7: --dry-run exited $AU_RC, want 0: $AU_OUT"
printf '%s' "$AU_OUT" | grep -q "landing audit" \
  && fail "R7: --dry-run ran the landing audit: $AU_OUT"
[ -d "$AU/u3/child-d/.harness" ] \
  && fail "R7: --dry-run wrote .harness/ into a child"
cascade "$AU/u3"
[ "$AU_RC" = "3" ] \
  || fail "R7 control: the same umbrella without --dry-run did not audit and fail (rc=$AU_RC)"
pass "--dry-run writes nothing and skips the audit (R7) [R7_dry_run_skips_audit]"

# ── R9: the audit never modifies a target's git state ───────────────────────────────────
# R9_audit_is_read_only — HEAD, the full unfiltered porcelain, and the index mtime must all
# be unchanged. Asserting "no new commit" alone would pass on an audit that staged without
# committing, which is exactly the accident this epic exists to prevent.
mk_umb "$AU/u4" child-e
cascade "$AU/u4"                       # first run installs (and reports unlanded)
land "$AU/u4/child-e"                  # commit it: the write under test is the stat-cache
git -C "$AU/u4/child-e" status --porcelain >/dev/null   # settle the cache before measuring
_head_before="$(git -C "$AU/u4/child-e" rev-parse HEAD)"
_status_before="$(GIT_OPTIONAL_LOCKS=0 git -C "$AU/u4/child-e" status --porcelain)"
# BYTE-COMPARE the index, not `ls -l` it. mtime via ls has one-second resolution, and the
# write this guards against — git refreshing its stat cache after install_one recopies the
# body — completes well inside a second, so the original `ls -l` comparison could not see it
# and did not. Copy the file and `cmp`: exact, portable, no stat(1) format differences.
cp "$AU/u4/child-e/.git/index" "$AU/u4/index.before" 2>/dev/null || true
cascade "$AU/u4"                       # second run: install is idempotent, audit runs again
# The index comparison MUST come first, before any other git command in this block. A plain
# `git status` refreshes the stat cache and rewrites .git/index itself — so verifying with it
# first would destroy the very evidence being checked. (The first draft did exactly that and
# reported a violation that was its own measurement.) Every later probe here is read-only or
# runs under GIT_OPTIONAL_LOCKS=0.
cmp -s "$AU/u4/index.before" "$AU/u4/child-e/.git/index" \
  || fail "R9: the audit rewrote the target's git index (byte-compare) — needs GIT_OPTIONAL_LOCKS=0"
[ "$(git -C "$AU/u4/child-e" rev-parse HEAD)" = "$_head_before" ] \
  || fail "R9: the audit created a commit in the target"
[ "$(GIT_OPTIONAL_LOCKS=0 git -C "$AU/u4/child-e" status --porcelain)" = "$_status_before" ] \
  || fail "R9: the audit changed the target's working tree or index"
pass "the audit never modifies a target's git state (R9) [R9_audit_is_read_only]"

# ── R2: an ADDED body file is caught even when git is configured to hide untracked ─────
# R2_added_file_caught_under_hidden_untracked
# An upgrade that ADDS a harness file leaves it untracked, and `status.showUntrackedFiles=no`
# in a repo or global gitconfig suppresses untracked files entirely — so without an explicit
# -uall the audit reports a fully committed target while an unlanded file sits in it. That is
# the same silent false-clean the whole epic exists to end, and the generic "fresh cascade is
# unlanded" cases cannot detect it (there, `?? .harness/` shows either way).
mk_umb "$AU/u5" child-f
cascade "$AU/u5"
land "$AU/u5/child-f"
git -C "$AU/u5/child-f" config status.showUntrackedFiles no
# The added file goes in `.claude/commands/`, NOT `.harness/agents/`: install_one PRUNES
# unknown files from the body directories, so a stray file there does not survive the
# re-install this case performs — the fixture would silently stop reproducing anything. The
# root generated-glue dirs are not pruned, and are equally harness-owned.
printf '# added by an upgrade, never committed\n' > "$AU/u5/child-f/.claude/commands/added-command.md"
# Preconditions: the target is otherwise clean, and the added file really is invisible
# without -uall — otherwise this case cannot discriminate.
[ -z "$(git -C "$AU/u5/child-f" status --porcelain -- .claude/)" ] \
  || fail "R2-uall: fixture precondition broken — showUntrackedFiles=no did not hide the added file"
[ -n "$(git -C "$AU/u5/child-f" status --porcelain -uall -- .claude/)" ] \
  || fail "R2-uall: fixture precondition broken — even -uall does not see the added file"
cascade "$AU/u5"
[ "$AU_RC" = "3" ] \
  || fail "R2-uall: an ADDED, uncommitted body file was hidden by status.showUntrackedFiles=no — the audit needs -uall (rc=$AU_RC): $AU_OUT"
pass "an added body file is caught under status.showUntrackedFiles=no (R2) [R2_added_file_caught_under_hidden_untracked]"


# ── R2: ANY ignored owned subtree must not be reported as landed ───────────────────────
# R2_ignored_owned_subtree_is_not_landed
# Three narrower probes shipped and each missed a shape: `check-ignore .harness` missed
# `.harness/tools/`, and witness-file sampling then missed `.harness/docs/` and
# `.claude/commands/` (no witness lived in them). Each fix was a narrower sample that invited
# the next gap, so the probe was inverted: git's COMPLETE ignored set over the owned
# pathspecs, minus the harness's own deliberate local-only list.
#
# This case is therefore a MATRIX over ignore shapes rather than one fixture. A sampling
# probe passes for whichever shapes it happens to cover and fails the rest — which is exactly
# how the previous two fixes looked green.
_shape_n=0
for _ign in '.harness/' '.harness/tools/' '.harness/docs/' '.claude/commands/'; do
  _shape_n=$((_shape_n + 1))
  _u="$AU/shape$_shape_n"
  mk_umb "$_u" child-s
  printf '%s\n' "$_ign" > "$_u/child-s/.gitignore"
  git -C "$_u/child-s" add -A && git -C "$_u/child-s" commit -q -m "ignore $_ign"
  cascade "$_u"
  land "$_u/child-s"                     # commit everything git will accept
  # Precondition: the ignore really does hide installed files from the index.
  [ "$(git -C "$_u/child-s" ls-files -- "$_ign" 2>/dev/null | wc -l | tr -d ' ')" = "0" ] \
    || fail "R2-shapes: fixture precondition broken — files under '$_ign' are tracked"
  cascade "$_u"
  printf '%s' "$AU_OUT" | grep -qE "landed +child-s" \
    && fail "R2-shapes: FALSE CLEAN — '$_ign' ignored, yet reported landed: $AU_OUT"
  printf '%s' "$AU_OUT" | grep -qE "no vcs +child-s" \
    || fail "R2-shapes: '$_ign' ignored but not reported unverifiable: $AU_OUT"
done
pass "every ignored owned subtree shape is unverifiable, never landed (R2) [R2_ignored_owned_subtree_is_not_landed]"
# Control 1: a HEALTHY target must still read `landed`. The harness seeds its own ignores
# (`__pycache__/`, `telemetry.jsonl`), so a probe that merely counted ignored paths would
# call every healthy target unverifiable and never fail a real cascade again.
mk_umb "$AU/healthy" child-t
cascade "$AU/healthy"
land "$AU/healthy/child-t"
cascade "$AU/healthy"
printf '%s' "$AU_OUT" | grep -qE "landed +child-t" \
  || fail "R2-shapes control: a HEALTHY landed target was not reported landed — the local-only subtraction is missing: $AU_OUT"
[ "$AU_RC" = "0" ] || fail "R2-shapes control: a healthy landed cascade exited $AU_RC, want 0"
pass "…while a healthy target is still landed (R2 control) [R2_ignored_owned_subtree_is_not_landed]"

# ── R2: the harness-seeded ignored progress/ run dir (and workers.json) is subtracted ───
# R2_seeded_progress_run_dir_is_subtracted
# The installer seeds `.harness/progress/feedback/` (E32-F03) and its own `.harness/.gitignore`
# ignores `progress/*/`, so every landed target's audit sees one ignored owned dir. Without a
# `progress/` entry in the local-only subtraction the audit reports EVERY child unverifiable
# and exits 3 — PR #227 sat two commits red behind a green Codex trend this way. The empty-dir
# healthy control above did not catch it on its own, so pin the RUNTIME shape: a NON-EMPTY
# feedback dir holding F02's `.session-id`, which is exactly what a real target has.
mk_umb "$AU/progseed" child-z
cascade "$AU/progseed"
mkdir -p "$AU/progseed/child-z/.harness/progress/feedback"
printf '20260101T000000Z\n' > "$AU/progseed/child-z/.harness/progress/feedback/.session-id"
land "$AU/progseed/child-z"
# Preconditions: the dir really is ignored, and git really reports it as an ignored DIRECTORY
# (the shape the subtraction matches), not as the file inside it.
git -C "$AU/progseed/child-z" check-ignore -q .harness/progress/feedback/ \
  || fail "R2-progseed: fixture precondition broken — progress/feedback is not ignored"
git -C "$AU/progseed/child-z" status --porcelain -z -uall --ignored=matching -- .harness/ \
  | tr '\0' '\n' | grep -qxF '!! .harness/progress/feedback/' \
  || fail "R2-progseed: fixture precondition broken — git does not report the ignored progress dir as a dir"
cascade "$AU/progseed"
printf '%s' "$AU_OUT" | grep -qE "landed +child-z" \
  || fail "R2-progseed: a landed target whose only ignored owned path is the harness-seeded progress/feedback/ dir was NOT reported landed — emit_local_only lacks the progress/ entry: $AU_OUT"
[ "$AU_RC" = "0" ] || fail "R2-progseed: the fully landed cascade exited $AU_RC, want 0"
pass "the harness-seeded ignored progress/ run dir is subtracted, so a landed target stays landed (R2) [R2_seeded_progress_run_dir_is_subtracted]"

# The subtraction is consumed as a `|`-joined ERE alternation by `grep -Ev`
# (harness-install.sh:8982), so build THAT string and drive it over the shapes git emits AND
# the loose files the SOURCE layout tracks. Two-sided on purpose: a `progress/` pattern that
# matches no ignored path leaves the regression open, while a bare `(^|/)progress/` would also
# subtract tracked-layout loose files and can turn a real drift into a false clean.
_lo_alt="$(sh "$SRC/tools/harness-owned-paths.sh" local-only "$AU/healthy/child-t/.harness" \
  | tr '\n' '|' | sed 's/|$//')"
[ -n "$_lo_alt" ] || fail "R2-localonly: emit_local_only printed nothing"
for _lo_p in '.harness/progress/feedback/' '.harness/progress/run-9/' '.harness/workers.json'; do
  printf '%s\n' "$_lo_p" | grep -qE "$_lo_alt" \
    || fail "R2-localonly: a harness-seeded ignored path is NOT in the local-only subtraction: $_lo_p"
done
for _lo_p in 'progress/history.md' 'progress/lessons.md' 'progress/README.md' 'progress/inbox/E04-F01.md'; do
  if printf '%s\n' "$_lo_p" | grep -qE "$_lo_alt"; then
    fail "R2-localonly: a TRACKED-style loose progress file matches the local-only subtraction (the progress/ pattern must stay directory-only): $_lo_p"
  fi
done
pass "emit_local_only subtracts harness-seeded progress/ dirs and workers.json while never matching the tracked-layout loose progress files (R2) [R2_seeded_progress_run_dir_is_subtracted]"

# Control 2: a fresh, un-ignored body is UNLANDED, not unverifiable — a probe keyed on
# tracked-ness rather than ignored-ness passes the matrix above and silently exempts every
# fresh cascade.
mk_umb "$AU/u7" child-h
cascade "$AU/u7"
printf '%s' "$AU_OUT" | grep -qE "unlanded +child-h" \
  || fail "R2-shapes control: a fresh untracked (not ignored) body was not reported unlanded: $AU_OUT"
[ "$AU_RC" = "3" ] || fail "R2-shapes control: a fresh cascade did not exit 3 (rc=$AU_RC)"
pass "…and a fresh un-ignored body is still unlanded (R2 control) [R2_ignored_owned_subtree_is_not_landed]"

# ── R2: a CONFIGURED telemetry log override must not make a target unverifiable ────────
# R2_configured_telemetry_override_is_subtracted
# `telemetry.log` is configurable, and install_one adds a relative override to
# `.harness/.gitignore` itself. A subtraction list carrying only the hard-coded defaults
# therefore sees a legitimately-ignored file it does not recognise and reports the target
# unverifiable FOREVER — the audit never runs there again. Fails safe (under-claims rather
# than over-claims) but silently exempts the target. Reported as P2 on PR #103 round 4.
mk_umb "$AU/tlog" child-u
cascade "$AU/tlog"
python3 - "$AU/tlog/child-u/.harness/harness.config.yaml" <<'PYCFG' \
  || fail "R2-tlog: could not rewrite telemetry.log in the fixture config"
import sys
p = sys.argv[1]
s = open(p).read()
# ASSERT the anchor. A silent no-op here leaves the default config in place, the case then
# tests nothing, and it passes — which is exactly what happened while writing this suite.
assert "log: telemetry.jsonl" in s, "telemetry.log anchor not found in " + p
open(p, "w").write(s.replace("log: telemetry.jsonl", "log: custom/my.jsonl", 1))
PYCFG
cascade "$AU/tlog"                       # re-run so install_one seeds the override ignore
mkdir -p "$AU/tlog/child-u/.harness/custom"
printf '{}\n' > "$AU/tlog/child-u/.harness/custom/my.jsonl"
land "$AU/tlog/child-u"
# Preconditions: the override really is ignored, and it really is the configured value —
# otherwise this case cannot distinguish the fix from the fixed-list version.
grep -q 'custom/my.jsonl' "$AU/tlog/child-u/.harness/.gitignore" \
  || fail "R2-tlog: fixture precondition broken — install_one did not ignore the configured override"
git -C "$AU/tlog/child-u" check-ignore -q .harness/custom/my.jsonl \
  || fail "R2-tlog: fixture precondition broken — the override is not actually ignored"
cascade "$AU/tlog"
printf '%s' "$AU_OUT" | grep -qE "no vcs +child-u" \
  && fail "R2-tlog: a CONFIGURED telemetry override made the target unverifiable — the subtraction must read telemetry.log: $AU_OUT"
printf '%s' "$AU_OUT" | grep -qE "landed +child-u" \
  || fail "R2-tlog: a fully landed target with a telemetry override was not reported landed: $AU_OUT"
pass "a configured telemetry.log override is subtracted, not treated as unverifiable (R2) [R2_configured_telemetry_override_is_subtracted]"

# ── R2: a FAILED git status is not a status that found nothing ─────────────────────────
# R2_failed_status_is_not_landed
# `git status` exits non-zero on a corrupt or unreadable index. Piping it straight into
# `grep -c` discarded that: the count came back 0 and the audit printed `landed` over a
# target it never inspected. A false CLEAN is the one output this audit must never produce.
# Reported as P2 on PR #103 round 5.
mk_umb "$AU/corrupt" child-v
cascade "$AU/corrupt"
land "$AU/corrupt/child-v"
printf 'CORRUPT' > "$AU/corrupt/child-v/.git/index"
# Precondition: status really does fail here — otherwise the case proves nothing.
git -C "$AU/corrupt/child-v" status --porcelain -uall -- .harness/ >/dev/null 2>&1 \
  && fail "R2-failstatus: fixture precondition broken — git status still succeeds on the corrupt index"
cascade "$AU/corrupt"
printf '%s' "$AU_OUT" | grep -qE "landed +child-v" \
  && fail "R2-failstatus: FALSE CLEAN — a target whose git status FAILED was reported landed: $AU_OUT"
printf '%s' "$AU_OUT" | grep -qE "no read +child-v" \
  || fail "R2-failstatus: a failed git status was not reported as unverifiable: $AU_OUT"
pass "a failed git status is reported unverifiable, never landed (R2) [R2_failed_status_is_not_landed]"

# ── R2: the telemetry override is read in BOTH YAML quote forms ────────────────────────
# R2_telemetry_override_single_quoted
# YAML accepts `log: 'x'` as well as `log: "x"`, and install_one strips both before seeding
# the ignore. The helper stripped only double quotes, so a single-quoted override produced a
# pattern containing literal apostrophes, matched nothing, and the target read unverifiable
# forever. Reported as P2 on PR #103 round 5.
mk_umb "$AU/tlq" child-w
cascade "$AU/tlq"
python3 - "$AU/tlq/child-w/.harness/harness.config.yaml" <<'PYCFG' \
  || fail "R2-tlq: could not rewrite telemetry.log in the fixture config"
import sys
p = sys.argv[1]
s = open(p).read()
assert "log: telemetry.jsonl" in s, "telemetry.log anchor not found in " + p
open(p, "w").write(s.replace("log: telemetry.jsonl", "log: 'custom/my.jsonl'", 1))
PYCFG
cascade "$AU/tlq"
mkdir -p "$AU/tlq/child-w/.harness/custom"
printf '{}\n' > "$AU/tlq/child-w/.harness/custom/my.jsonl"
land "$AU/tlq/child-w"
git -C "$AU/tlq/child-w" check-ignore -q .harness/custom/my.jsonl \
  || fail "R2-tlq: fixture precondition broken — the single-quoted override is not ignored"
cascade "$AU/tlq"
printf '%s' "$AU_OUT" | grep -qE "landed +child-w" \
  || fail "R2-tlq: a single-quoted telemetry.log override was not subtracted: $AU_OUT"
pass "the telemetry override is read in both YAML quote forms (R2) [R2_telemetry_override_single_quoted]"

# ── R2: a telemetry override containing WHITESPACE is still subtracted ─────────────────
# R2_telemetry_override_with_whitespace
# git QUOTES any path containing whitespace (or non-ASCII, backslashes, control chars) in
# porcelain output — `".harness/custom/my log.jsonl"` — while the subtraction patterns are
# built from raw config values, so the quoted form never matched and the target reported
# `cannot verify` forever. Filed as E99-F11 from PR #103 round 6; fixed with `-z`, which
# emits raw paths instead of reimplementing git's C-style unescaping.
mk_umb "$AU/tlws" child-x
cascade "$AU/tlws"
python3 - "$AU/tlws/child-x/.harness/harness.config.yaml" <<'PYCFG' \
  || fail "R2-tlws: could not rewrite telemetry.log in the fixture config"
import sys
p = sys.argv[1]
s = open(p).read()
assert "log: telemetry.jsonl" in s, "telemetry.log anchor not found in " + p
open(p, "w").write(s.replace("log: telemetry.jsonl", 'log: "custom/my log.jsonl"', 1))
PYCFG
cascade "$AU/tlws"
mkdir -p "$AU/tlws/child-x/.harness/custom"
printf '{}\n' > "$AU/tlws/child-x/.harness/custom/my log.jsonl"
land "$AU/tlws/child-x"
# Preconditions: the path really contains whitespace, really is ignored, and git really does
# QUOTE it in default porcelain — that quoting IS the defect under test.
git -C "$AU/tlws/child-x" check-ignore -q ".harness/custom/my log.jsonl" \
  || fail "R2-tlws: fixture precondition broken — the whitespace override is not ignored"
git -C "$AU/tlws/child-x" status --porcelain -uall --ignored=matching -- .harness/ \
  | grep -q '^!! "' \
  || fail "R2-tlws: fixture precondition broken — git did not quote the whitespace path, so this case cannot reproduce the defect"
cascade "$AU/tlws"
printf '%s' "$AU_OUT" | grep -qE "no vcs +child-x" \
  && fail "R2-tlws: a whitespace telemetry override was not subtracted — the probe needs -z: $AU_OUT"
printf '%s' "$AU_OUT" | grep -qE "landed +child-x" \
  || fail "R2-tlws: a fully landed target with a whitespace override was not reported landed: $AU_OUT"
pass "a telemetry override containing whitespace is subtracted (R2) [R2_telemetry_override_with_whitespace]"

# ── R2: a newline inside an ignored path must not collapse into a false clean ──────────
# R2_newline_in_ignored_path_is_not_landed
# `tr '\0' '\n'` on `-z` output splits a path containing a literal newline into two lines;
# the second loses its `!! ` prefix and is dropped by the sed, so if the FIRST fragment
# matches a local-only pattern the whole record is subtracted and the target reads `landed`.
# A false CLEAN — not the over-count I first claimed in the commit that introduced it.
# Reported as P2 on PR #105 round 1.
mk_umb "$AU/nlpath" child-y
cascade "$AU/nlpath"
# A path whose first line is EXACTLY a local-only pattern, so a naive split subtracts it.
_nlname="$(printf 'telemetry.jsonl\nshadow')"
if ( cd "$AU/nlpath/child-y/.harness" && printf 'x\n' > "$_nlname" ) 2>/dev/null; then
  # Ignore it by a GLOB matching its tail, not by name: `.gitignore` is line-based and
  # cannot express a newline, and a directory-wide rule makes git collapse the whole
  # directory to one entry — neither produces the individual `!!` record this case needs.
  printf '*shadow\n' >> "$AU/nlpath/child-y/.harness/.gitignore"
  land "$AU/nlpath/child-y"
  # Preconditions: the file exists with a newline in its name AND git reports it ignored.
  [ -e "$AU/nlpath/child-y/.harness/$_nlname" ] \
    || fail "R2-nl: fixture precondition broken — the newline-named file does not exist"
  git -C "$AU/nlpath/child-y" status --porcelain -z -uall --ignored=matching -- .harness/ \
    | tr '\0' '\n' | grep -qE '^!! (.*/)?telemetry\.jsonl$' \
    || fail "R2-nl: fixture precondition broken — the naive split does not produce a subtractable first fragment, so this case cannot reproduce the defect"
  cascade "$AU/nlpath"
  printf '%s' "$AU_OUT" | grep -qE "landed +child-y" \
    && fail "R2-nl: FALSE CLEAN — a newline inside an ignored path collapsed into a subtracted record: $AU_OUT"
  pass "a newline inside an ignored path does not collapse into a false clean (R2) [R2_newline_in_ignored_path_is_not_landed]"
else
  # Some filesystems reject newlines in names. Skipping is honest; silently passing is not.
  echo "ok - SKIPPED R2_newline_in_ignored_path_is_not_landed (filesystem rejects newline in a filename)"
fi


# A final negative probe is not a suite failure.
exit 0
