#!/usr/bin/env bash
# init.sh — environment verification gate.
# The Orchestrator MUST run this before any work. Non-zero exit = STOP.
# It proves the harness is structurally healthy so agents don't hallucinate fixes.
#
# Adapt the project-specific section to the target repo (tests, deps, build).

set -euo pipefail

# Resolve the harness root (this script's dir) and run structural checks from there,
# so an installed copy at <repo>/.harness/init.sh works when invoked from the repo
# root. PROJECT_ROOT is where project-specific checks (tests, build) must run: the
# parent when we're installed under `.harness/`, else the harness root itself.
HARNESS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
case "$HARNESS_DIR" in
  */.harness) PROJECT_ROOT="$(dirname "$HARNESS_DIR")" ;;
  *)          PROJECT_ROOT="$HARNESS_DIR" ;;
esac
cd "$HARNESS_DIR"

fail() { echo "❌ init: $1" >&2; exit 1; }
ok()   { echo "✅ $1"; }

echo "── harness-sdd init ──────────────────────────────"

# 1. Structural checks — the harness itself must be intact.
[ -f AGENTS.md ]            || fail "AGENTS.md missing (no entrypoint)"
[ -f harness.config.yaml ]  || fail "harness.config.yaml missing"
[ -d agents ]               || fail "agents/ missing (no role prompts)"
[ -d specs ]                || fail "specs/ missing"
[ -d progress ]             || fail "progress/ missing"
for role in orchestrator architect builder reviewer scout; do
  [ -f "agents/${role}.md" ] || fail "agents/${role}.md missing"
done
ok "harness structure intact"

# 1b. Drift guard (E24-F01) — the installed harness must be the COMMITTED harness.
#
#     harness-install.sh stamps VERSION into .harness/.harness-version, but that stamp is
#     read only by the NEXT installer run (upgrade-vs-fresh detection). At runtime nothing
#     ever checked whether the body an agent is about to read was committed, so an upgrade
#     that was written but never landed was indistinguishable from one that was landed.
#     That is not hypothetical: a v0.50.x umbrella cascade left 26-29 uncommitted files in
#     each of five children, and every Builder and Reviewer spawned there afterwards read
#     agent prompts no commit describes.
#
#     ONE CHECK, NOT TWO. `.harness-version` is itself a tracked file inside the
#     harness-owned tree and every upgrade rewrites it, so a half-applied upgrade shows up
#     as an uncommitted change to the stamp via the same dirty-tree check that catches the
#     prompts. There is no second signal available here: init.sh has no access to the
#     harness SOURCE it was installed from, so it cannot compare installed-vs-latest at all.
#
#     FALSE POSITIVES ARE THE DOMINANT RISK. This gate runs before every agent step, so a
#     misfire halts the whole harness and the guard gets disabled within a week. Every
#     ambiguous case therefore degrades to a silent skip or a warning, never to a failure:
#     no install (R6), no git (R7), nothing tracked (R9). Only an unambiguously
#     half-applied write fails.
#
#     The guard REPORTS; it never repairs. No auto-commit, no auto-reinstall, no writes.
if [ -f "$HARNESS_DIR/.harness-version" ]; then
  # R7: a target that is not a git work tree cannot have anything "unlanded". Silent.
  if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [ -n "${HARNESS_SKIP_DRIFT_CHECK:-}" ]; then
      # R8: loud. An overridden gate that says nothing is a gate nobody remembers
      # overriding. Deliberately checked AFTER the install/git tests, so an override set
      # globally does not announce a skip of a check that never applied here.
      echo "ℹ️  harness drift check skipped (HARNESS_SKIP_DRIFT_CHECK is set)"
    else
      # R4/R5/R8: the checked set comes from ONE definition, tools/harness-owned-paths.sh,
      # which the E24-F02 cascade audit also calls. It used to live inline here; E99-F10 then
      # needed four corrections to it in a single week — .codex/.gemini claimed wholesale,
      # symlinked ledgers, non-regular ledger entries, wildcard basenames — every one a FALSE
      # POSITIVE failing this mandatory gate on a file the operator owns. A second copy in the
      # installer would have had to relearn all four, so there is exactly one.
      OWNED_HELPER="$HARNESS_DIR/tools/harness-owned-paths.sh"
      if [ ! -x "$OWNED_HELPER" ] && [ ! -f "$OWNED_HELPER" ]; then
        # A torn install (init.sh present, tools/ not) must not hard-fail the gate every
        # session — same fail-safe direction as every other ambiguous case here. tools/ is
        # harness-owned and ships with init.sh, so this is a broken copy, not a configuration.
        echo "⚠️  tools/harness-owned-paths.sh missing — cannot verify the installed harness is committed (warn-only)"
        OWNED_HELPER=""
      fi
      if [ -n "$OWNED_HELPER" ]; then
      HARNESS_BODY=()
      while IFS= read -r _l; do [ -n "$_l" ] && HARNESS_BODY+=( "$_l" ); done <<EOF
