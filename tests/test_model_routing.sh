#!/bin/sh
# test_model_routing.sh — E17-F01 per-role model selection.
#
# Covers R4–R23 and R26: tier resolution, `inherit` ⇒ key omission, the built-in
# floating-alias table, pin override + the OpenCode `provider/model` guard, unknown-tier
# tolerance, per-front-end stamping (claude / antigravity / opencode / gemini / codex),
# conditional creation of the two new trees, selection gating, idempotent re-stamping, the
# opencode.json re-stamp rules, determinism, and both halves of the BR6 seam — deselection
# preserves a user-edited artifact (R23) while a re-install regenerates one (R26).
#
# Zero dependencies; self-cleaning temp dir. R1–R3, R11, R12, R24 and R25 (the
# installer-wiring half) live in tests/test_install.sh.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
trap 'rm -rf "$T"' EXIT

# Sandbox CODEX_HOME for the WHOLE suite so legacy-migration checks can never touch the
# developer's real ~/.codex; each target below also gets its own per-run CODEX_HOME so
# the "project-local, never global" assertion (R16) is crisp.
export CODEX_HOME="$T/codex-home"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

ALL=claude,gemini,opencode,antigravity,codex
ROLES="orchestrator architect builder reviewer scout doc-critic"

# mk <name> — make a target dir under $T and print its path.
mk() { _d="$T/$1"; mkdir -p "$_d"; printf '%s\n' "$_d"; }

# cfg <target> — path of that target's config.
cfg() { printf '%s\n' "$1/.harness/harness.config.yaml"; }

# set_tier <target> <role> <tier> — rewrite one `models.<role>` line in place.
set_tier() {
  _c="$(cfg "$1")"
  sed "s/^  $2: .*/  $2: $3/" "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  grep -q "^  $2: $3\$" "$_c" || fail "setup: could not set models.$2 = $3"
}

