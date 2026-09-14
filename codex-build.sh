#!/bin/sh
# codex-build.sh — execution.builder.delegate_cmd implementation backed by Codex CLI.
#
# TRIAL, NOT SHIPPED BODY. This file lives at the repo ROOT on purpose: the installer's
# body lists (harness-install.sh:722-723) copy `tools/`, `store/`, `agents/`, `docs/` and
# `init.sh` into every target, and a root script is in NONE of them. So this changes no
# installed body and needs no VERSION bump. If the trial proves out, it gets seeded as a
# real feature, moved under tools/, and asserted in tests/ — see the report on the branch.
#
# THE SEAM. agents/builder.md "Loop B" invokes a delegate exactly as:
#
#     <delegate_cmd> <feature-id> <abs-spec-path>
#
# and reads ONLY the exit status: 0 = implemented, non-zero = the Builder records the
# failure in progress/ and hands back to the Orchestrator WITHOUT improvising a fix. That
# is the whole contract. Everything else here is this wrapper's own choice.
#
# WHY THE PROMPT IS THE HARD PART. The contract passes an id and a path, nothing more —
# no tasks, no plan, no DO-NOT-TOUCH list. An executor that is handed only a path will
# read what it feels like reading. So this script resolves the worklist itself and names
# the files, which is the difference between delegating a spec and delegating a wish.
#
# Env overrides (all optional):
#   CODEX_BUILD_MODEL     -m value; empty ⇒ Codex's own default (float, don't pin)
#   CODEX_BUILD_SANDBOX   -s value; default workspace-write (it must write code)
#   CODEX_BUILD_LOG_DIR   where the transcript + last message land; default progress/codex

set -eu

_feature="${1:-}"
_spec="${2:-}"

if [ -z "$_feature" ] || [ -z "$_spec" ]; then
  echo "usage: codex-build.sh <feature-id> <abs-spec-path>" >&2
  exit 64
fi

command -v codex >/dev/null 2>&1 || {
  echo "codex-build.sh: no 'codex' on PATH — the delegate cannot run" >&2
  exit 69
}

_model="${CODEX_BUILD_MODEL:-}"
_sandbox="${CODEX_BUILD_SANDBOX:-workspace-write}"
_logdir="${CODEX_BUILD_LOG_DIR:-progress/codex}"
mkdir -p "$_logdir"
_last="$_logdir/$_feature.last.md"
_transcript="$_logdir/$_feature.jsonl"

# ── Resolve the worklist ────────────────────────────────────────────────────────
# Two shapes, both real (agents/builder.md): an `sdd: true` feature has the four-file
# spec and a tasks.md; an `sdd: false` fix has NO spec dir at all and its worklist is the
# inbox brief. Guessing between them is how a delegate silently builds nothing, so this
# resolves it explicitly and fails closed when neither exists.
_tasks="$_spec/$_feature.tasks.md"
if [ -f "$_tasks" ]; then
  _mode=spec
  _worklist="Work $_spec/$_feature.tasks.md IN ORDER, one task at a time.
Read $_spec/$_feature.spec.md for the EARS acceptance criteria, $_spec/$_feature.plan.md
for the file list and its DO NOT TOUCH section, and $_spec/$_feature.tests.md for the
tests you must write (every R-id needs a passing test)."
elif [ -f "progress/inbox/$_feature.md" ]; then
  _mode=brief
  _worklist="This item has NO four-file spec. Its worklist is the inbox brief at
progress/inbox/$_feature.md — implement the fix it describes, and write at least one test
that proves the fix (revert the fix in place and confirm that test fails with the real
symptom before you call it done)."
else
  echo "codex-build.sh: no worklist for $_feature — neither $_tasks nor progress/inbox/$_feature.md exists" >&2
  exit 66
fi

echo "── codex delegate ── $_feature ($_mode) sandbox=$_sandbox model=${_model:-<codex default>}" >&2

set -- exec --cd "$(pwd)" --sandbox "$_sandbox" \
  --output-last-message "$_last" --json
[ -n "$_model" ] && set -- "$@" -m "$_model"

# stdout carries the JSONL event stream; it is saved, not swallowed, so a failed build
# leaves evidence the Builder (and a human) can read.
#
# `< /dev/null` is load-bearing. `codex exec` APPENDS piped stdin to the prompt as a
# `<stdin>` block, and the Builder may invoke this delegate with stdin attached to
# anything at all. The first smoke run printed "Reading additional input from stdin..."
# and got lucky; left alone it is a silent prompt-injection seam from whatever the
# caller happened to have on fd 0.
if codex "$@" "You are the Builder in a spec-driven development harness. Implement
feature $_feature in this repository.

$_worklist

Rules that are not negotiable:
- Touch ONLY the files the plan lists. Honor its DO NOT TOUCH list exactly.
- Do NOT redesign. If the spec is wrong or incomplete, stop and say so in your final
  message rather than improvising a fix — a human reviews this.
- Run ./init.sh and make it pass before you finish. Run the project's test command too.
- Tick each completed task in the tasks file as you go.
- Do NOT commit, push, or open a pull request. Leave the work in the working tree.

Your final message must state: which tasks you completed, which tests you added, and the
exact result of ./init.sh." > "$_transcript" < /dev/null; then
  _status=0
else
  _status=$?
fi

if [ -s "$_last" ]; then
  echo "── executor summary ──"
  cat "$_last"
fi
echo "── transcript: $_transcript ──" >&2

exit "$_status"

# ── HOW TO USE THIS (and why the config flip is NOT committed) ──────────────────
# The delegate is engaged by two keys in harness.config.yaml:
#
#     execution:
#       builder:
#         backend: delegate
#         delegate_cmd: "./codex-build.sh"
#
# DO NOT COMMIT THAT FLIP IN THIS REPO. This repo's harness.config.yaml is the
# fresh-install SEED TEMPLATE — harness-install.sh copies it verbatim into every target
# (see harness-install.sh:545 and :1896). Committing `backend: delegate` here would ship a
# delegate backend, pointed at a script that does not exist in the target, to everyone who
# installs from this source. tests/test_installer_toggles.sh R9 catches it: it compares a
# SEEDED config against a MIGRATED one, and the migrate path re-seeds the built-in
# `delegate_cmd: ""`, so the two diverge and the suite goes red. That test is right.
#
# So flip it LOCALLY for a trial and revert before committing.