$(sh "$OWNED_HELPER" body "$HARNESS_DIR")
EOF
      HARNESS_OWNED=()
      while IFS= read -r _l; do [ -n "$_l" ] && HARNESS_OWNED+=( "$_l" ); done <<EOF
$(sh "$OWNED_HELPER" all "$HARNESS_DIR")
EOF

      # ORDER IS LOAD-BEARING (R9 before R2). In a repo where nothing is tracked yet,
      # `git status --porcelain -- .harness/` reports `?? .harness/` — non-empty. Running
      # status first would read an un-version-controlled install as DRIFT and hard-fail it,
      # which is exactly the false positive R9 exists to prevent. ls-files decides first.
      #
      # And it probes the BODY ALONE, not the combined set. A repo that gitignores
      # `.harness/` while tracking the root glue has a non-zero combined count, which
      # skipped the warn-only branch — and then `git status` cannot report the ignored body
      # either, so an edited `.harness/agents/builder.md` produced `✅ installed harness
      # matches the commit`. A false CLEAN is the worst output this feature can emit, and it
      # also contradicted the docs/INSTALL.md promise that an untracked body warns.
      if [ "$(git -C "$PROJECT_ROOT" ls-files -- "${HARNESS_BODY[@]}" | wc -l | tr -d ' ')" = "0" ]; then
        echo "⚠️  installed harness body (.harness/) is not version-controlled here — cannot verify it matches a commit (warn-only)"
      else
        # -uall is REQUIRED, not a default worth inheriting. `status.showUntrackedFiles=no`
        # in a repo or global gitconfig suppresses untracked files entirely, and an upgrade
        # that ADDS a harness-owned file leaves it untracked — so without this flag the
        # guard prints "installed harness matches the commit" over an unlanded file, which
        # is the exact silent false negative this whole feature exists to end. Reproduced:
        # `git config status.showUntrackedFiles no` + a new .harness/agents/*.md ⇒ clean.
        DRIFT="$(git -C "$PROJECT_ROOT" status --porcelain -uall -- "${HARNESS_OWNED[@]}")"
        if [ -z "$DRIFT" ]; then
          ok "installed harness matches the commit"                       # R10
        else
          # R2/R3: name the count, show a bounded sample, and hand over the command that
          # lists the rest. 29 paths inline is noise; a count with no paths is unactionable.
          DRIFT_N="$(printf '%s\n' "$DRIFT" | wc -l | tr -d ' ')"
          # `sed -n '1,10p'`, NOT `head -n 10`. head closes its input after ten lines, so on
          # a drift larger than the pipe buffer the upstream printf takes SIGPIPE and exits
          # 141 — and under this script's `set -o pipefail` + `set -e` that aborts the whole
          # gate right here, before the elision count, the recovery command, or the fail()
          # diagnostic ever print. Reproduced with 1,800 untracked files: exit 141, no
          # message, at exactly the moment the operator most needs one. sed reads its input
          # to EOF, so nothing early-closes.
          printf '%s\n' "$DRIFT" | sed -n '1,10p' | sed 's/^/     /'
          [ "$DRIFT_N" -le 10 ] || echo "     … $((DRIFT_N - 10)) more …"
          # Reproduce the ACTUAL pathspec set. A hand-written approximation drifts from
          # HARNESS_OWNED silently: an earlier version printed `.harness/ .claude/ .agents/`,
          # which both omitted the checked `.codex/agents/`, `.gemini/agents/` and
          # `opencode.json` AND dropped every `:(exclude)`, so eleven drifted files under
          # .codex/agents/ would trip the gate and then be invisible to the one command
          # offered for inspecting them.
          # EVERY interpolated value goes through the same escaper — the root AND each
          # pathspec. The root needs it because a repo path containing whitespace reaches
          # git as its first word only (exit 128 when pasted). The pathspecs need it because
          # a LEDGER-DERIVED entry carries an operator-chosen basename: a stamp named
          # `operator's-role.toml` closed the quote early and the advertised command died
          # with `unexpected EOF while looking for matching quote` — on the one line whose
          # entire purpose is to be pasted. One helper, so the two cannot diverge again.
          _shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
          DRIFT_SPEC=""
          for _p in "${HARNESS_OWNED[@]}"; do DRIFT_SPEC="$DRIFT_SPEC $(_shq "$_p")"; done
          DRIFT_ROOT="$(_shq "$PROJECT_ROOT")"
          echo "   list them:  git -C $DRIFT_ROOT status --porcelain -uall --$DRIFT_SPEC"
          echo "   land them, or re-run with HARNESS_SKIP_DRIFT_CHECK=1 to proceed anyway."
          fail "the installed harness is not committed — $DRIFT_N harness-owned path(s) differ from what this branch records. Agents would run on a body no commit describes."
        fi
      fi
      fi
    fi
  fi