# set_pin <target> <front-end> <tier> <value> — uncomment/insert a pin line.
set_pin() {
  _c="$(cfg "$1")"
  if grep -q "^  # pin\.$2\.$3: " "$_c"; then
    sed "s|^  # pin\.$2\.$3: .*|  pin.$2.$3: \"$4\"|" "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  else
    awk -v line="  pin.$2.$3: \"$4\"" '
      { print }
      !done && /^models:[[:space:]]*(#.*)?$/ { print line; done=1 }
    ' "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  fi
  grep -q "^  pin\.$2\.$3: " "$_c" || fail "setup: could not set models.pin.$2.$3"
}

# fmode <path> — the permission string (`-rw-r--r--`) of <path>. `cut -c1-10` drops the
# trailing `@`/`+` macOS appends for xattrs/ACLs. Used instead of `stat`, whose flags are
# not portable between BSD and GNU.
fmode() { ls -ld "$1" | cut -c1-10; }

# run <target> <agents-csv> — install, asserting exit 0, discarding all output.
run() {
  CODEX_HOME="$1/ch" sh "$SRC/harness-install.sh" --agents="$2" "$1" >/dev/null 2>&1 \
    || fail "install into $1 with --agents=$2 exited non-zero"
}

# run_err <target> <agents-csv> — install, print STDERR only, assert exit 0.
run_err() {
  _e="$(CODEX_HOME="$1/ch" sh "$SRC/harness-install.sh" --agents="$2" "$1" 2>&1 >/dev/null)" \
    || fail "install into $1 with --agents=$2 exited non-zero (stderr: $_e)"
  printf '%s\n' "$_e"
}

# ── R4: tier resolution order role → default → inherit ────────────────────────────
test_tier_resolution_order() {
  _t="$(mk r4)"; run "$_t" claude
  # (a) explicit role wins
  set_tier "$_t" architect reasoning
  # (b) default covers a role left on... an explicit inherit is still an explicit value,
  #     so blank the role line entirely to exercise the default fallback.
  _c="$(cfg "$_t")"
  sed '/^  reviewer: /d' "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  sed 's/^  default: .*/  default: cheap/' "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  run "$_t" claude
  [ "$(sed -n 's/^model: //p' "$_t/.claude/agents/architect.md")" = "opus" ] \
    || fail "R4: models.<role> did not win over models.default"
  [ "$(sed -n 's/^model: //p' "$_t/.claude/agents/reviewer.md")" = "haiku" ] \
    || fail "R4: a role with no entry did not fall back to models.default"
  # (c) neither present ⇒ inherit ⇒ omission
  _t2="$(mk r4b)"; run "$_t2" claude
  _c2="$(cfg "$_t2")"
  sed -e '/^  default: /d' -e '/^  scout: /d' "$_c2" > "$_c2.t" && mv "$_c2.t" "$_c2"
  run "$_t2" claude
  grep -q '^model:' "$_t2/.claude/agents/scout.md" \
    && fail "R4: with no role entry and no default the role must resolve to inherit (no key)"
  return 0
}

# ── R5: `inherit` is never written as a literal value ────────────────────────────
test_inherit_is_omission() {
  _t="$(mk r5)"; run "$_t" "$ALL"
  set_tier "$_t" architect reasoning     # a mix of resolved and inherit roles
  set_tier "$_t" scout cheap
  set_pin "$_t" opencode cheap "openai/gpt-5-mini"
  set_pin "$_t" codex cheap "gpt-5-mini"
  run "$_t" "$ALL"
  # Roles left on inherit carry NO key at all, on every front-end.
  grep -q '^model:' "$_t/.claude/agents/builder.md"  && fail "R5: inherit role got a model: key (claude)"
  grep -q '^model:' "$_t/.agents/agents/builder.md"  && fail "R5: inherit role got a model: key (antigravity)"
  grep -q '^model:' "$_t/.gemini/agents/builder.md"  && fail "R5: inherit role got a model: key (gemini)"
  grep -q '^model = ' "$_t/.codex/agents/builder.toml" && fail "R5: inherit role got a model key (codex)"
  grep -q '"builder":.*"model"' "$_t/opencode.json"  && fail "R5: inherit role got a model member (opencode)"
  # The literal string `inherit` appears in NO generated agent definition. Scope: the
  # artifacts this feature writes. The `.harness/` body is a VERBATIM copy of the source
  # (config, docs, specs, role bodies, tools, init.sh, manifest prose) and legitimately
  # uses the word in prose — copying is not generating, so it is out of scope here.
  _hits="$(grep -rl 'inherit' \
      "$_t/.claude/agents" "$_t/.agents/agents" "$_t/.gemini/agents" "$_t/.codex/agents" \
      "$_t/opencode.json" 2>/dev/null || true)"
  [ -z "$_hits" ] || fail "R5: the literal 'inherit' leaked into generated artifacts: $_hits"

  # The PIN path is the other way `inherit` can reach an artifact: a pin is otherwise
  # written VERBATIM, so `pin.<front-end>.<tier>: "inherit"` — an easy misreading of the
  # documented tier vocabulary — would emit `model: inherit` / `model = "inherit"`.
  # R5 is absolute, so a pin of `inherit` must compile to the SAME omission the inherit
  # TIER does (not to the built-in alias, and not to the literal). Exercised on ALL FIVE
  # front-ends at once: `builder` is on a tier whose pin is `inherit` everywhere, while
  # `scout` carries a real value so the conditional .gemini/ and .codex/ trees exist and
  # the builder artifacts are actually there to inspect.
  _p="$(mk r5pin)"; run "$_p" "$ALL"
  set_tier "$_p" builder reasoning
  for _fe in claude antigravity gemini codex opencode; do
    set_pin "$_p" "$_fe" reasoning "inherit"
  done
  set_tier "$_p" scout cheap
  set_pin "$_p" codex cheap "gpt-5-mini"
  set_pin "$_p" opencode cheap "openai/gpt-5-mini"
  _pe="$(run_err "$_p" "$ALL")"           # also asserts exit 0
  # The pinned-to-`inherit` role carries NO model key anywhere. (`opus`/`pro` would mean
  # the guard fell through to the alias instead of omitting.)
  grep -q '^model:'   "$_p/.claude/agents/builder.md"    && fail "R5pin: a pin of 'inherit' produced a model: key (claude)"
  grep -q '^model:'   "$_p/.agents/agents/builder.md"    && fail "R5pin: a pin of 'inherit' produced a model: key (antigravity)"
  grep -q '^model:'   "$_p/.gemini/agents/builder.md"    && fail "R5pin: a pin of 'inherit' produced a model: key (gemini)"
  grep -q '^model = ' "$_p/.codex/agents/builder.toml"   && fail "R5pin: a pin of 'inherit' produced a model key (codex)"
  grep -q '"builder":.*"model"' "$_p/opencode.json"      && fail "R5pin: a pin of 'inherit' produced a model member (opencode)"
  # …and the role with a real value still resolves, so this is omission, not a dead run.
  grep -q '^model: haiku' "$_p/.claude/agents/scout.md" \
    || fail "R5pin: setup — scout should still resolve normally"
  grep -q '^model = "gpt-5-mini"' "$_p/.codex/agents/scout.toml" \
    || fail "R5pin: setup — the codex scout pin should still resolve"
  # No literal `inherit` anywhere in the generated artifacts, and the drop is diagnosed.
  _phits="$(grep -rl 'inherit' \
      "$_p/.claude/agents" "$_p/.agents/agents" "$_p/.gemini/agents" "$_p/.codex/agents" \
      "$_p/opencode.json" 2>/dev/null || true)"
  [ -z "$_phits" ] || fail "R5pin: the literal 'inherit' leaked in via a pin: $_phits"
  printf '%s\n' "$_pe" | grep -q "is a tier name, not a model id" \
    || fail "R5pin: a pin of 'inherit' was dropped silently — no advisory on stderr"
  return 0
}

# ── R6: built-in floating aliases; no harness-frozen model id ────────────────────
test_builtin_tier_aliases() {
  _t="$(mk r6)"; run "$_t" claude,gemini,antigravity
  set_tier "$_t" architect reasoning
  set_tier "$_t" builder standard
  set_tier "$_t" scout cheap
  run "$_t" claude,gemini,antigravity
  _cl() { sed -n 's/^model: //p' "$_t/.claude/agents/$1.md"; }
  _ag() { sed -n 's/^model: //p' "$_t/.agents/agents/$1.md"; }
  _gm() { sed -n 's/^model: //p' "$_t/.gemini/agents/$1.md"; }
  [ "$(_cl architect)" = "opus" ]   || fail "R6: claude reasoning != opus (got '$(_cl architect)')"
  [ "$(_cl builder)"   = "sonnet" ] || fail "R6: claude standard != sonnet (got '$(_cl builder)')"
  [ "$(_cl scout)"     = "haiku" ]  || fail "R6: claude cheap != haiku (got '$(_cl scout)')"
  [ "$(_ag architect)" = "pro" ]    || fail "R6: antigravity reasoning != pro"
  [ "$(_ag builder)"   = "pro" ]    || fail "R6: antigravity standard != pro"
  [ "$(_ag scout)"     = "flash" ]  || fail "R6: antigravity cheap != flash"
  [ "$(_gm architect)" = "pro" ]    || fail "R6: gemini reasoning != pro"
  [ "$(_gm scout)"     = "flash" ]  || fail "R6: gemini cheap != flash"
  # No built-in default may be a version-pinned id (any digit in the emitted alias).
  _frozen="$(sed -n '/^model_alias()/,/^}/p' "$SRC/harness-install.sh" | grep -E "printf '[a-z-]*[0-9]" || true)"
  [ -z "$_frozen" ] || fail "R6: the built-in tier table ships a version-pinned model id: $_frozen"
  return 0
}

# ── R7: unpinned tier on codex/opencode omits the key + ONE info line ────────────
test_unpinned_codex_opencode_omits() {
  _t="$(mk r7)"; run "$_t" "$ALL"
  # every role on `cheap` ⇒ six resolutions per front-end, one advisory line each
  for _r in $ROLES; do set_tier "$_t" "$_r" cheap; done
  _e="$(run_err "$_t" "$ALL")"
  printf '%s\n' "$_e" | grep -q 'pin.codex.cheap'    || fail "R7: no advisory naming models.pin.codex.cheap"
  printf '%s\n' "$_e" | grep -q 'pin.opencode.cheap' || fail "R7: no advisory naming models.pin.opencode.cheap"
  [ "$(printf '%s\n' "$_e" | grep -c 'pin\.codex\.cheap')" = "1" ] \
    || fail "R7: the codex advisory was not de-duplicated to one line per (front-end, tier)"
  [ "$(printf '%s\n' "$_e" | grep -c 'pin\.opencode\.cheap')" = "1" ] \
    || fail "R7: the opencode advisory was not de-duplicated to one line per (front-end, tier)"
  grep -q '"model"' "$_t/opencode.json" && fail "R7: an unpinned tier stamped a model into opencode.json"
  for _r in $ROLES; do
    [ -f "$_t/.codex/agents/$_r.toml" ] || fail "R6/R7: unpinned Codex omitted registered role $_r"
    grep -q '^model = ' "$_t/.codex/agents/$_r.toml" \
      && fail "R7: unpinned Codex role $_r gained a model key"
  done
  # claude/gemini/antigravity DO resolve on the same config (they have aliases).
  grep -q '^model: haiku' "$_t/.claude/agents/scout.md" || fail "R7: claude did not resolve while codex/opencode were unpinned"
  return 0
}

# ── R8: a pin overrides the built-in alias and is written verbatim ───────────────
test_pin_overrides_verbatim() {
  _t="$(mk r8)"; run "$_t" "$ALL"
  set_tier "$_t" architect reasoning
  set_tier "$_t" scout cheap
  set_pin "$_t" claude reasoning "claude-opus-4-1-20250805"
  set_pin "$_t" opencode cheap  "anthropic/claude-haiku-4-5"
  set_pin "$_t" codex cheap     "gpt-5-mini"
  run "$_t" "$ALL"
  [ "$(sed -n 's/^model: //p' "$_t/.claude/agents/architect.md")" = "claude-opus-4-1-20250805" ] \
    || fail "R8: the claude pin did not override the built-in 'opus' alias"
  grep -q '"scout":.*"model": "anthropic/claude-haiku-4-5"' "$_t/opencode.json" \
    || fail "R8: the opencode pin was not written verbatim into agent.scout"
  grep -q '^model = "gpt-5-mini"$' "$_t/.codex/agents/scout.toml" \
    || fail "R8: the codex pin was not written verbatim into .codex/agents/scout.toml"
  # an unpinned tier on the SAME front-end still uses the built-in alias
  [ "$(sed -n 's/^model: //p' "$_t/.claude/agents/scout.md")" = "haiku" ] \
    || fail "R8: pinning one tier must not disturb another tier's built-in alias"
  return 0
}

# ── R9: unknown tier ⇒ stderr warning, resolves as inherit, exit 0 ───────────────
test_unknown_tier_warns_and_inherits() {
  _t="$(mk r9)"; run "$_t" claude
  set_tier "$_t" builder "turbo-9000"
  _e="$(run_err "$_t" claude)"
  printf '%s\n' "$_e" | grep -q 'builder'    || fail "R9: the warning does not name the role"
  printf '%s\n' "$_e" | grep -q 'turbo-9000' || fail "R9: the warning does not name the unrecognized tier"
  grep -q '^model:' "$_t/.claude/agents/builder.md" \
    && fail "R9: an unrecognized tier must resolve as inherit (no model key)"
  [ -f "$_t/.claude/agents/builder.md" ] || fail "R9: the install did not complete"
  return 0
}

# ── R10: an opencode pin without `/` is warned about and never written ───────────
test_opencode_pin_format_guard() {
  _t="$(mk r10)"; run "$_t" opencode
  set_tier "$_t" builder standard
  set_pin "$_t" opencode standard "sonnet-only-no-provider"
  _e="$(run_err "$_t" opencode)"
  printf '%s\n' "$_e" | grep -q 'provider/model' \
    || fail "R10: no warning about the invalid provider/model form"
  grep -q '"model"' "$_t/opencode.json" \
    && fail "R10: an invalid opencode pin must not stamp any model key"
  grep -q 'sonnet-only-no-provider' "$_t/opencode.json" \
    && fail "R10: the invalid pin value leaked into opencode.json"
  return 0
}

# ── R13: antigravity `.agents/agents/<role>.md` frontmatter ──────────────────────
test_antigravity_model_frontmatter() {
  _t="$(mk r13)"; run "$_t" antigravity
  set_tier "$_t" scout cheap
  run "$_t" antigravity
  _f="$_t/.agents/agents/scout.md"
  grep -q '^description: ' "$_f"        || fail "R13: scout persona lost its description: key"
  grep -q '^model: flash$' "$_f"        || fail "R13: scout persona carries no model: flash key"
  [ "$(grep -c '^model:' "$_f")" = "1" ] || fail "R13: scout persona accumulated more than one model: key"
  grep -q '^model:' "$_t/.agents/agents/builder.md" \
    && fail "R13: a role on inherit must carry no model: key"
  return 0
}

# ── R14: opencode `agent.<role>` carries a "model" member ────────────────────────
test_opencode_json_model_member() {
  _t="$(mk r14)"; run "$_t" opencode
  set_tier "$_t" builder standard
  set_pin "$_t" opencode standard "anthropic/claude-sonnet-4-5"
  run "$_t" opencode
  grep -q '"builder":.*"model": "anthropic/claude-sonnet-4-5".*"prompt"' "$_t/opencode.json" \
    || fail "R14: agent.builder has no \"model\" member"
  grep -q '"scout":.*"model"' "$_t/opencode.json" \
    && fail "R14: a role on inherit got a \"model\" member"
  # still valid JSON-ish: exactly one model member for the one configured role
  [ "$(grep -c '"model":' "$_t/opencode.json")" = "1" ] \
    || fail "R14: expected exactly one \"model\" member"
  return 0
}

# ── R15: gemini per-role files, all six roles, pointer body ──────────────────────
test_gemini_agent_files() {
  _t="$(mk r15)"; run "$_t" gemini
  set_tier "$_t" architect reasoning
  run "$_t" gemini
  for _r in $ROLES; do
    [ -f "$_t/.gemini/agents/$_r.md" ] || fail "R15: .gemini/agents/$_r.md not created"
    grep -q "^name: $_r\$" "$_t/.gemini/agents/$_r.md"  || fail "R15: $_r.md has no name: key"
    grep -q '^description: ' "$_t/.gemini/agents/$_r.md" || fail "R15: $_r.md has no description: key"
    grep -qF ".harness/agents/$_r.md" "$_t/.gemini/agents/$_r.md" \
      || fail "R15: $_r.md does not point at the canonical .harness/agents/$_r.md"
  done
  grep -q '^model: pro$' "$_t/.gemini/agents/architect.md" \
    || fail "R15: the resolved role carries no model: key"
  grep -q '^model:' "$_t/.gemini/agents/builder.md" \
    && fail "R15: an inherit role must carry no model: key"
  # the pointer body must not duplicate the canonical role body
  [ "$(wc -l < "$_t/.gemini/agents/architect.md")" -lt 30 ] \
    || fail "R15: the gemini agent file looks like a duplicated role body, not a pointer"
  return 0
}

# ── R16: codex per-role files are PROJECT-LOCAL, never in $CODEX_HOME ────────────
test_codex_agent_files_project_local() {
  _t="$(mk r16)"; run "$_t" codex
  set_tier "$_t" builder standard
  set_pin "$_t" codex standard "gpt-5-codex"
  run "$_t" codex
  for _r in $ROLES; do
    [ -f "$_t/.codex/agents/$_r.toml" ] || fail "R16: .codex/agents/$_r.toml not created"
    # Codex rejects an agent role file that is missing any of this trio ("must define
    # `developer_instructions`") and then silently ignores the model stamp. Assert the
    # exact key names statically — the suite must not depend on the `codex` CLI.
    grep -q "^name = \"$_r\"\$" "$_t/.codex/agents/$_r.toml" \
      || fail "R16: $_r.toml does not define name"
    grep -q '^description = "..*"$' "$_t/.codex/agents/$_r.toml" \
      || fail "R16: $_r.toml does not define description"
    grep -q '^developer_instructions = "..*"$' "$_t/.codex/agents/$_r.toml" \
      || fail "R16: $_r.toml does not define developer_instructions — Codex rejects the file and the model stamp never applies"
    grep -q '^instructions = ' "$_t/.codex/agents/$_r.toml" \
      && fail "R16: $_r.toml uses the unsupported key 'instructions'"
    grep -qF ".harness/agents/$_r.md" "$_t/.codex/agents/$_r.toml" \
      || fail "R16: $_r.toml does not point at the canonical .harness/agents/$_r.md"
  done
  grep -q '^model = "gpt-5-codex"$' "$_t/.codex/agents/builder.toml" \
    || fail "R16: builder.toml carries no model = key"
  grep -q '^model = ' "$_t/.codex/agents/scout.toml" \
    && fail "R16: an inherit role must carry no model key"
  # The operator's GLOBAL codex config must be untouched by model routing.
  [ -d "$_t/ch/agents" ] && fail "R16: the installer wrote a per-role agent file into \$CODEX_HOME"
  [ -d "$CODEX_HOME/agents" ] && fail "R16: the installer wrote into the suite-level \$CODEX_HOME/agents"
  [ -d "$_t/ch/prompts" ] && fail "R4: model routing created the retired global Codex prompt surface"
  return 0
}

# ── E23-F01 review: selected Codex preserves foreign/edited standard role files ──
test_codex_selected_preserves_foreign_and_edited() {
  _t="$(mk codex-owned)"
  mkdir -p "$_t/.codex/agents"
  printf 'foreign orchestrator role\n' > "$_t/.codex/agents/orchestrator.toml"
  cp "$_t/.codex/agents/orchestrator.toml" "$_t/foreign-role.ref"
  _e="$(run_err "$_t" codex)"
  cmp -s "$_t/foreign-role.ref" "$_t/.codex/agents/orchestrator.toml" \
    || fail "E23 review: selected Codex install overwrote a foreign orchestrator role"
  [ -e "$_t/.harness/.model-agents/codex/orchestrator.toml" ] \
    && fail "E23 review: installer claimed a last-written stamp for a foreign role"
  printf '%s\n' "$_e" | grep -qF '.codex/agents/orchestrator.toml' \
    || fail "E23 review: selected foreign role preservation was not diagnosed"
  [ "$(find "$_t/.codex/agents" -type f -name '*.toml' | wc -l | tr -d ' ')" = "6" ] \
    || fail "E23 review: preserving one foreign role did not leave exactly six registrations"

  # A role the harness DID write has a last-written stamp. Once edited, a selected
  # re-install must leave it byte-for-byte untouched even when routing changes.
  _role="$_t/.codex/agents/builder.toml"
  _stamp="$_t/.harness/.model-agents/codex/builder.toml"
  [ -f "$_stamp" ] && cmp -s "$_role" "$_stamp" \
    || fail "E23 review: harness-owned builder role has no matching last-written stamp"
  printf '# user edit\n' >> "$_role"
  cp "$_role" "$_t/edited-role.ref"
  set_tier "$_t" builder cheap
  set_pin "$_t" codex cheap "gpt-5-mini"
  _e2="$(run_err "$_t" codex)"
  cmp -s "$_t/edited-role.ref" "$_role" \
    || fail "E23 review: selected re-install overwrote an edited Codex role"
  grep -q '^model = ' "$_role" \
    && fail "E23 review setup: edited pre-routing role unexpectedly gained the new model"
  printf '%s\n' "$_e2" | grep -qF '.codex/agents/builder.toml' \
    || fail "E23 review: selected edited role preservation was not diagnosed"
  return 0
}

# ── E23-F01 review: Codex role ownership never follows destination symlinks ─────
test_codex_rejects_symlinked_role_destinations() {
  # File symlink: after a legitimate install, redirect one stamped role outside the
  # target. A model change makes the newly generated bytes differ, proving a selected
  # re-install neither follows the link nor updates its stale ownership stamp.
  _f="$(mk codex-role-file-link)"; run "$_f" codex
  _fext="$T/codex-role-file.external"
  mv "$_f/.codex/agents/builder.toml" "$_fext"
  cp "$_fext" "$_fext.ref"
  ln -s "$_fext" "$_f/.codex/agents/builder.toml"
  set_tier "$_f" builder standard
  set_pin "$_f" codex standard "gpt-5-codex"
  run "$_f" codex
  [ -L "$_f/.codex/agents/builder.toml" ] \
    || fail "E23 symlink: selected install replaced a symlinked Codex role file"
  cmp -s "$_fext.ref" "$_fext" \
    || fail "E23 symlink: model re-route overwrote an external role-file target"
  grep -q '^model = ' "$_fext" \
    && fail "E23 symlink: generated model bytes reached an external role-file target"
  [ -e "$_f/.harness/.model-agents/codex/builder.toml" ] \
    && fail "E23 symlink: rejected role-file symlink retained an ownership stamp"

  # Directory symlink: redirect the whole role directory after a legitimate install.
  # Changing a second model route forces every old ownership comparison through the
  # symlink unless the writable directory component is rejected first.
  _d="$(mk codex-role-dir-link)"; run "$_d" codex
  _dext="$T/codex-role-dir.external"
  mv "$_d/.codex/agents" "$_dext"
  cp -R "$_dext" "$_dext.ref"
  ln -s "$_dext" "$_d/.codex/agents"
  set_tier "$_d" architect reasoning
  set_pin "$_d" codex reasoning "gpt-5"
  run "$_d" codex
  [ -L "$_d/.codex/agents" ] \
    || fail "E23 symlink: selected install replaced a symlinked Codex role directory"
  diff -r "$_dext.ref" "$_dext" >/dev/null \
    || fail "E23 symlink: model re-route changed an external role-directory target"
  [ -e "$_d/.harness/.model-agents/codex" ] \
    && fail "E23 symlink: rejected role-directory symlink retained ownership stamps"

  # Reclamation applies the same rejection boundary: links and their external targets
  # survive deselection byte-for-byte.
  run "$_f" claude
  [ -L "$_f/.codex/agents/builder.toml" ] \
    || fail "E23 symlink: deselection removed a symlinked Codex role file"
  cmp -s "$_fext.ref" "$_fext" \
    || fail "E23 symlink: deselection changed an external role-file target"
  run "$_d" claude
  [ -L "$_d/.codex/agents" ] \
    || fail "E23 symlink: deselection removed a symlinked Codex role directory"
  diff -r "$_dext.ref" "$_dext" >/dev/null \
    || fail "E23 symlink: deselection changed an external role-directory target"
  return 0
}

# ── R17: Gemini remains conditional; selected Codex roles are always registered ──
test_new_trees_conditional() {
  # (a) everything on inherit
  _t="$(mk r17a)"; run "$_t" gemini,codex
  [ -d "$_t/.gemini/agents" ] && fail "R17: all-inherit created .gemini/agents/"
  [ "$(find "$_t/.codex/agents" -type f -name '*.toml' | wc -l | tr -d ' ')" = "6" ] \
    || fail "R6: all-inherit Codex did not create exactly six role TOMLs"
  grep -q '^model = ' "$_t/.codex/agents/"*.toml \
    && fail "R7: all-inherit Codex role gained a model key"
  # (b) a real tier without a Codex pin remains model-less, while Gemini resolves.
  _t2="$(mk r17b)"; run "$_t2" gemini,codex
  set_tier "$_t2" architect reasoning
  run "$_t2" gemini,codex
  [ -d "$_t2/.gemini/agents" ] || fail "R17: a resolvable gemini tier must create .gemini/agents/"
  [ "$(find "$_t2/.codex/agents" -type f -name '*.toml' | wc -l | tr -d ' ')" = "6" ] \
    || fail "R6: unpinned Codex did not retain exactly six role TOMLs"
  grep -q '^model = ' "$_t2/.codex/agents/"*.toml \
    && fail "R7: unpinned Codex tier stamped a model key"
  return 0
}

# ── R18: an unselected front-end is never stamped ────────────────────────────────
test_selection_gating() {
  _t="$(mk r18)"; run "$_t" claude
  for _r in $ROLES; do set_tier "$_t" "$_r" reasoning; done
  set_pin "$_t" opencode reasoning "anthropic/claude-opus-4-5"
  set_pin "$_t" codex reasoning "gpt-5"
  run "$_t" claude
  grep -q '^model: opus$' "$_t/.claude/agents/builder.md" || fail "R18: the SELECTED front-end was not stamped"
  [ -d "$_t/.gemini/agents" ]   && fail "R18: unselected gemini was stamped"
  [ -d "$_t/.codex/agents" ]    && fail "R18: unselected codex was stamped"
  [ -f "$_t/opencode.json" ]    && fail "R18: unselected opencode was stamped"
  [ -d "$_t/.agents/agents" ]   && fail "R18: unselected antigravity was stamped"
  [ -f "$_t/.harness/.opencode.stamp" ] && fail "R18: unselected opencode left a stamp file"
  return 0
}

# ── R19: a config change re-stamps every artifact, one model key per role ────────
test_restamp_after_config_change() {
  _t="$(mk r19)"; run "$_t" "$ALL"
  set_tier "$_t" builder cheap
  set_pin "$_t" opencode cheap "anthropic/claude-haiku-4-5"
  set_pin "$_t" codex cheap "gpt-5-mini"
  run "$_t" "$ALL"
  [ "$(sed -n 's/^model: //p' "$_t/.claude/agents/builder.md")" = "haiku" ] || fail "R19: claude not stamped on run 1"
  # now change the tier and re-run
  set_tier "$_t" builder reasoning
  set_pin "$_t" opencode reasoning "anthropic/claude-opus-4-5"
  set_pin "$_t" codex reasoning "gpt-5"
  run "$_t" "$ALL"
  [ "$(sed -n 's/^model: //p' "$_t/.claude/agents/builder.md")" = "opus" ] \
    || fail "R19: .claude/agents/builder.md was not re-stamped to the new value"
  [ "$(grep -c '^model:' "$_t/.claude/agents/builder.md")" = "1" ] \
    || fail "R19: .claude/agents/builder.md accumulated a second model key"
  [ "$(sed -n 's/^model: //p' "$_t/.agents/agents/builder.md")" = "pro" ] \
    || fail "R19: .agents/agents/builder.md was not re-stamped"
  [ "$(grep -c '^model:' "$_t/.agents/agents/builder.md")" = "1" ] \
    || fail "R19: .agents/agents/builder.md accumulated a second model key"
  [ "$(sed -n 's/^model: //p' "$_t/.gemini/agents/builder.md")" = "pro" ] \
    || fail "R19: .gemini/agents/builder.md was not re-stamped"
  [ "$(grep -c '^model:' "$_t/.gemini/agents/builder.md")" = "1" ] \
    || fail "R19: .gemini/agents/builder.md accumulated a second model key"
  grep -q '^model = "gpt-5"$' "$_t/.codex/agents/builder.toml" \
    || fail "R19: .codex/agents/builder.toml was not re-stamped"
  [ "$(grep -c '^model = ' "$_t/.codex/agents/builder.toml")" = "1" ] \
    || fail "R19: .codex/agents/builder.toml accumulated a second model key"
  grep -q '"builder":.*"model": "anthropic/claude-opus-4-5"' "$_t/opencode.json" \
    || fail "R19: opencode.json was not re-stamped"
  [ "$(grep -c '"model":' "$_t/opencode.json")" = "1" ] \
    || fail "R19: opencode.json accumulated a second model member"
  return 0
}

# ── R26: historical front-ends regenerate edits; Codex requires ownership ──────────
# BR6 has two paths with two different rules, and R23 only pins one of them. RECLAMATION
# (deselect) never deletes a user-edited file; REGENERATION (re-install) always overwrites
# one for the historical front-ends. Codex's shared project-local namespace now requires
# a matching last-written stamp before replacement, so an edited Codex role is preserved.
#
# The config is byte-UNCHANGED across the re-run on purpose: with a changed tier this
# would just be R19 again and would prove nothing about an untouched config.
# `opencode.json` is deliberately absent — it is a SHARED file and R20(c) requires the
# opposite of R26 for it (edited ⇒ untouched + warning).
test_restamp_overwrites_user_edits() {
  _t="$(mk r26)"; run "$_t" "$ALL"
  set_tier "$_t" scout cheap
  set_pin "$_t" codex cheap "gpt-5-mini"
  run "$_t" "$ALL"

  _cl="$_t/.claude/agents/scout.md"        # pre-existing generated glue — the precedent
  _ag="$_t/.agents/agents/scout.md"        # pre-existing generated glue — the precedent
  _gm="$_t/.gemini/agents/scout.md"        # new in E17-F01
  _cx="$_t/.codex/agents/scout.toml"       # new in E17-F01
  for _f in "$_cl" "$_ag" "$_gm" "$_cx"; do
    [ -f "$_f" ] || fail "R26: setup — $_f was not stamped"
  done

  # Keep a pristine reference of each file plus the config, then plant the same edit in
  # all four. The reference is what "regenerated from the current configuration" means.
  _ref="$T/r26-ref"; rm -rf "$_ref"; mkdir -p "$_ref"
  cp "$_cl" "$_ref/claude.md"
  cp "$_ag" "$_ref/antigravity.md"
  cp "$_gm" "$_ref/gemini.md"
  cp "$_cx" "$_ref/codex.toml"
  cp "$(cfg "$_t")" "$_ref/harness.config.yaml"
  for _f in "$_cl" "$_ag" "$_gm" "$_cx"; do
    printf 'zzz-user-edit\n' >> "$_f"
  done

  run "$_t" "$ALL"

  # The premise of this test: no set_tier, no set_pin, so the installer saw the SAME
  # config bytes it saw on the previous run. If this ever fails the test has silently
  # become a duplicate of R19.
  cmp -s "$_ref/harness.config.yaml" "$(cfg "$_t")" \
    || fail "R26: the config changed across the re-run — this test must exercise an UNCHANGED config (R19 owns the changed case)"

  # (a) Gemini retains its regeneration contract; Codex preserves the edit.
  grep -q 'zzz-user-edit' "$_gm" && fail "R26: an edited .gemini/agents/scout.md was not regenerated on re-install"
  grep -q 'zzz-user-edit' "$_cx" || fail "E23 review: an edited .codex/agents/scout.toml was overwritten on selected re-install"
  # (b) …and from the two PRE-EXISTING ones, the contract R26 says it matches. Asserting
  #     this here is what makes "matching the pre-existing generated-glue contract"
  #     verified rather than merely claimed in prose.
  grep -q 'zzz-user-edit' "$_cl" && fail "R26: an edited .claude/agents/scout.md was not regenerated (the precedent R26 cites no longer holds)"
  grep -q 'zzz-user-edit' "$_ag" && fail "R26: an edited .agents/agents/scout.md was not regenerated (the precedent R26 cites no longer holds)"

  # (c) the regenerated body is the NORMAL one — the stamp is intact and single, not a
  #     truncated or doubled rewrite.
  [ "$(grep -c '^model:' "$_gm")" = "1" ] || fail "R26: .gemini/agents/scout.md does not carry exactly one model: key after regeneration"
  [ "$(grep -c '^model = ' "$_cx")" = "1" ] || fail "E23 review: preserved .codex/agents/scout.toml lost its model key"
  [ "$(grep -c '^model:' "$_cl")" = "1" ] || fail "R26: .claude/agents/scout.md does not carry exactly one model: key after regeneration"
  [ "$(grep -c '^model:' "$_ag")" = "1" ] || fail "R26: .agents/agents/scout.md does not carry exactly one model: key after regeneration"
  grep -q '^model: flash$' "$_gm"            || fail "R26: .gemini/agents/scout.md lost its resolved value"
  grep -q '^model = "gpt-5-mini"$' "$_cx"    || fail "R26: .codex/agents/scout.toml lost its resolved value"
  grep -q '^model: haiku$' "$_cl"            || fail "R26: .claude/agents/scout.md lost its resolved value"
  grep -q '^model: flash$' "$_ag"            || fail "R26: .agents/agents/scout.md lost its resolved value"

  # (d) strongest form: each regenerated file is byte-identical to the pristine reference,
  #     i.e. the re-run reproduced the generator's output exactly (this is also what keeps
  #     deselection able to reclaim these files at all — R21).
  cmp -s "$_ref/gemini.md"      "$_gm" || fail "R26: the regenerated .gemini/agents/scout.md is not byte-identical to the pristine reference"
  cmp -s "$_ref/codex.toml"     "$_cx" && fail "E23 review: edited Codex role unexpectedly reverted to its pristine reference"
  cmp -s "$_ref/claude.md"      "$_cl" || fail "R26: the regenerated .claude/agents/scout.md is not byte-identical to the pristine reference"
  cmp -s "$_ref/antigravity.md" "$_ag" || fail "R26: the regenerated .agents/agents/scout.md is not byte-identical to the pristine reference"

  # (e) the OTHER half of BR6, in a separate target so both sides of the seam are visible
  #     in one place: the very same edit, on the DESELECT path, must SURVIVE with a
  #     warning. R23 unchanged — regeneration overwrites, reclamation does not delete.
  _b="$(mk r26b)"; run "$_b" "$ALL"
  set_tier "$_b" scout cheap
  set_pin "$_b" codex cheap "gpt-5-mini"
  run "$_b" "$ALL"
  [ -f "$_b/.gemini/agents/scout.md" ] || fail "R26b: setup — gemini artifact missing"
  printf 'zzz-user-edit\n' >> "$_b/.gemini/agents/scout.md"
  _e="$(run_err "$_b" claude)"
  [ -f "$_b/.gemini/agents/scout.md" ] \
    || fail "R26b: deselection deleted an EDITED .gemini/agents/scout.md — reclamation must not destroy a user edit (R23)"
  grep -qx 'zzz-user-edit' "$_b/.gemini/agents/scout.md" \
    || fail "R26b: the user edit did not survive deselection (R23)"
  printf '%s\n' "$_e" | grep -q '.gemini/agents/scout.md' \
    || fail "R26b: no warning naming the preserved file on deselect (R23)"
  return 0
}

# ── R20: the three opencode.json re-stamp cases ──────────────────────────────────
test_opencode_json_restamp_rules() {
  # (a) a pre-existing PRISTINE model-free body gains the model members
  _ta="$(mk r20a)"; run "$_ta" opencode
  grep -q '"model"' "$_ta/opencode.json" && fail "R20a: setup — the model-free body already has a model member"
  [ -f "$_ta/.harness/.opencode.stamp" ] && fail "R20a: a model-free body must leave no stamp file"
  set_tier "$_ta" builder standard
  set_pin "$_ta" opencode standard "anthropic/claude-sonnet-4-5"
  run "$_ta" opencode
  grep -q '"model": "anthropic/claude-sonnet-4-5"' "$_ta/opencode.json" \
    || fail "R20a: a pristine model-free opencode.json was not re-stamped"
  [ -f "$_ta/.harness/.opencode.stamp" ] || fail "R20a: no .opencode.stamp written after stamping a model"
  cmp -s "$_ta/opencode.json" "$_ta/.harness/.opencode.stamp" \
    || fail "R20a: .opencode.stamp is not a byte copy of the written opencode.json"

  # (b) with the stamp present and matching, a further config change re-stamps again
  set_pin "$_ta" opencode standard "anthropic/claude-opus-4-5"
  run "$_ta" opencode
  grep -q '"model": "anthropic/claude-opus-4-5"' "$_ta/opencode.json" \
    || fail "R20b: a stamped opencode.json was not re-stamped after a config change"
  cmp -s "$_ta/opencode.json" "$_ta/.harness/.opencode.stamp" \
    || fail "R20b: .opencode.stamp was not refreshed"

  # (c) an operator edit is left byte-identical, with a warning
  _tc="$(mk r20c)"; run "$_tc" opencode
  printf '\n// my own note\n' >> "$_tc/opencode.json"
  cp "$_tc/opencode.json" "$_tc/edited.json"
  set_tier "$_tc" builder standard
  set_pin "$_tc" opencode standard "anthropic/claude-sonnet-4-5"
  _e="$(run_err "$_tc" opencode)"
  cmp -s "$_tc/edited.json" "$_tc/opencode.json" \
    || fail "R20c: an edited opencode.json was modified by the installer"
  printf '%s\n' "$_e" | grep -q 'opencode.json' \
    || fail "R20c: no warning that model routing changes were not applied"
  return 0
}

# ── R20/R11 (file mode): opencode.json keeps the pre-feature permission bits ──────
# §6 builds the body in a mktemp file, which is mode 0600. `cp` to a NON-EXISTENT
# destination copies the SOURCE's permission bits, so installing with `cp` would silently
# ship a 0600 opencode.json on a fresh install where the pre-E17 `gen_opencode_json
# "$TARGET/opencode.json"` (a plain `>` redirect) produced 0666 & ~umask — and would make
# fresh targets diverge from upgraded ones, since `cp` onto an EXISTING file keeps that
# file's mode. `diff`/`cmp` compare content only and are blind to this, so R11's
# "behaviorally identical to the pre-feature installer" is asserted on mode directly.
# The expectation is a file this test creates with the same `>` redirect the pre-feature
# installer used, which makes the check umask-independent rather than freezing 0644.
test_opencode_json_file_mode() {
  _ref="$T/mode-ref"; rm -f "$_ref"; : > "$_ref"
  _want="$(fmode "$_ref")"

  # (a) fresh create with no models: block configured — the R11 baseline path
  _ta="$(mk r20m-a)"; run "$_ta" opencode
  [ "$(fmode "$_ta/opencode.json")" = "$_want" ] \
    || fail "R20mode: a fresh opencode.json is $(fmode "$_ta/opencode.json"), expected $_want (mktemp's 0600 leaked through a cp)"

  # (b) fresh create of a STAMPED body — same branch, models on
  _tb="$(mk r20m-b)"; run "$_tb" opencode
  rm -f "$_tb/opencode.json" "$_tb/.harness/.opencode.stamp"
  set_tier "$_tb" builder standard
  set_pin "$_tb" opencode standard "anthropic/claude-sonnet-4-5"
  run "$_tb" opencode
  grep -q '"model": "anthropic/claude-sonnet-4-5"' "$_tb/opencode.json" \
    || fail "R20mode: setup — the re-created opencode.json was not stamped"
  [ "$(fmode "$_tb/opencode.json")" = "$_want" ] \
    || fail "R20mode: a fresh STAMPED opencode.json is $(fmode "$_tb/opencode.json"), expected $_want"
  [ "$(fmode "$_tb/.harness/.opencode.stamp")" = "$_want" ] \
    || fail "R20mode: .opencode.stamp is $(fmode "$_tb/.harness/.opencode.stamp"), expected $_want"

  # (c) the pristine-regenerate branch must PRESERVE the operator's existing mode
  chmod 640 "$_tb/opencode.json"
  set_pin "$_tb" opencode standard "anthropic/claude-opus-4-5"
  run "$_tb" opencode
  grep -q '"model": "anthropic/claude-opus-4-5"' "$_tb/opencode.json" \
    || fail "R20mode: setup — the pristine re-stamp did not happen"
  [ "$(fmode "$_tb/opencode.json")" = "-rw-r-----" ] \
    || fail "R20mode: re-stamping changed the file's mode to $(fmode "$_tb/opencode.json"), expected -rw-r----- (preserved)"
  return 0
}

# ── R21: two runs with an unchanged config are byte-identical ────────────────────
test_stamping_is_deterministic() {
  _t="$(mk r21)"; run "$_t" "$ALL"
  set_tier "$_t" architect reasoning
  set_tier "$_t" builder standard
  set_tier "$_t" scout cheap
  set_pin "$_t" opencode standard "anthropic/claude-sonnet-4-5"
  set_pin "$_t" codex cheap "gpt-5-mini"
  run "$_t" "$ALL"
  _s="$T/r21-snap"; rm -rf "$_s"; mkdir -p "$_s"
  cp -R "$_t/.claude" "$_t/.agents" "$_t/.gemini" "$_t/.codex" "$_s/"
  cp "$_t/opencode.json" "$_t/.harness/.opencode.stamp" "$_s/"
  run "$_t" "$ALL"
  for _d in .claude .agents .gemini .codex; do
    diff -r "$_s/$_d" "$_t/$_d" >/dev/null || fail "R21: $_d/ is not byte-identical across two identical runs"
  done
  cmp -s "$_s/opencode.json" "$_t/opencode.json" || fail "R21: opencode.json is not byte-identical across two identical runs"
  cmp -s "$_s/.opencode.stamp" "$_t/.harness/.opencode.stamp" || fail "R21: .opencode.stamp is not stable"
  return 0
}

# ── R22: deselection reclaims every stamped artifact ─────────────────────────────
test_deselect_reclaims_stamped() {
  _t="$(mk r22)"; run "$_t" "$ALL"
  set_tier "$_t" architect reasoning
  set_tier "$_t" builder standard
  set_tier "$_t" scout cheap
  set_pin "$_t" opencode standard "anthropic/claude-sonnet-4-5"
  set_pin "$_t" codex cheap "gpt-5-mini"
  run "$_t" "$ALL"
  [ -f "$_t/.gemini/agents/scout.md" ]        || fail "R22: setup — gemini artifact missing"
  [ -f "$_t/.codex/agents/scout.toml" ]       || fail "R22: setup — codex artifact missing"
  [ -f "$_t/.harness/.opencode.stamp" ]       || fail "R22: setup — opencode stamp missing"
  run "$_t" claude
  [ -e "$_t/.gemini/agents" ]            && fail "R22: .gemini/agents/ left behind after deselect"
  [ -e "$_t/.gemini" ]                   && fail "R22: the harness-created .gemini/ dir left behind"
  [ -e "$_t/.codex/agents" ]             && fail "R22: .codex/agents/ left behind after deselect"
  [ -e "$_t/.codex" ]                    && fail "R22: the harness-created .codex/ dir left behind"
  [ -e "$_t/opencode.json" ]             && fail "R22: a stamped opencode.json was not reclaimed"
  [ -e "$_t/.harness/.opencode.stamp" ]  && fail "R22: .opencode.stamp was not removed with opencode.json"
  [ -e "$_t/.agents/agents" ]            && fail "R22: stamped antigravity personas left behind"
  [ -f "$_t/.claude/agents/architect.md" ] || fail "R22: the still-selected front-end lost its glue"
  return 0
}

# ── R23: an edited stamped artifact survives deselection, with a warning ─────────
test_deselect_preserves_user_edits() {
  _t="$(mk r23)"; run "$_t" "$ALL"
  set_tier "$_t" scout cheap
  set_pin "$_t" codex cheap "gpt-5-mini"
  run "$_t" "$ALL"
  [ -f "$_t/.gemini/agents/scout.md" ]  || fail "R23: setup — gemini artifact missing"
  [ -f "$_t/.codex/agents/scout.toml" ] || fail "R23: setup — codex artifact missing"
  printf 'x\n' >> "$_t/.gemini/agents/scout.md"
  printf '# mine\n' >> "$_t/.codex/agents/scout.toml"
  _e="$(run_err "$_t" claude)"
  [ -f "$_t/.gemini/agents/scout.md" ]  || fail "R23: an EDITED .gemini/agents/scout.md was deleted on deselect"
  grep -qx 'x' "$_t/.gemini/agents/scout.md" || fail "R23: the user edit was not preserved"
  [ -f "$_t/.codex/agents/scout.toml" ] || fail "R23: an EDITED .codex/agents/scout.toml was deleted on deselect"
  printf '%s\n' "$_e" | grep -q '.gemini/agents/scout.md' \
    || fail "R23: no warning naming the preserved gemini file"
  printf '%s\n' "$_e" | grep -q '.codex/agents/scout.toml' \
    || fail "R23: no warning naming the preserved codex file"
  # pristine siblings ARE reclaimed; the dirs survive only because a user file remains
  [ -f "$_t/.gemini/agents/builder.md" ]  && fail "R23: a pristine sibling was not reclaimed (gemini)"
  [ -f "$_t/.codex/agents/builder.toml" ] && fail "R23: a pristine sibling was not reclaimed (codex)"
  return 0
}

# ── R11/R17: every role back to `inherit` reconciles previously stamped models ──
test_return_to_inherit_reconciles() {
  # (a) Gemini remains conditional; Codex regenerates the same six model-less roles.
  _t="$(mk r11rec)"; run "$_t" gemini,codex
  set_tier "$_t" architect reasoning
  set_tier "$_t" scout cheap
  set_pin "$_t" codex cheap "gpt-5-mini"
  run "$_t" gemini,codex
  [ -f "$_t/.gemini/agents/architect.md" ] || fail "R11rec: setup — gemini artifact missing"
  [ -f "$_t/.codex/agents/scout.toml" ]    || fail "R11rec: setup — codex artifact missing"
  grep -q '^model: ' "$_t/.gemini/agents/architect.md" || fail "R11rec: setup — gemini model: key missing"
  grep -q '^model = ' "$_t/.codex/agents/scout.toml"   || fail "R11rec: setup — codex model key missing"
  # Now put EVERY role back on inherit — nothing resolves for either front-end.
  set_tier "$_t" architect inherit
  set_tier "$_t" scout inherit
  run "$_t" gemini,codex
  [ -e "$_t/.gemini/agents" ] && fail "R11rec: .gemini/agents/ survived a switch back to inherit"
  [ -e "$_t/.gemini" ]        && fail "R11rec: the harness-created .gemini/ dir survived"
  [ "$(find "$_t/.codex/agents" -type f -name '*.toml' | wc -l | tr -d ' ')" = "6" ] \
    || fail "R8: pin→inherit did not retain exactly six Codex roles"
  grep -q '^model = ' "$_t/.codex/agents/"*.toml \
    && fail "R8: pin→inherit left a Codex model key behind"
  # The still-selected front-ends keep the rest of their glue.
  [ -f "$_t/.agents/skills/sdd-next/SKILL.md" ] || fail "R8: pin→inherit removed Codex skills"

  # (b) Selected Codex roles update from current routing only while their live bytes
  # still match the last-written stamp. Edited Codex and Gemini roles are preserved.
  _u="$(mk r11rec_edit)"; run "$_u" gemini,codex
  set_tier "$_u" architect reasoning
  set_tier "$_u" scout cheap
  set_pin "$_u" codex cheap "gpt-5-mini"
  run "$_u" gemini,codex
  printf 'mine\n' >> "$_u/.gemini/agents/architect.md"
  printf '# mine\n' >> "$_u/.codex/agents/scout.toml"
  set_tier "$_u" architect inherit
  set_tier "$_u" scout inherit
  _e="$(run_err "$_u" gemini,codex)"
  [ -f "$_u/.gemini/agents/architect.md" ] \
    || fail "R11rec: an EDITED .gemini/agents/architect.md was deleted on the switch back to inherit"
  grep -qx 'mine' "$_u/.gemini/agents/architect.md" || fail "R11rec: the gemini user edit was not preserved"
  [ -f "$_u/.codex/agents/scout.toml" ] \
    || fail "R8: Codex scout role vanished on the switch back to inherit"
  grep -qx '# mine' "$_u/.codex/agents/scout.toml" \
    || fail "R8: selected Codex pin→inherit overwrote an edited role"
  grep -q '^model = "gpt-5-mini"$' "$_u/.codex/agents/scout.toml" \
    || fail "R8: preserved edited Codex role unexpectedly changed its prior routing"
  printf '%s\n' "$_e" | grep -q '.gemini/agents/architect.md' \
    || fail "R11rec: no warning naming the preserved gemini file"
  printf '%s\n' "$_e" | grep -q '.codex/agents/scout.toml' \
    || fail "R8: no warning naming the preserved edited Codex role"
  # Gemini pristine siblings are reclaimed; Codex siblings remain registered model-less.
  [ -f "$_u/.gemini/agents/builder.md" ]  && fail "R11rec: a pristine sibling was not reclaimed (gemini)"
  [ -f "$_u/.codex/agents/builder.toml" ] || fail "R8: Codex sibling role vanished on pin→inherit"

  # (c) R22 with the `models:` edit and the DESELECT in the SAME run: the on-disk files
  # came from the OLD config, so a freshly generated reference cannot match them. The
  # remembered bytes can — without them a pristine file would be misclassified as
  # user-edited and orphaned. (Codex r1 P2 #3654925555.)
  _d="$(mk r11rec_desel)"; run "$_d" gemini,codex
  set_tier "$_d" architect reasoning
  set_pin "$_d" codex reasoning "gpt-5"
  run "$_d" gemini,codex
  [ -f "$_d/.gemini/agents/architect.md" ] || fail "R11rec: setup — gemini artifact missing (c)"
  [ -f "$_d/.codex/agents/architect.toml" ] || fail "R11rec: setup — codex artifact missing (c)"
  set_tier "$_d" architect cheap          # config changes AND the front-ends go away
  run "$_d" claude
  [ -e "$_d/.gemini" ] && fail 'R11rec: a models: edit in the deselect run orphaned .gemini/'
  [ -e "$_d/.codex" ]  && fail 'R11rec: a models: edit in the deselect run orphaned .codex/'
  [ -e "$_d/.harness/.model-agents" ] && fail "R11rec: .model-agents/ outlived the artifacts it describes"
  return 0
}

test_tier_resolution_order
pass "tier resolves role → models.default → inherit (R4)"
test_inherit_is_omission
pass "inherit compiles to key omission on the tier AND the pin path; the literal string is never generated (R5)"
test_builtin_tier_aliases
pass "built-in floating aliases for claude/antigravity/gemini; no harness-frozen model id (R6)"
test_unpinned_codex_opencode_omits
pass "unpinned codex/opencode omit the key and advise exactly once per (front-end, tier) (R7)"
test_pin_overrides_verbatim
pass "models.pin.<front-end>.<tier> overrides the alias and is written verbatim (R8)"
test_unknown_tier_warns_and_inherits
pass "unknown tier warns, resolves as inherit, exits 0 (R9)"
test_opencode_pin_format_guard
pass "an opencode pin without '/' warns and never reaches opencode.json (R10)"
test_antigravity_model_frontmatter
pass "antigravity personas carry model: beside description (R13)"
test_opencode_json_model_member
pass "opencode agent.<role> carries a \"model\" member (R14)"
test_gemini_agent_files
pass "gemini .gemini/agents/<role>.md created for all six roles with a pointer body (R15)"
test_codex_agent_files_project_local
pass "codex .codex/agents/<role>.toml is project-local; \$CODEX_HOME is never touched (R16)"
test_codex_selected_preserves_foreign_and_edited
pass "selected Codex role installs preserve foreign/edited files through last-written ownership stamps"
test_codex_rejects_symlinked_role_destinations
pass "Codex role install/reclamation reject symlinked files and directories without touching external targets"
test_new_trees_conditional
pass "Gemini remains conditional; selected Codex always registers six model-optional roles (R6, R7, R17)"
test_return_to_inherit_reconciles
pass "every role back to inherit reclaims Gemini and regenerates six model-less Codex roles (R8, R11, R17)"
test_selection_gating
pass "an unselected front-end is never stamped, even with a full models: block (R18)"
test_restamp_after_config_change
pass "a config change re-stamps every artifact, exactly one model key per role (R19)"
test_restamp_overwrites_user_edits
pass "historical front-ends retain regeneration behavior while selected Codex preserves edited roles through ownership stamps (R26)"
test_opencode_json_restamp_rules
pass "opencode.json: pristine ⇒ regenerated, stamped ⇒ re-stamped, edited ⇒ untouched + warning (R20)"
test_opencode_json_file_mode
pass "opencode.json is written at the umask default, never mktemp's 0600; an existing mode is preserved (R20, R11)"
test_stamping_is_deterministic
pass "two runs with an unchanged config produce byte-identical stamped artifacts (R21)"
test_deselect_reclaims_stamped
pass "deselect reclaims every stamped artifact and prunes the harness-created dirs (R22)"
test_deselect_preserves_user_edits
pass "an edited stamped artifact survives deselection with a warning (R23)"

echo "All model-routing tests passed."