fi

# 2. TaskStore presence + schema validation (local backend).
#    Syntactically-valid JSON is not enough: an unsupported status or a missing
#    required field (e.g. spec_path) must halt here, not surface later as corrupt
#    routing state. We validate against store/tasks.schema.json.
if grep -q "tasks: local" harness.config.yaml 2>/dev/null; then
  [ -f state/tasks.json ]          || fail "state/tasks.json missing (local TaskStore)"
  [ -f store/tasks.schema.json ]   || fail "store/tasks.schema.json missing (cannot validate TaskStore)"
  # python3 is a HARD prerequisite for the local backend, not optional. Since
  # E15-F01 the ONLY supported `set_status` write path is the flock-guarded
  # `python3 tools/tasks-lock.py`, and schema validation runs the same
  # `python3 tools/validate-board.py`. A python3-less install would look "ready"
  # here yet fail on the very first Orchestrator transition with
  # `python3: not found`, so we fail-stop now with a clear message rather than
  # warn-and-continue.
  command -v python3 >/dev/null 2>&1 \
    || fail "python3 not found — REQUIRED for TaskStore schema validation and the mandatory board write lock (tools/tasks-lock.py). Install python3 and re-run."
  # The lock helper depends on stdlib fcntl.flock; it is stdlib on every Unix
  # target but verify it is importable so a broken/stripped interpreter fails
  # clearly HERE, not mid-transition.
  python3 -c "import fcntl" 2>/dev/null \
    || fail "python3 lacks the stdlib 'fcntl' module — REQUIRED for the board write lock (tools/tasks-lock.py). Use a Unix python3 with fcntl support."
  # The validation logic lives in ONE canonical place — tools/validate-board.py —
  # shared verbatim with the guarded write path (tasks-lock.py imports its
  # validate()). It prefers jsonschema.Draft7Validator when importable and
  # otherwise runs the complete zero-dependency structural check, so init.sh
  # stays zero-dependency while accepting/rejecting exactly what the write lock
  # does. Same stderr contract as before (draft warning, then two-space-prefixed
  # errors) and non-zero on invalid.
  # `--spec-root .` additionally checks the board against what is on disk (E99-F14):
  # an `sdd` feature past `pending` whose `spec_path` leads nowhere a Reviewer can
  # read, and any spec/epic file whose frontmatter `status` disagrees with the board.
  # store/local.md makes both a contract; until now nothing verified either, and each
  # cost a review round on PR #122. The flag is opt-in in the validator, so passing it
  # here is what arms the check for a real harness tree.
  python3 tools/validate-board.py state/tasks.json store/tasks.schema.json --spec-root . \
    || fail "state/tasks.json failed schema validation or disagrees with the specs on disk (see errors above)"
  ok "TaskStore (local) valid against schema and consistent with specs/"

  # Dependency cycles are planning diagnostics, not schema failures. Run this
  # only after canonical validation succeeds, capture the helper status before
  # rendering records, and keep both cycles and helper failures warn-only.
  if CYCLE_RECORDS="$(python3 tools/task-diagnostics.py cycles state/tasks.json 2>&1)"; then
    if [ -n "$CYCLE_RECORDS" ]; then
      while IFS="$(printf '\t')" read -r cycle_code cycle_kind cycle_path; do
        [ "$cycle_code" = "dependency-cycle" ] || continue
        echo "⚠️  TaskStore dependency-cycle [$cycle_kind]: $cycle_path (warn-only)"
      done <<EOF
$CYCLE_RECORDS
EOF
    fi
  else
    echo "⚠️  TaskStore dependency diagnostics unavailable: $CYCLE_RECORDS (warn-only)" >&2
  fi
fi

# 2a2. Umbrella-resolved body (E24-F03, ADR-0004). REPORT ONLY — this can never fail the
#      gate. A child separated from its umbrella (a lone clone, CI, a PR reviewer's tree)
#      is a SUPPORTED state: init.sh, the verification gate and the PR loop all still work
#      there, because they read the program tier, which is always a full local copy. Only
#      the prose body is remote. Saying so here is what turns "this file is a pointer to
#      nowhere" from a mystery into a fact the reader already knows.
#
#      Section-scoped read: `root:` is taken only from inside the top-level `umbrella:`
#      block, so an unrelated `root:` elsewhere in the config can never be mistaken for it.
UMBRELLA_ROOT="$(awk '
  /^umbrella:[[:space:]]*(#.*)?$/ { u=1; next }
  u && /^[^[:space:]#]/ { u=0 }
  u && /^[[:space:]]+root:/ {
    sub(/^[[:space:]]+root:[[:space:]]*/, "")
    # ONE RULE, stated once, instead of a special case per metacharacter. Three review
    # rounds landed on this function because each fix answered a sample rather than the
    # requirement, and every patch traded one gap for the next:
    #   E99-F13    strip comments before quotes  -> `"/a#b"`      read as `/a`
    #   r1 #3712741520  stop at the FIRST quote  -> `"/a"b"`      read as `/a`
    #   r2 #3712898952  require a bare remainder -> `"/a#b" # c`  read as `/a`
    #
    # The requirement: `set_umbrella_root` writes `"<path>"` — outer quotes it adds
    # itself, the path verbatim between them, NO escaping of any kind — and an operator
    # may add a trailing comment. So the closing quote is THE LAST QUOTE ON THE LINE
    # FOLLOWED BY NOTHING BUT OPTIONAL WHITESPACE AND AN OPTIONAL `#` COMMENT. Everything
    # between it and the opening quote is the value, `#` and `"` alike. Scanning from the
    # right is what makes that true: the first candidate it accepts is the last one.
    # The format has NO escaping, so `"/a" # b"` is genuinely ambiguous — value `/a` with
    # comment `# b"`, or value `/a" # b`. Rank the two readings instead of hoping one
    # predicate covers both: the machine-written form is authoritative, a comment is a
    # courtesy for a hand-edited file.
    q = substr($0, 1, 1)
    if (q == "\"" || q == "'\''") {
      # PASS 1 — exactly what set_umbrella_root writes: `"<path>"`, nothing after it.
      # At most ONE quote can qualify (an earlier one would have a quote in its
      # remainder, which is not whitespace), so this pass cannot be ambiguous and its
      # direction cannot matter.
      for (i = length($0); i > 1; i--)
        if (substr($0, i, 1) == q && substr($0, i + 1) ~ /^[[:space:]]*$/) {
          print substr($0, 2, i - 2); exit
        }
      # PASS 2 — hand-edited: a trailing comment follows the closing quote. Several
      # quotes CAN qualify here (`"/a" # b" # c`), so direction is load-bearing: take the
      # FIRST, so the comment begins as early as the line allows and is never swallowed
      # into the value.
      for (i = 2; i <= length($0); i++)
        if (substr($0, i, 1) == q && substr($0, i + 1) ~ /^[[:space:]]*#/) {
          print substr($0, 2, i - 2); exit
        }
    }
    # Unquoted (or opened with a quote that never closes): a plain scalar, where a
    # comment starts at the first `#`. Unchanged from before E99-F13 — existing
    # hand-written configs depend on exactly this.
    sub(/[[:space:]]*#.*$/, ""); gsub(/^"|"$|^'\''|'\''$/, ""); print; exit
  }
' harness.config.yaml 2>/dev/null)"
#      RECORDING an umbrella is not the same as RESOLVING one. A child that already held a
#      full body when the cascade reached it keeps that body (converting it is destructive
#      and is E24-F04) and still gets `umbrella.root` written. Reporting "the prose body is
#      remote" there would be plainly false — `agents/`, `docs/` and the templates are all
#      sitting right here. So read the LAYOUT off disk, from the same stub sentinel the
#      installer writes, before saying anything about where the body lives.
if [ -n "${UMBRELLA_ROOT:-}" ]; then
  if head -n 1 AGENTS.md 2>/dev/null | grep -qxF '<!-- harness:umbrella-stub -->'; then
    if [ -f "$UMBRELLA_ROOT/.harness/.harness-version" ]; then
      echo "ℹ️  harness body resolves from the umbrella at $UMBRELLA_ROOT (prose tier is stubs)"
    else
      echo "ℹ️  umbrella at $UMBRELLA_ROOT is not reachable — the prose body (agent prompts, docs) is remote and unavailable here; init.sh, verification and the PR loop are unaffected"
    fi
  else
    echo "ℹ️  umbrella.root recorded ($UMBRELLA_ROOT), but this target holds a full local body — nothing resolves remotely"
  fi
fi

# 2b. Umbrella mode (additive, opt-in). Engaged ONLY when harness.config.yaml has a
#     non-empty `umbrella.manifest` AND that file exists. Inert otherwise, so a
#     single-repo target is completely unaffected. The check is NON-FATAL: it warns
#     about manifest repos whose `path` is missing rather than blocking the gate.
UMBRELLA_MANIFEST="$(sed -n 's/^[[:space:]]*manifest:[[:space:]]*"\{0,1\}\([^"#]*\)"\{0,1\}.*/\1/p' harness.config.yaml 2>/dev/null | head -n1 | sed 's/[[:space:]]*$//')"
if [ -n "${UMBRELLA_MANIFEST:-}" ] && [ -f "$UMBRELLA_MANIFEST" ]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$UMBRELLA_MANIFEST" <<'PY' || true
import sys, os, re
path = sys.argv[1]
base = os.path.dirname(os.path.abspath(path))
repo = None
missing = []
try:
    with open(path) as f:
        lines = f.readlines()
except OSError as e:
    print("⚠️  umbrella manifest unreadable: %s" % e); sys.exit(0)
# Minimal YAML read (zero-dep): top-level `repos:` mapping, each repo a 2-space key
# with a `path:` under it. Good enough to flag missing child-repo paths.
in_repos = False
for ln in lines:
    if re.match(r"^repos:\s*$", ln):
        in_repos = True; continue
    if in_repos and re.match(r"^\S", ln):
        in_repos = False
    if not in_repos:
        continue
    # Repo keys must use the SAME grammar as the slice-id `@<repo>` segment
    # (^[a-z0-9-]+$). A key with an underscore/uppercase could not be represented
    # as a canonical slice id `E03-F01@<repo>`, so flag it rather than silently
    # accepting an undispatchable manifest entry.
    m = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", ln)
    if m:
        repo = m.group(1)
        if not re.match(r"^[a-z0-9-]+$", repo):
            print("⚠️  umbrella manifest: repo key '%s' is not a valid slice-id segment "
                  "(use ^[a-z0-9-]+$ to match '<feature-id>@<repo>')" % repo, file=sys.stderr)
        continue
    m = re.match(r"^\s+path:\s*\"?([^\"#\n]+)\"?", ln)
    if m and repo:
        p = m.group(1).strip()
        full = p if os.path.isabs(p) else os.path.join(base, p)
        if not os.path.exists(full):
            missing.append((repo, p))
for r, p in missing:
    print("⚠️  umbrella manifest: repo '%s' path not found: %s" % (r, p))
PY
  fi
  echo "ℹ️  umbrella mode: manifest present ($UMBRELLA_MANIFEST)"
fi

# 2c. ADR-citation sweep (WARN-ONLY, additive). Feature specs cite the ADRs they
#     honor in a `## Architecture alignment` section (agents/architect.md); the
#     Reviewer soft-flags a cited-but-nonexistent id at review time. This sweep
#     surfaces the same typo at session start instead: for each
#     specs/epics/**/*.spec.md carrying the section, every `ADR-NNNN` cited INSIDE
#     that section (only there — incidental ADR-NNNN mentions elsewhere don't count)
#     must resolve to an ADR file `NNNN-*.md`. A miss WARNS and NEVER fails the gate
#     (the ADR may have been renamed/removed legitimately — the Reviewer's soft flag
#     owns the verdict).
#
#     ADR NAMESPACES. A project may keep more than one ADR space: the platform space
#     `specs/adr/` plus one product/agent space per subtree, e.g. `specs/<product>/adr/`
#     (that split is itself an ADR-recorded decision downstream). The number spaces are
#     INDEPENDENT and normally COLLIDE — `0023` may exist in both with different
#     content — so "which space" is part of the citation, not a detail.
#     A namespace is a directory literally named `adr/` anywhere under `specs/`; only
#     `*.md` sitting DIRECTLY in it counts as an ADR (an `adr/archive/` subtree is not a
#     namespace). Its TOKEN is the parent directory's basename, with the reserved token
#     `platform` for the root space `specs/adr/` (which has no parent name of its own).
#
#     RESOLUTION IS QUALIFIER-AWARE (E99-F50). Specs already disambiguate in prose:
#       * QUALIFIED — `<ns>/ADR-NNNN`, or `<ns> ADR-NNNN` when `<ns>` is a known
#         namespace token — ASSERTS a space, so it resolves against THAT space ONLY.
#         `platform ADR-0023` warns even when `bookings/0023` exists: a cross-namespace
#         id is exactly the typo this sweep exists to catch. An unknown `<ns>/` warns too.
#       * BARE — `ADR-NNNN` asserts NO space, so it resolves against ANY namespace and
#         warns only when it resolves in NONE. Deliberate: pre-convention corpora and
#         single-namespace projects write bare ids, and inferring a space the author
#         never wrote would recreate the false-positive wall this rule replaced.
#     RESIDUAL HOLE (known, intentional): a BARE citation is NOT namespace-checked, so in
#     a multi-namespace project a bare cross-namespace typo (bare `ADR-0023` meant as
#     platform, resolving against bookings/0023) still passes silently. Write the
#     qualifier to get it checked — that is the convention `specs/_templates/feature.spec.md`,
#     `agents/architect.md` and `agents/reviewer.md` now teach.
#     No-op when `specs/` holds no `adr/` directory at all (graceful degradation,
#     mirroring the Reviewer check's precondition). Zero-dep + fast: the per-namespace
#     index is built ONCE per run, then each citation is one `grep -qx`.
ADR_NS_DIRS="$(find specs -type d -name adr 2>/dev/null | sort)"
if [ -n "$ADR_NS_DIRS" ]; then
  # Namespace tokens (`platform` for specs/adr, else the adr/ dir's parent basename)
  # and an alternation of them, used to recognize the `<ns> ADR-NNNN` prose form.
  ADR_NS_TOKENS="$(printf '%s\n' "$ADR_NS_DIRS" \
                   | sed -e 's|/adr$||' -e 's|^specs$|platform|' -e 's|.*/||' | sort -u)"
  ADR_NS_ALT="$(printf '%s\n' "$ADR_NS_TOKENS" | tr '\n' '|' | sed 's/|$//')"
  # Namespace-tagged index (`<token>/<NNNN>`), built once: the per-citation lookup is a
  # string match, not a filesystem probe per space. ADR_INDEX drops the tag for bare ids.
  ADR_INDEX_NS="$(printf '%s\n' "$ADR_NS_DIRS" | while IFS= read -r d; do
      [ -n "$d" ] || continue
      p="${d%/adr}"; t="platform"
      [ "$p" = "specs" ] || t="${p##*/}"
      printf '%s\n' "$d"/*.md | sed 's|.*/||' \
        | grep -oE '^[0-9]+' | sed "s|^|$t/|" || true
    done | sort -u)"
  ADR_INDEX="$(printf '%s\n' "$ADR_INDEX_NS" | sed 's|^.*/||' | sort -u || true)"
  # Comma-joined for humans: a namespace path may itself contain a space, so a
  # space-joined list would be ambiguous.
  ADR_NS_LIST="$(printf '%s\n' "$ADR_NS_DIRS" | sed 's|$|, |' | tr -d '\n' | sed 's|, $||')"
  ADR_MISS=0
  for spec in $(grep -rl '^## Architecture alignment' specs/epics --include='*.spec.md' 2>/dev/null || true); do
    # Normalize each citation to `adr-NNNN` (bare) or `<ns>/adr-NNNN` (qualified):
    # lowercase, promote a KNOWN `<ns> ADR-` prose qualifier to `<ns>/`, then drop any
    # other leading word (ordinary prose like "the contract ADR-0012" is NOT a qualifier).
    # No spaces survive, so the `for` word-split below is safe.
    #
    # Two normalizations run BEFORE the extractor, because the optional qualifier group
    # `[A-Za-z0-9_-]+` is a blunt instrument at both of its boundaries:
    #  1. Emphasis/quote wrappers are deleted (`*`, `"`, backtick, `'`). Without this a
    #     REAL qualifier written `**platform** ADR-0023` is demoted to a bare id, because
    #     the char before the space is outside the group's char class. `_` is deliberately
    #     NOT deleted: underscore is legal in a namespace token (`my_product/`), so
    #     stripping it would corrupt real tokens (`_platform_ ADR-N` stays demoted).
    #  2. A `|` is appended to EVERY id. Without this the group happily eats a preceding
    #     CITATION (`ADR-0042` is letters+digits+hyphen too), so `ADR-0042 ADR-0001`
    #     yields ONE match whose "qualifier" `adr-0042` is then discarded by the demotion
    #     `sed` below — the first id would never be looked up at all. The delimiter must
    #     be a SUFFIX: a `|` prefix would also break the legitimate `<ns> ADR-NNNN` form.
    for cite in $(awk '/^## Architecture alignment/{f=1;next} /^## /{f=0} f' "$spec" \
                  | sed -e 's#[*"`]##g' -e "s#'##g" -e 's#ADR-[0-9][0-9][0-9][0-9]#&|#g' \
                  | grep -oE '([A-Za-z0-9_-]+[ /])?ADR-[0-9]{4}' \
                  | tr '[:upper:]' '[:lower:]' \
                  | sed -E "s#^(${ADR_NS_ALT}) adr-#\\1/adr-#" \
                  | sed -E 's#^[a-z0-9_-]+ adr-#adr-#' \
                  | sort -u || true); do
      case "$cite" in
        */*)  # qualified: that namespace only
          ns="${cite%%/*}"; n="${cite##*adr-}"
          if ! printf '%s\n' "$ADR_INDEX_NS" | grep -qx "$ns/$n"; then
            echo "⚠️  ADR citation: $spec cites $ns/ADR-$n but no ${n}-*.md exists in the '$ns' ADR namespace (a qualified citation resolves in that namespace ONLY; namespaces: $ADR_NS_LIST)"
            ADR_MISS=$((ADR_MISS+1))
          fi ;;
        *)    # bare: any namespace
          n="${cite#adr-}"
          if ! printf '%s\n' "$ADR_INDEX" | grep -qx "$n"; then
            echo "⚠️  ADR citation: $spec cites ADR-$n but no ${n}-*.md exists in any ADR namespace (searched: $ADR_NS_LIST)"
            ADR_MISS=$((ADR_MISS+1))
          fi ;;
      esac
    done
  done
  if [ "$ADR_MISS" -eq 0 ]; then
    ok "ADR citations resolve (namespaces: $ADR_NS_LIST)"
  else
    echo "⚠️  $ADR_MISS unresolved ADR citation(s) — warn-only, never blocks the gate (fix the typo or update the spec)"
  fi
fi

# 2z. Escalation visibility (2026-09-04). `escalation.after_rejections > 0` READS as
#     active in the config, but the feature fires only when `.harness/.escalation-arming`
#     says `armed` — and that file is written by the installer, so a target that set the
#     threshold without re-running it (or whose builder-heavy resolves to no different
#     model) carries a silently-inert safety feature. E99-F25 went three rejection rounds
#     on the base builder for exactly this reason. One line here makes the state visible
#     at every session start; builder-role.sh remains the enforcement point.
ESC_THRESHOLD="$(awk '
  /^escalation:[[:space:]]*(#.*)?$/ { e=1; next }
  e && /^[^[:space:]#]/ { e=0 }
  e && /^[[:space:]]+after_rejections:/ {
    sub(/^[[:space:]]+after_rejections:[[:space:]]*/, ""); sub(/[[:space:]]*#.*$/, "")
    print; exit
  }' harness.config.yaml 2>/dev/null || true)"
case "$ESC_THRESHOLD" in
  ''|0|*[!0-9]*) : ;;   # off / absent / malformed (builder-role.sh warns on malformed) — not noteworthy
  *)
    ESC_ARMING="$HARNESS_DIR/.escalation-arming"
    # A symlinked arming file reads as absent — same refusal builder-role.sh applies.
    if [ ! -L "$ESC_ARMING" ] && [ -f "$ESC_ARMING" ] \
       && [ "$(head -n 1 "$ESC_ARMING" 2>/dev/null)" = "armed" ]; then
      echo "ℹ️  escalation: ARMED (builder-heavy after $ESC_THRESHOLD rejections)"
    else
      echo "⚠️  escalation: configured (after_rejections: $ESC_THRESHOLD) but DISARMED — .escalation-arming is absent or not 'armed', so builder-heavy will never fire. Configure models.builder-heavy and re-run the installer. (warn-only)"
    fi
    ;;
esac

# 3. Project-specific checks.
#    Project-authored gates live in `.harness/init.project.sh` — seeded once by
#    harness-install.sh and NEVER clobbered on upgrade, unlike THIS file (which is
#    harness BODY and gets overwritten). Put FAST structural/presence/build checks
#    here (the things that must hold for any agent to safely proceed) rather than
#    editing this file, or they vanish on the next upgrade.
#    KEEP IT FAST: init.sh runs before EVERY orchestrator step, so a slow suite here
#    taxes the whole loop (multiplied across slices in umbrella mode). The heavy test
#    suite belongs in `verification.test_command`, which the Reviewer runs once at the
#    `in-review` gate — not here. The hook is sourced from the PROJECT ROOT so
#    `npm test` / `pytest` resolve against the repo, and it inherits the `fail`/`ok`
#    helpers defined above.
cd "$PROJECT_ROOT"
PROJECT_CHECKS="$HARNESS_DIR/init.project.sh"
if [ -f "$PROJECT_CHECKS" ]; then
  # shellcheck source=/dev/null
  . "$PROJECT_CHECKS"
else
  echo "ℹ️  no project-specific checks (.harness/init.project.sh absent)"
fi

echo "──────────────────────────────────────────────────"
ok "environment ready — agents may proceed"
