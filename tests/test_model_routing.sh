#!/bin/sh
# test_model_routing.sh — E17-F01 per-role model selection.
#
# Covers R4–R23 and R26: tier resolution, `inherit` ⇒ key omission, the built-in
# floating-alias table, pin override + the OpenCode `provider/model` guard, unknown-tier
# tolerance, per-front-end stamping (claude / codex / opencode),
# conditional creation of the two new trees, selection gating, idempotent re-stamping, the
# opencode.json re-stamp rules, determinism, and both halves of the BR6 seam — deselection
# preserves a user-edited artifact (R23) while a re-install regenerates one (R26).
#
# Zero dependencies; self-cleaning temp dir. R1–R3, R11, R12, R24 and R25 (the
# installer-wiring half) live in tests/test_install.sh.
#
# E99-F159 additions: the fourth tier `frontier`, resolving to the floating `fable`
# alias on claude, with no built-in alias on codex/opencode (same shape as the other
# three tiers) and honored by `pin.<front-end>.frontier`.

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

ALL=claude,codex,opencode
ROLES="orchestrator architect builder builder-heavy reviewer scout doc-critic"

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
  grep -q '^model = ' "$_t/.codex/agents/builder.toml" && fail "R5: inherit role got a model key (codex)"
  grep -q '"builder":.*"model"' "$_t/opencode.json"  && fail "R5: inherit role got a model member (opencode)"
  # The literal string `inherit` appears in NO generated agent definition. Scope: the
  # artifacts this feature writes. The `.harness/` body is a VERBATIM copy of the source
  # (config, docs, specs, role bodies, tools, init.sh, manifest prose) and legitimately
  # uses the word in prose — copying is not generating, so it is out of scope here.
  _hits="$(grep -rl 'inherit' \
      "$_t/.claude/agents" "$_t/.codex/agents" \
      "$_t/opencode.json" 2>/dev/null || true)"
  [ -z "$_hits" ] || fail "R5: the literal 'inherit' leaked into generated artifacts: $_hits"

  # The PIN path is the other way `inherit` can reach an artifact: a pin is otherwise
  # written VERBATIM, so `pin.<front-end>.<tier>: "inherit"` — an easy misreading of the
  # documented tier vocabulary — would emit `model: inherit` / `model = "inherit"`.
  # R5 is absolute, so a pin of `inherit` must compile to the SAME omission the inherit
  # TIER does (not to the built-in alias, and not to the literal). Exercised on ALL THREE
  # front-ends at once: `builder` is on a tier whose pin is `inherit` everywhere, while
  # `scout` carries a real value so the .codex/ tree exists and
  # the builder artifacts are actually there to inspect.
  _p="$(mk r5pin)"; run "$_p" "$ALL"
  set_tier "$_p" builder reasoning
  for _fe in claude codex opencode; do
    set_pin "$_p" "$_fe" reasoning "inherit"
  done
  set_tier "$_p" scout cheap
  set_pin "$_p" codex cheap "gpt-5-mini"
  set_pin "$_p" opencode cheap "openai/gpt-5-mini"
  _pe="$(run_err "$_p" "$ALL")"           # also asserts exit 0
  # The pinned-to-`inherit` role carries NO model key anywhere. (`opus`/`pro` would mean
  # the guard fell through to the alias instead of omitting.)
  grep -q '^model:'   "$_p/.claude/agents/builder.md"    && fail "R5pin: a pin of 'inherit' produced a model: key (claude)"
  grep -q '^model = ' "$_p/.codex/agents/builder.toml"   && fail "R5pin: a pin of 'inherit' produced a model key (codex)"
  grep -q '"builder":.*"model"' "$_p/opencode.json"      && fail "R5pin: a pin of 'inherit' produced a model member (opencode)"
  # …and the role with a real value still resolves, so this is omission, not a dead run.
  grep -q '^model: haiku' "$_p/.claude/agents/scout.md" \
    || fail "R5pin: setup — scout should still resolve normally"
  grep -q '^model = "gpt-5-mini"' "$_p/.codex/agents/scout.toml" \
    || fail "R5pin: setup — the codex scout pin should still resolve"
  # No literal `inherit` anywhere in the generated artifacts, and the drop is diagnosed.
  _phits="$(grep -rl 'inherit' \
      "$_p/.claude/agents" "$_p/.codex/agents" \
      "$_p/opencode.json" 2>/dev/null || true)"
  [ -z "$_phits" ] || fail "R5pin: the literal 'inherit' leaked in via a pin: $_phits"
  printf '%s\n' "$_pe" | grep -q "is a tier name, not a model id" \
    || fail "R5pin: a pin of 'inherit' was dropped silently — no advisory on stderr"
  return 0
}

# ── R6: built-in floating aliases; no harness-frozen model id ────────────────────
test_builtin_tier_aliases() {
  _t="$(mk r6)"; run "$_t" claude
  set_tier "$_t" architect reasoning
  set_tier "$_t" builder standard
  set_tier "$_t" scout cheap
  run "$_t" claude
  _cl() { sed -n 's/^model: //p' "$_t/.claude/agents/$1.md"; }
  [ "$(_cl architect)" = "opus" ]   || fail "R6: claude reasoning != opus (got '$(_cl architect)')"
  [ "$(_cl builder)"   = "sonnet" ] || fail "R6: claude standard != sonnet (got '$(_cl builder)')"
  [ "$(_cl scout)"     = "haiku" ]  || fail "R6: claude cheap != haiku (got '$(_cl scout)')"
  # No built-in default may be a version-pinned id (any digit in the emitted alias).
  _frozen="$(sed -n '/^model_alias()/,/^}/p' "$SRC/harness-install.sh" | grep -E "printf '[a-z-]*[0-9]" || true)"
  [ -z "$_frozen" ] || fail "R6: the built-in tier table ships a version-pinned model id: $_frozen"
  return 0
}

# ── R7: unpinned tier on codex/opencode omits the key + ONE info line ────────────
test_unpinned_codex_opencode_omits() {
  _t="$(mk r7)"; run "$_t" "$ALL"
  # every role on `cheap` ⇒ seven resolutions per front-end, one advisory line each
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
  # Claude does resolve on the same config through its built-in aliases.
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
  # E99-F159: the known-tiers list in the warning now names all FOUR tiers, so an
  # operator reading stderr against an older doc is not left one tier short.
  printf '%s\n' "$_e" | grep -q 'known tiers: reasoning standard cheap frontier inherit' \
    || fail "E99-F159: the unknown-tier warning does not list all four known tiers"
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

# ── E99-F159: `frontier` resolves to the floating `fable` alias on claude ────────
test_frontier_tier_claude_alias() {
  _t="$(mk f159-alias)"; run "$_t" claude
  set_tier "$_t" architect frontier
  run "$_t" claude
  [ "$(sed -n 's/^model: //p' "$_t/.claude/agents/architect.md")" = "fable" ] \
    || fail "E99-F159: claude frontier tier did not resolve to fable"
  # No digit anywhere in the emitted alias: it must stay a FLOATING vendor alias, never
  # a version-pinned model id (same invariant R6 already pins for the other three tiers).
  case "$(sed -n 's/^model: //p' "$_t/.claude/agents/architect.md")" in
    *[0-9]*) fail "E99-F159: the frontier alias looks version-pinned, not floating" ;;
  esac
  return 0
}

# ── E99-F159: an unpinned `frontier` stamps no model on codex/opencode ───────────
test_frontier_unpinned_codex_opencode_omits() {
  _t="$(mk f159-unpinned)"; run "$_t" "$ALL"
  set_tier "$_t" architect frontier
  run "$_t" "$ALL"
  [ "$(sed -n 's/^model: //p' "$_t/.claude/agents/architect.md")" = "fable" ] \
    || fail "E99-F159: setup — claude should still resolve frontier while codex/opencode are unpinned"
  grep -q '^model = ' "$_t/.codex/agents/architect.toml" \
    && fail "E99-F159: an unpinned frontier tier stamped a model key on codex"
  grep -q '"architect":.*"model"' "$_t/opencode.json" \
    && fail "E99-F159: an unpinned frontier tier stamped a model member on opencode"
  return 0
}

# ── E99-F159: pin.<front-end>.frontier is honored on codex and opencode ─────────
test_frontier_pin_honored() {
  _t="$(mk f159-pin)"; run "$_t" "$ALL"
  set_tier "$_t" architect frontier
  set_pin "$_t" codex frontier "gpt-5-pro"
  set_pin "$_t" opencode frontier "anthropic/claude-fable"
  run "$_t" "$ALL"
  grep -q '^model = "gpt-5-pro"$' "$_t/.codex/agents/architect.toml" \
    || fail "E99-F159: pin.codex.frontier was not honored"
  grep -q '"architect":.*"model": "anthropic/claude-fable"' "$_t/opencode.json" \
    || fail "E99-F159: pin.opencode.frontier was not honored"

  # The opencode provider/model format guard is generic over the tier — a malformed
  # frontier pin is rejected exactly like a malformed pin on any other tier (R10).
  _u="$(mk f159-pin-guard)"; run "$_u" opencode
  set_tier "$_u" architect frontier
  set_pin "$_u" opencode frontier "fable-only-no-provider"
  _e="$(run_err "$_u" opencode)"
  printf '%s\n' "$_e" | grep -q 'provider/model' \
    || fail "E99-F159: a malformed frontier pin was not rejected by the provider/model guard"
  grep -q '"model"' "$_u/opencode.json" \
    && fail "E99-F159: a malformed frontier pin still stamped a model key"
  return 0
}

# ── E99-F161: Codex `model_reasoning_effort` rides the SAME tier as `model` ──────
# No new config key: the tier that would pick a floating `claude` alias also picks a
# built-in Codex reasoning effort. Unlike `model`, this needs no `pin.codex.<tier>` —
# the effort is not model-identity, so there is nothing for the operator to pin.
test_codex_effort_rides_tier() {
  _t="$(mk f161-rides-tier)"; run "$_t" codex
  set_tier "$_t" scout      cheap
  set_tier "$_t" builder    standard
  set_tier "$_t" architect  reasoning
  set_tier "$_t" doc-critic frontier
  run "$_t" codex
  grep -q '^model_reasoning_effort = "low"$'    "$_t/.codex/agents/scout.toml" \
    || fail "F161: cheap tier did not stamp effort 'low' on scout"
  grep -q '^model_reasoning_effort = "medium"$' "$_t/.codex/agents/builder.toml" \
    || fail "F161: standard tier did not stamp effort 'medium' on builder"
  grep -q '^model_reasoning_effort = "high"$'   "$_t/.codex/agents/architect.toml" \
    || fail "F161: reasoning tier did not stamp effort 'high' on architect"
  grep -q '^model_reasoning_effort = "xhigh"$'  "$_t/.codex/agents/doc-critic.toml" \
    || fail "F161: frontier tier did not stamp effort 'xhigh' on doc-critic"
  # None of the four roles above have a `pin.codex.<tier>` set — `model` stays omitted
  # while `model_reasoning_effort` is stamped, proving effort needs no model pin.
  for _r in scout builder architect doc-critic; do
    grep -q '^model = ' "$_t/.codex/agents/$_r.toml" \
      && fail "F161: setup — $_r unexpectedly resolved a model without a pin"
  done
  # A role left on `inherit` gets neither key, and its file is byte-identical to a
  # target with no models: block edits at all (the untouched-seed control).
  _u="$(mk f161-inherit)"; run "$_u" codex
  grep -q '^model_reasoning_effort = ' "$_u/.codex/agents/reviewer.toml" \
    && fail "F161: an inherit-tier role stamped a model_reasoning_effort key"
  cmp -s "$_t/.codex/agents/reviewer.toml" "$_u/.codex/agents/reviewer.toml" \
    || fail "F161: an untouched (inherit) role's file differs across two otherwise-different configs"
  return 0
}

# ── E99-F161: the built-in ladder is a FIXED, closed table — no `ultra` ──────────
# Mirrors R6's frozen-alias check: extract the function body statically (never execute
# it) so the assertion fails the moment someone edits the table, not just when a role
# happens to exercise the changed arm.
test_codex_effort_builtin_ladder_is_fixed() {
  _body="$(sed -n '/^codex_effort_alias() {/,/^}/p' "$SRC/harness-install.sh")"
  printf '%s\n' "$_body" | grep -q "cheap)     printf 'low\\\\n'" \
    || fail "F161: codex_effort_alias no longer maps cheap -> low"
  printf '%s\n' "$_body" | grep -q "standard)  printf 'medium\\\\n'" \
    || fail "F161: codex_effort_alias no longer maps standard -> medium"
  printf '%s\n' "$_body" | grep -q "reasoning) printf 'high\\\\n'" \
    || fail "F161: codex_effort_alias no longer maps reasoning -> high"
  printf '%s\n' "$_body" | grep -q "frontier)  printf 'xhigh\\\\n'" \
    || fail "F161: codex_effort_alias no longer maps frontier -> xhigh"
  # `ultra` is real Codex vocabulary but is model-specific (exactly two models today) —
  # the harness has no model list, so the built-in table must never emit it.
  printf '%s\n' "$_body" | grep -q 'ultra' \
    && fail "F161: the built-in tier->effort table emits 'ultra' — it cannot know the pinned model supports it"
  return 0
}

# ── E99-F161: an invalid effort value is GUARDED — warn once, write nothing ──────
# Codex does not degrade an unrecognized key: it discards the WHOLE role definition.
# The harness has no operator-facing effort override (E99-F161 rejected that axis), so
# the only way an invalid value can ever reach `resolve_codex_effort`'s guard is a
# maintenance edit to the built-in table — reproduced here as a doctored installer
# copy, the same technique tests/test_umbrella.sh uses for its own fail-closed control.
test_codex_effort_guard_rejects_bad_value() {
  _m="$(mk f161-guard-src)"
  mkdir -p "$_m/mut"
  for _md in harness-install.sh VERSION AGENTS.md init.sh agents docs store tools specs \
             harness.config.yaml umbrella.manifest.example.yaml umbrella.gitignore.example; do
    [ -e "$SRC/$_md" ] && cp -R "$SRC/$_md" "$_m/mut/"
  done
  awk '
    $0 == "    reasoning) printf '\''high\\n'\'' ;;" {
      print "    reasoning) printf '\''totally_bogus_effort_zz\\n'\'' ;; # mutation: invalid built-in effort"
      next
    }
    { print }
  ' "$_m/mut/harness-install.sh" > "$_m/mut/harness-install.mut"
  mv "$_m/mut/harness-install.mut" "$_m/mut/harness-install.sh"
  [ "$(grep -c 'mutation: invalid built-in effort' "$_m/mut/harness-install.sh")" = "1" ] \
    || fail "F161 guard setup: the doctored installer did not carry exactly one injected bad value"

  _t="$(mk f161-guard-bad)"
  # First run seeds a fresh models: block (config not created yet); THEN set the tier
  # and re-run — matching every other test's run/edit/run shape.
  CODEX_HOME="$_t/ch" sh "$_m/mut/harness-install.sh" --agents=codex "$_t" >/dev/null 2>&1 \
    || fail "F161 guard: first (unmutated-config) install exited non-zero"
  set_tier "$_t" architect reasoning
  _e="$(CODEX_HOME="$_t/ch" sh "$_m/mut/harness-install.sh" --agents=codex "$_t" 2>&1 >/dev/null)" \
    || fail "F161 guard: mutated-table install exited non-zero"
  printf '%s\n' "$_e" | grep -q "not in the known Codex effort vocabulary" \
    || fail "F161 guard: no warning for the invalid built-in effort value: $_e"
  grep -q '^model_reasoning_effort = ' "$_t/.codex/agents/architect.toml" \
    && fail "F161 guard: an invalid effort value REACHED the generated file"

  # Prove the guard — and not some other omission — is what stopped it: neutralise
  # ONLY the validation case/esac block (same doctored copy, same bad table entry) and
  # confirm the identical bad value now DOES reach the file.
  awk '
    $0 == "  case \"$_rce_val\" in" { print "  : # mutation: codex effort guard neutralised"; skip=1; next }
    skip { if ($0 == "  esac") skip=0; next }
    { print }
  ' "$_m/mut/harness-install.sh" > "$_m/mut/harness-install.noguard"
  mv "$_m/mut/harness-install.noguard" "$_m/mut/harness-install.sh"
  [ "$(grep -c 'mutation: codex effort guard neutralised' "$_m/mut/harness-install.sh")" = "1" ] \
    || fail "F161 guard control: the doctored installer did not neutralise exactly one guard"
  _v="$(mk f161-guard-noguard)"
  CODEX_HOME="$_v/ch" sh "$_m/mut/harness-install.sh" --agents=codex "$_v" >/dev/null 2>&1 \
    || fail "F161 guard control: setup install (unmutated config) exited non-zero"
  set_tier "$_v" architect reasoning
  CODEX_HOME="$_v/ch" sh "$_m/mut/harness-install.sh" --agents=codex "$_v" >/dev/null 2>&1 \
    || fail "F161 guard control: mutated-table, no-guard install exited non-zero"
  grep -q '^model_reasoning_effort = "totally_bogus_effort_zz"$' "$_v/.codex/agents/architect.toml" \
    || fail "F161 guard control: removing the guard did NOT let the bad value through — the earlier rejection was not proven to be the guard's doing"
  return 0
}

# ── R13: antigravity `.agents/agents/<role>.md` frontmatter ──────────────────────
# E29-F01 R1/R3: retired active emission is replaced by frozen migration coverage
# in tests/test_frontend_retirement.sh.

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

# ── R15: gemini per-role files, all seven roles, pointer body ────────────────────
# E29-F01 R1/R3: retired active emission is replaced by frozen migration coverage
# in tests/test_frontend_retirement.sh.

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
  [ "$(find "$_t/.codex/agents" -type f -name '*.toml' | wc -l | tr -d ' ')" = "7" ] \
    || fail "E23 review: preserving one foreign role did not leave exactly seven registrations"
  [ -f "$_t/.codex/agents/builder-heavy.toml" ] \
    || fail "E17-F02 R10: builder-heavy.toml missing after preserving one foreign role"

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

# Last-written model stamps must not become ownership capabilities through symlinks.
# Cover a Codex stamp directory across selected routing + deselection, a Codex stamp
# leaf across routing. Retired Gemini stamp preservation is in the migration suite.
test_model_stamp_symlinks_are_not_followed() {
  _d="$(mk model-stamp-dir-link)"; run "$_d" codex
  _dext="$T/model-stamp-dir.external"
  mv "$_d/.harness/.model-agents/codex" "$_dext"
  ln -s "$_dext" "$_d/.harness/.model-agents/codex"
  printf 'external model stamp sentinel\n' > "$_dext/builder.toml"
  cp "$_dext/builder.toml" "$_d/.codex/agents/builder.toml"
  cp -R "$_dext" "$_dext.ref"
  cp "$_d/.codex/agents/builder.toml" "$_d/live.ref"
  set_tier "$_d" builder standard
  set_pin "$_d" codex standard "gpt-5-codex"
  run "$_d" codex
  [ -L "$_d/.harness/.model-agents/codex" ] \
    || fail "round-5 model stamp: routing replaced a Codex stamp-directory link"
  diff -r "$_dext.ref" "$_dext" >/dev/null \
    || fail "round-5 model stamp: routing changed an external Codex stamp directory"
  cmp -s "$_d/live.ref" "$_d/.codex/agents/builder.toml" \
    || fail "round-5 model stamp: routing used a linked Codex stamp as ownership evidence"
  run "$_d" claude
  [ -L "$_d/.harness/.model-agents/codex" ] \
    || fail "round-5 model stamp: deselection removed a Codex stamp-directory link"
  diff -r "$_dext.ref" "$_dext" >/dev/null \
    || fail "round-5 model stamp: deselection changed an external Codex stamp directory"
  cmp -s "$_d/live.ref" "$_d/.codex/agents/builder.toml" \
    || fail "round-5 model stamp: deselection removed a role through linked ownership evidence"

  _f="$(mk model-stamp-leaf-link)"; run "$_f" codex
  _fext="$T/model-stamp-leaf.external"
  mv "$_f/.harness/.model-agents/codex/architect.toml" "$_fext"
  ln -s "$_fext" "$_f/.harness/.model-agents/codex/architect.toml"
  printf 'external model leaf sentinel\n' > "$_fext"
  cp "$_fext" "$_f/.codex/agents/architect.toml"
  cp "$_fext" "$_fext.ref"
  cp "$_f/.codex/agents/architect.toml" "$_f/live.ref"
  set_tier "$_f" architect reasoning
  set_pin "$_f" codex reasoning "gpt-5"
  run "$_f" codex
  [ -L "$_f/.harness/.model-agents/codex/architect.toml" ] \
    || fail "round-5 model stamp: routing removed a Codex stamp-leaf link"
  cmp -s "$_fext.ref" "$_fext" \
    || fail "round-5 model stamp: routing changed an external Codex stamp leaf"
  cmp -s "$_f/live.ref" "$_f/.codex/agents/architect.toml" \
    || fail "round-5 model stamp: routing used a linked Codex stamp leaf as ownership evidence"

  return 0
}

# R9/round 6: an unsafe Gemini stamp tree affects bookkeeping only. Under the same
# selected model config, live role bytes must remain exactly the pre-feature baseline.
# E29-F01 R1/R3: retired active emission is replaced by frozen migration coverage
# in tests/test_frontend_retirement.sh.

# ── R17: Selected Codex roles are always registered ──
test_new_trees_conditional() {
  # (a) everything on inherit
  _t="$(mk r17a)"; run "$_t" codex
  [ "$(find "$_t/.codex/agents" -type f -name '*.toml' | wc -l | tr -d ' ')" = "7" ] \
    || fail "R6: all-inherit Codex did not create exactly seven role TOMLs"
  [ -f "$_t/.codex/agents/builder-heavy.toml" ] \
    || fail "E17-F02 R10: all-inherit Codex did not register builder-heavy"
  grep -q '^model = ' "$_t/.codex/agents/"*.toml \
    && fail "R7: all-inherit Codex role gained a model key"
  # (b) a real tier without a Codex pin remains model-less.
  _t2="$(mk r17b)"; run "$_t2" codex
  set_tier "$_t2" architect reasoning
  run "$_t2" codex
  [ "$(find "$_t2/.codex/agents" -type f -name '*.toml' | wc -l | tr -d ' ')" = "7" ] \
    || fail "R6: unpinned Codex did not retain exactly seven role TOMLs"
  [ -f "$_t2/.codex/agents/builder-heavy.toml" ] \
    || fail "E17-F02 R10: unpinned Codex did not retain builder-heavy"
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
  _cx="$_t/.codex/agents/scout.toml"       # new in E17-F01
  for _f in "$_cl" "$_cx"; do
    [ -f "$_f" ] || fail "R26: setup — $_f was not stamped"
  done

  # Keep a pristine reference of each file plus the config, then plant the same edit in
  # both. The reference is what "regenerated from the current configuration" means.
  _ref="$T/r26-ref"; rm -rf "$_ref"; mkdir -p "$_ref"
  cp "$_cl" "$_ref/claude.md"
  cp "$_cx" "$_ref/codex.toml"
  cp "$(cfg "$_t")" "$_ref/harness.config.yaml"
  for _f in "$_cl" "$_cx"; do
    printf 'zzz-user-edit\n' >> "$_f"
  done

  run "$_t" "$ALL"

  # The premise of this test: no set_tier, no set_pin, so the installer saw the SAME
  # config bytes it saw on the previous run. If this ever fails the test has silently
  # become a duplicate of R19.
  cmp -s "$_ref/harness.config.yaml" "$(cfg "$_t")" \
    || fail "R26: the config changed across the re-run — this test must exercise an UNCHANGED config (R19 owns the changed case)"

  # (a) Codex preserves the edit.
  grep -q 'zzz-user-edit' "$_cx" || fail "E23 review: an edited .codex/agents/scout.toml was overwritten on selected re-install"
  # (b) …and from the Claude shim, the contract R26 says it matches. Asserting
  #     this here is what makes "matching the pre-existing generated-glue contract"
  #     verified rather than merely claimed in prose.
  grep -q 'zzz-user-edit' "$_cl" && fail "R26: an edited .claude/agents/scout.md was not regenerated (the precedent R26 cites no longer holds)"

  # (c) the regenerated body is the NORMAL one — the stamp is intact and single, not a
  #     truncated or doubled rewrite.
  [ "$(grep -c '^model = ' "$_cx")" = "1" ] || fail "E23 review: preserved .codex/agents/scout.toml lost its model key"
  [ "$(grep -c '^model:' "$_cl")" = "1" ] || fail "R26: .claude/agents/scout.md does not carry exactly one model: key after regeneration"
  grep -q '^model = "gpt-5-mini"$' "$_cx"    || fail "R26: .codex/agents/scout.toml lost its resolved value"
  grep -q '^model: haiku$' "$_cl"            || fail "R26: .claude/agents/scout.md lost its resolved value"

  # (d) strongest form: each regenerated file is byte-identical to the pristine reference,
  #     i.e. the re-run reproduced the generator's output exactly (this is also what keeps
  #     deselection able to reclaim these files at all — R21).
  cmp -s "$_ref/codex.toml"     "$_cx" && fail "E23 review: edited Codex role unexpectedly reverted to its pristine reference"
  cmp -s "$_ref/claude.md"      "$_cl" || fail "R26: the regenerated .claude/agents/scout.md is not byte-identical to the pristine reference"

  # Deselection preservation for the retained Codex roles is asserted separately
  # by test_deselect_preserves_user_edits; retired Gemini uses the frozen migration suite.
  return 0
}

# ── R20: the three opencode.json re-stamp cases ──────────────────────────────────
test_opencode_json_restamp_rules() {
  # (a) a pre-existing PRISTINE model-free body gains the model members
  _ta="$(mk r20a)"; run "$_ta" opencode
  grep -q '"model"' "$_ta/opencode.json" && fail "R20a: setup — the model-free body already has a model member"
  # E17-F02 REVISES this clause: the stamp is now written on EVERY run that writes
  # opencode.json. A model-free body is reproducible only by the installer VERSION that
  # generated it, so "no stamp for a model-free body" is what locked already-installed
  # targets out of a newly added role. What must remain true — and is asserted instead —
  # is that an unconfigured target's stamp holds no model state.
  [ -f "$_ta/.harness/.opencode.stamp" ] \
    || fail "R20a/E17-F02: a model-free write did not record .opencode.stamp"
  grep -q '"model"' "$_ta/.harness/.opencode.stamp" \
    && fail "R20a: a model-free body stamped a model member"
  cmp -s "$_ta/opencode.json" "$_ta/.harness/.opencode.stamp" \
    || fail "R20a/E17-F02: the model-free stamp is not a byte copy of opencode.json"
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
  cp -R "$_t/.claude" "$_t/.agents" "$_t/.codex" "$_s/"
  cp "$_t/opencode.json" "$_t/.harness/.opencode.stamp" "$_s/"
  run "$_t" "$ALL"
  for _d in .claude .agents .codex; do
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
  [ -f "$_t/.codex/agents/scout.toml" ]       || fail "R22: setup — codex artifact missing"
  [ -f "$_t/.harness/.opencode.stamp" ]       || fail "R22: setup — opencode stamp missing"
  run "$_t" claude
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
  [ -f "$_t/.codex/agents/scout.toml" ] || fail "R23: setup — codex artifact missing"
  printf '# mine\n' >> "$_t/.codex/agents/scout.toml"
  _e="$(run_err "$_t" claude)"
  [ -f "$_t/.codex/agents/scout.toml" ] || fail "R23: an EDITED .codex/agents/scout.toml was deleted on deselect"
  printf '%s\n' "$_e" | grep -q '.codex/agents/scout.toml' \
    || fail "R23: no warning naming the preserved codex file"
  # pristine siblings ARE reclaimed; the dirs survive only because a user file remains
  [ -f "$_t/.codex/agents/builder.toml" ] && fail "R23: a pristine sibling was not reclaimed (codex)"
  return 0
}

# ── R11/R17: every role back to `inherit` reconciles previously stamped models ──
test_return_to_inherit_reconciles() {
  # (a) Codex regenerates the same seven model-less roles.
  _t="$(mk r11rec)"; run "$_t" codex
  set_tier "$_t" architect reasoning
  set_tier "$_t" scout cheap
  set_pin "$_t" codex cheap "gpt-5-mini"
  run "$_t" codex
  [ -f "$_t/.codex/agents/scout.toml" ]    || fail "R11rec: setup — codex artifact missing"
  grep -q '^model = ' "$_t/.codex/agents/scout.toml"   || fail "R11rec: setup — codex model key missing"
  # Now put EVERY role back on inherit — nothing resolves for either front-end.
  set_tier "$_t" architect inherit
  set_tier "$_t" scout inherit
  run "$_t" codex
  [ "$(find "$_t/.codex/agents" -type f -name '*.toml' | wc -l | tr -d ' ')" = "7" ] \
    || fail "R8: pin→inherit did not retain exactly seven Codex roles"
  [ -f "$_t/.codex/agents/builder-heavy.toml" ] \
    || fail "E17-F02 R10: pin→inherit did not retain builder-heavy"
  grep -q '^model = ' "$_t/.codex/agents/"*.toml \
    && fail "R8: pin→inherit left a Codex model key behind"
  # The still-selected front-ends keep the rest of their glue.
  [ -f "$_t/.agents/skills/sdd-next/SKILL.md" ] || fail "R8: pin→inherit removed Codex skills"

  # (b) Selected Codex roles update from current routing only while their live bytes
  # still match the last-written stamp. Edited Codex roles are preserved.
  _u="$(mk r11rec_edit)"; run "$_u" codex
  set_tier "$_u" architect reasoning
  set_tier "$_u" scout cheap
  set_pin "$_u" codex cheap "gpt-5-mini"
  run "$_u" codex
  printf '# mine\n' >> "$_u/.codex/agents/scout.toml"
  set_tier "$_u" architect inherit
  set_tier "$_u" scout inherit
  _e="$(run_err "$_u" codex)"
  [ -f "$_u/.codex/agents/scout.toml" ] \
    || fail "R8: Codex scout role vanished on the switch back to inherit"
  grep -qx '# mine' "$_u/.codex/agents/scout.toml" \
    || fail "R8: selected Codex pin→inherit overwrote an edited role"
  grep -q '^model = "gpt-5-mini"$' "$_u/.codex/agents/scout.toml" \
    || fail "R8: preserved edited Codex role unexpectedly changed its prior routing"
  printf '%s\n' "$_e" | grep -q '.codex/agents/scout.toml' \
    || fail "R8: no warning naming the preserved edited Codex role"
  # Codex siblings remain registered model-less.
  [ -f "$_u/.codex/agents/builder.toml" ] || fail "R8: Codex sibling role vanished on pin→inherit"

  # (c) R22 with the `models:` edit and the DESELECT in the SAME run: the on-disk files
  # came from the OLD config, so a freshly generated reference cannot match them. The
  # remembered bytes can — without them a pristine file would be misclassified as
  # user-edited and orphaned. (Codex r1 P2 #3654925555.)
  _d="$(mk r11rec_desel)"; run "$_d" codex
  set_tier "$_d" architect reasoning
  set_pin "$_d" codex reasoning "gpt-5"
  run "$_d" codex
  [ -f "$_d/.codex/agents/architect.toml" ] || fail "R11rec: setup — codex artifact missing (c)"
  set_tier "$_d" architect cheap          # config changes AND the front-ends go away
  run "$_d" claude
  [ -e "$_d/.codex" ]  && fail 'R11rec: a models: edit in the deselect run orphaned .codex/'
  [ -e "$_d/.harness/.model-agents" ] && fail "R11rec: .model-agents/ outlived the artifacts it describes"
  return 0
}

# ── E35-F03: the hostile-pin table (ONE copy per suite; the plan's rows 1-35) ─────────────
# Fields: row-id <TAB> yaml-rhs <TAB> value-read <TAB> installer-verdict <TAB> dispatcher
# (no thinking:) <TAB> dispatcher (thinking: high). Both value fields are expanded with
# printf '%b' (bytes a here-doc cannot hold: UTF-8, ESC, TAB, newline, a literal backslash-n
# written as two backslashes). @EMPTY@ is the empty value (IFS-tab would drop the field);
# @256@ / @257@ are a valid-charset id of exactly 256 / 257 bytes. A dash in a dispatcher
# column means the row cannot reach a role file.
TAB="$(printf '\t')"
pin_rows() { cat <<'PINROWS'
1	""	@EMPTY@	absent	—	—
2	"anthropic/claude-sonnet-4-5"	anthropic/claude-sonnet-4-5	ok	pass	pass
3	"openrouter/meta-llama/llama-3.1-8b-instruct:free"	openrouter/meta-llama/llama-3.1-8b-instruct:free	ok	pass	pass
4	"amazon-bedrock/anthropic.claude-3-5-sonnet-20240620-v1:0"	amazon-bedrock/anthropic.claude-3-5-sonnet-20240620-v1:0	ok	pass	pass
5	"openrouter/anthropic/claude-3.7-sonnet:thinking"	openrouter/anthropic/claude-3.7-sonnet:thinking	ok	pass	pass
6	"google-vertex/claude-sonnet-4@20250514"	google-vertex/claude-sonnet-4@20250514	ok	pass	pass
7	"Prov/id:HIGH"	Prov/id:HIGH	ok	pass	pass
8	'anthropic/claude-opus-4'	anthropic/claude-opus-4	ok	pass	pass
9	anthropic/claude-opus-4  # note	anthropic/claude-opus-4	ok	pass	pass
10	@256@	@256@	ok	pass	pass
11	@257@	@257@	length	3	3
12	"claude-sonnet"	claude-sonnet	form	pass	pass
13	"/claude"	/claude	form	pass	pass
14	"anthropic/"	anthropic/	form	pass	pass
15	"anthropic//claude"	anthropic//claude	form	pass	pass
16	"anthropic/claude/"	anthropic/claude/	form	pass	pass
17	"anthropic/claude:"	anthropic/claude:	form	pass	pass
18	"-x/claude"	-x/claude	form	3	3
19	".hidden/claude"	.hidden/claude	form	pass	pass
20	"anthropic/claude:high"	anthropic/claude:high	suffix	pass	3
21	"anthropic/claude:high:low"	anthropic/claude:high:low	suffix	pass	3
22	"anthropic/claude:max"	anthropic/claude:max	suffix	pass	3
23	"anthropic/claude sonnet"	anthropic/claude sonnet	charset	3	3
24	anthropic/claude   	anthropic/claude   	charset	3	3
25	"a/b;rm -rf ~"	a/b;rm -rf ~	charset	3	3
26	"a/$(id)"	a/$(id)	charset	3	3
27	"a/b`id`"	a/b`id`	charset	3	3
28	"a/b\\nc"	a/b\\nc	charset	3	3
29	"a/b|c"	a/b|c	charset	3	3
30	"a/b'c"	a/b'c	charset	3	3
31	"a/b\0303\0251"	a/b\0303\0251	charset	3	3
32	"a/b\0033[31m"	a/b\0033[31m	charset	3	3
33	"a/b\0011c"	a/b\0011c	charset	3	3
34	inherit	inherit	inherit	—	—
35	"a/b\n    c"	a/b	ok	pass	pass
PINROWS
}
# expand_pin <field> — decode one table value field into the real bytes.
expand_pin() {
  case "$1" in
    @EMPTY@) return 0 ;;
    @256@) printf 'p/%0254d' 0; return 0 ;;
    @257@) printf 'p/%0255d' 0; return 0 ;;
  esac
  printf '%b' "$1"
}
# load_row <tab-line> — split a table line into R_ID R_RHS R_VAL R_INST R_D1 R_D2 (decoded).
load_row() {
  IFS="$TAB" read -r R_ID _r_rhs _r_val R_INST R_D1 R_D2 <<ROWEOF
$1
ROWEOF
  R_RHS="$(expand_pin "$_r_rhs"; printf x)"; R_RHS="${R_RHS%x}"
  R_VAL="$(expand_pin "$_r_val"; printf x)"; R_VAL="${R_VAL%x}"
}

# ═══ E35-F03: pi model routing ═══════════════════════════════════════════════════════════
# put_pin <target> <tier> <raw-yaml-rhs> — insert `  pin.pi.<tier>: <rhs>` under `models:`
# VERBATIM (awk ENVIRON, so backslashes, ESC and newlines in <rhs> survive unchanged).
put_pin() {
  _c="$(cfg "$1")"
  PUT_LINE="  pin.pi.$2: $3" awk '{ print } !d && /^models:[[:space:]]*(#.*)?$/ { print ENVIRON["PUT_LINE"]; d=1 }' \
    "$_c" > "$_c.t" && mv "$_c.t" "$_c"
}
# pi_tiers <target> — the standard four-tier layout: one role per tier, rest inherit.
pi_tiers() {
  set_tier "$1" architect reasoning; set_tier "$1" builder standard
  set_tier "$1" scout cheap;         set_tier "$1" reviewer frontier
}
TIER_ROLES="reasoning:architect standard:builder cheap:scout frontier:reviewer"
# pi_file <target> <role> / pi_line <target> <role> <key> — the role file and one stamped line.
pi_file() { printf '%s\n' "$1/.pi/agents/$2.md"; }
pi_line() { sed -n "s/^$3: //p" "$1/.pi/agents/$2.md"; }
# wait_cells <dir> — join background cells; each cell writes <dir>/<name>.res ending in `done`.
wait_cells() {
  wait
  for _f in "$1"/*.res; do
    [ "$(tail -n 1 "$_f")" = done ] || { cat "$_f" >&2; fail "cell $(basename "$_f") failed"; }
  done
}
# pin_verdict — extract the installer's pure grammar and run it in-process.
PV_FN="$T/pv.sh"
awk '/^pi_pin_verdict\(\) \{/,/^\}/' "$SRC/harness-install.sh" > "$PV_FN"
[ -s "$PV_FN" ] || fail "setup: could not extract pi_pin_verdict"
pin_verdict() { sh -c '. "$1"; pi_pin_verdict "$2"' sh "$PV_FN" "$1"; }

# ── R1: the tier→thinking ladder ───────────────────────────────────────────────────────────
test_pi_thinking_ladder() {
  _t="$(mk pi-ladder)"; run "$_t" pi
  pi_tiers "$_t"; set_tier "$_t" doc-critic inherit
  run "$_t" pi
  [ "$(pi_line "$_t" architect thinking)" = high ]   || fail "R1a: reasoning did not stamp thinking: high"
  [ "$(pi_line "$_t" builder thinking)" = medium ]   || fail "R1a: standard did not stamp thinking: medium"
  [ "$(pi_line "$_t" scout thinking)" = low ]        || fail "R1a: cheap did not stamp thinking: low"
  [ "$(pi_line "$_t" reviewer thinking)" = xhigh ]   || fail "R1a: frontier did not stamp thinking: xhigh"
  grep -q '^thinking:' "$(pi_file "$_t" doc-critic)" && fail "R1a: an inherit role carries thinking:"
  grep -q '^model:' "$(pi_file "$_t" architect)" && fail "R1a: an unpinned tier carries model:"
  # (b) an unknown tier is the existing warning, then inherit: no thinking.
  set_tier "$_t" doc-critic turbo
  _e="$(run_err "$_t" pi)"
  printf '%s\n' "$_e" | grep -q 'known tiers: reasoning standard cheap frontier inherit' \
    || fail "R1b: the existing unknown-tier warning is missing"
  grep -q '^thinking:' "$(pi_file "$_t" doc-critic)" && fail "R1b: an unknown tier stamped thinking:"
  # (c) an umbrella child on inherit takes the coordinator's tier.
  _u="$(mk pi-ladder-umb)"; mkdir -p "$_u/child/.git" "$_u/.harness"; cp "$SRC/harness.config.yaml" "$(cfg "$_u")"
  set_tier "$_u" builder reasoning
  HARNESS_AGENTS=pi sh "$SRC/harness-install.sh" --umbrella "$_u" >/dev/null 2>&1 || fail "R1c: umbrella install failed"
  [ "$(pi_line "$_u/child" builder thinking)" = high ] || fail "R1c: an inherit child did not cascade thinking: high"
  # (d) exactly one tier→thinking table; the codex ladder is the only other one.
  [ "$(grep -c '^pi_thinking_alias() {' "$SRC/harness-install.sh")" = 1 ] || fail "R1d: pi_thinking_alias is not defined exactly once"
  [ "$(grep -cE '^[[:space:]]*cheap\)[^#]*(=|printf .)low' "$SRC/harness-install.sh")" = 2 ] \
    || fail "R1d: a third tier->level table appeared (expected only codex_effort_alias and pi_thinking_alias)"
}

# ── M2 / M2b: the thinking guard, proven in a scratch COPY of the tree ───────────────────
# MS: one copied source tree; variant installers sit beside the original as siblings.
MS="$T/ms"
mutsrc() {
  [ -d "$MS" ] && return 0
  mkdir -p "$MS/specs"
  for _e in agents AGENTS.md CHANGELOG.md CLAUDE.md docs harness.config.yaml harness-install.sh \
            init.sh store tools VERSION README.md umbrella.gitignore.example umbrella.manifest.example.yaml; do
    cp -R "$SRC/$_e" "$MS/"
  done
  cp -R "$SRC/specs/_templates" "$SRC/specs/adr" "$SRC/specs/glossary.md" "$SRC/specs/product.md" "$MS/specs/"
}
# mutant <name> <exact-line> <replacement> — a sibling installer with ONE line replaced; the
# marker must occur exactly once (else the mutant would prove nothing).
mutant() { # <name> <exact-line> <replacement> [<base-installer-basename>]
  mutsrc
  _mb="$MS/${4:-harness-install.sh}"
  [ "$(grep -cxF -- "$2" "$_mb")" = 1 ] || fail "mutant $1: marker line is not present exactly once: $2"
  M_LINE="$3" M_OLD="$2" awk '$0 == ENVIRON["M_OLD"] { print ENVIRON["M_LINE"]; next } { print }' \
    "$_mb" > "$MS/harness-install.$1.sh"
  cmp -s "$_mb" "$MS/harness-install.$1.sh" && fail "mutant $1: the edit changed nothing"
  return 0
}
mrun_err() { # <installer> <target> — stderr only, exit 0 asserted
  CODEX_HOME="$2/ch" sh "$1" --agents=pi "$2" 2>&1 >/dev/null || fail "mutant install into $2 exited non-zero"
}
test_pi_thinking_guard_mutation() {
  mutant m2 "    reasoning) _pta=high ;;" "    reasoning) _pta=bogus_zz ;;"
  _t="$(mk pi-m2)"; run "$_t" pi; set_tier "$_t" architect reasoning
  _e="$(mrun_err "$MS/harness-install.m2.sh" "$_t")"
  printf '%s\n' "$_e" | grep -q "pi thinking level 'bogus_zz'" || fail "M2: the corrupted ladder value did not warn"
  grep -q '^thinking:' "$(pi_file "$_t" architect)" && fail "M2: a corrupted ladder value still reached the role file"
  # M2b: with the guard ALSO neutralized, the bogus value lands — proving the guard did the work.
  mutant m2b "    off|minimal|low|medium|high|xhigh|max) ;;" "    *) ;;" harness-install.m2.sh
  _t="$(mk pi-m2b)"; run "$_t" pi; set_tier "$_t" architect reasoning
  mrun_err "$MS/harness-install.m2b.sh" "$_t" >/dev/null
  [ "$(pi_line "$_t" architect thinking)" = bogus_zz ] || fail "M2b: with the guard neutralized thinking: bogus_zz did not reach the file"
}

# ── R2a: the pin grammar, in-process over the whole table ──────────────────────────────────
test_pi_pin_grammar_table() {
  _n=0
  while IFS= read -r _line; do
    load_row "$_line"
    case "$R_INST" in absent|inherit) continue ;; esac
    _got="$(pin_verdict "$R_VAL")"
    [ "$_got" = "$R_INST" ] || fail "R2a: row $R_ID: pi_pin_verdict says '$_got', table says '$R_INST'"
    _n=$((_n + 1))
  done <<ROWS
$(pin_rows)
ROWS
  [ "$_n" -ge 33 ] || fail "R2a: only $_n rows exercised (the table lost rows)"
  # supplementary shapes the 35 rows leave to a single guard each
  for _x in 'a/b//c:form' 'a/b/c:ok' 'a/low:ok' 'a:b/c:form' 'a/b:free:high:suffix' 'a/:high:form' 'a/b:Max:ok' 'a/b:off:suffix' 'a/b:minimal:suffix' 'a/b:xhigh:suffix' 'a/b:medium:suffix' 'a/b:low:suffix'; do
    _got="$(pin_verdict "${_x%:*}")"
    [ "$_got" = "${_x##*:}" ] || fail "R2a: supplementary '${_x%:*}' -> '$_got', expected '${_x##*:}'"
  done
  # (e) model_alias has no pi row.
  awk '/^model_alias\(\) \{/,/^\}/' "$SRC/harness-install.sh" | grep -q 'pi:' && fail "R2e: model_alias grew a pi: row"
  return 0
}

# ── R2b-d: valid pins reach model: byte-for-byte ──────────────────────────────────────────
test_pi_pin_stamped_e2e() {
  _t="$(mk pi-stamp)"; run "$_t" pi; pi_tiers "$_t"
  _rows="2:reasoning 3:standard 4:cheap 10:frontier"
  for _p in $_rows; do
    _row="$(pin_rows | awk -F"$TAB" -v r="${_p%%:*}" '$1 == r')"
    load_row "$_row"; put_pin "$_t" "${_p##*:}" "$R_RHS"
  done
  _e="$(run_err "$_t" pi)"
  for _p in $_rows; do
    _row="$(pin_rows | awk -F"$TAB" -v r="${_p%%:*}" '$1 == r')"; load_row "$_row"
    for _tr in $TIER_ROLES; do
      [ "${_tr%%:*}" = "${_p##*:}" ] || continue
      [ "$(pi_line "$_t" "${_tr##*:}" model)" = "$R_VAL" ] || fail "R2b: row $R_ID did not land byte-for-byte on ${_tr##*:}"
    done
  done
  printf '%s\n' "$_e" | grep -q 'models.pin.pi' && fail "R2b: valid pins produced a pin warning"
  # (c) an unpinned non-inherit tier: no model:, the notice exactly once even with 3 roles on it.
  _t="$(mk pi-nopin)"; run "$_t" pi
  set_tier "$_t" builder standard; set_tier "$_t" reviewer standard; set_tier "$_t" scout standard
  _e="$(run_err "$_t" pi)"
  [ "$(printf '%s\n' "$_e" | grep -c 'pi has no built-in alias for tier .standard.')" = 1 ] \
    || fail "R2c: the no-built-in-alias notice is not printed exactly once per tier"
  grep -q '^model:' "$(pi_file "$_t" builder)" && fail "R2c: an unpinned tier stamped a model"
  # (d) umbrella: the child has no pin; the coordinator's pin applies.
  _u="$(mk pi-umb)"; mkdir -p "$_u/child/.git" "$_u/.harness"; cp "$SRC/harness.config.yaml" "$(cfg "$_u")"
  set_tier "$_u" builder standard; put_pin "$_u" standard '"a/b"'
  HARNESS_AGENTS=pi sh "$SRC/harness-install.sh" --umbrella "$_u" >/dev/null 2>&1 || fail "R2d: umbrella install failed"
  [ "$(pi_line "$_u/child" builder model)" = a/b ] || fail "R2d: the coordinator's pin did not reach the child"
  # R3d: a coordinator pin that fails the grammar warns and stamps no model.
  _u="$(mk pi-umb-bad)"; mkdir -p "$_u/child/.git" "$_u/.harness"; cp "$SRC/harness.config.yaml" "$(cfg "$_u")"
  set_tier "$_u" builder standard; put_pin "$_u" standard '"a/b;x"'
  _e="$(HARNESS_AGENTS=pi sh "$SRC/harness-install.sh" --umbrella "$_u" 2>&1 >/dev/null)" || fail "R3d: umbrella install failed"
  printf '%s\n' "$_e" | grep -q 'models.pin.pi.standard has characters outside' || fail "R3d: no charset warning for a bad coordinator pin"
  grep -q '^model:' "$(pi_file "$_u/child" builder)" && fail "R3d: a bad coordinator pin stamped a model"
  [ "$(pi_line "$_u/child" builder thinking)" = medium ] || fail "R3d: thinking was lost with the bad coordinator pin"
}

# ── R3a: every non-ok single-line row, 6 installs in parallel ─────────────────────────────
hostile_group() { # <name> <row-ids…> — one install, one tier per row, then every assertion
  _g="$1"; shift
  _t="$(mk "pi-host-$_g")"; run "$_t" pi; pi_tiers "$_t"
  _i=0; _assign=""
  for _rid in "$@"; do
    _i=$((_i + 1))
    _tr="$(printf '%s\n' $TIER_ROLES | sed -n "${_i}p")"
    load_row "$(pin_rows | awk -F"$TAB" -v r="$_rid" '$1 == r')"
    put_pin "$_t" "${_tr%%:*}" "$R_RHS"
    _assign="$_assign $_rid:$_tr"
  done
  _e="$(CODEX_HOME="$_t/ch" sh "$SRC/harness-install.sh" --agents=pi "$_t" 2>&1 >/dev/null)" \
    || fail "group $_g: the install exited non-zero"
  for _a in $_assign; do
    _rid="${_a%%:*}"; _rest="${_a#*:}"; _tier="${_rest%%:*}"; _role="${_rest##*:}"
    load_row "$(pin_rows | awk -F"$TAB" -v r="$_rid" '$1 == r')"
    case "$R_INST" in
      length) _why='is longer than 256 bytes' ;;
      charset) _why='has characters outside \[A-Za-z0-9._:/@-\]' ;;
      form) _why='is not in provider/id form' ;;
      suffix) _why='ends in a :<thinking> suffix' ;;
      *) fail "row $_rid is not a rejected row ($R_INST)" ;;
    esac
    _w="$(printf '%s\n' "$_e" | grep "models\.pin\.pi\.$_tier ")" || fail "R3a row $_rid: no warning naming models.pin.pi.$_tier"
    [ "$(printf '%s\n' "$_w" | wc -l | tr -d ' ')" = 1 ] || fail "R3a row $_rid: not exactly one warning line"
    printf '%s\n' "$_w" | grep -q -- "$_why" || fail "R3a row $_rid: the warning lacks its reason text ($_why): $_w"
    case "$R_INST" in
      form|suffix) printf '%s\n' "$_w" | grep -qF -- "'$R_VAL'" || fail "R3a row $_rid: the value is not echoed for $R_INST" ;;
      *) if [ -n "$R_VAL" ] && printf '%s\n' "$_e" | grep -qF -- "$R_VAL"; then fail "R3a row $_rid: the value was echoed for $R_INST"; fi ;;
    esac
    if [ "$(printf '%s' "$_e" | LC_ALL=C tr -cd '\033' | wc -c | tr -d ' ')" != 0 ]; then fail "R3a row $_rid: stderr carries an ESC byte"; fi
    grep -q '^model:' "$(pi_file "$_t" "$_role")" && fail "R3a row $_rid: a rejected pin still stamped model:"
    [ -n "$(pi_line "$_t" "$_role" thinking)" ] || fail "R3a row $_rid: thinking was dropped with the rejected pin"
  done
  return 0
}
test_pi_pin_rejects_hostile_e2e() {
  _d="$(mk pi-host-res)"
  ( hostile_group g1 11 12 13 14; echo done ) >"$_d/g1.res" 2>&1 &
  ( hostile_group g2 15 16 17 18; echo done ) >"$_d/g2.res" 2>&1 &
  ( hostile_group g3 19 20 21 22; echo done ) >"$_d/g3.res" 2>&1 &
  ( hostile_group g4 23 24 25 26; echo done ) >"$_d/g4.res" 2>&1 &
  ( hostile_group g5 27 28 29 30; echo done ) >"$_d/g5.res" 2>&1 &
  ( hostile_group g6 31 32 33; echo done ) >"$_d/g6.res" 2>&1 &
  wait_cells "$_d"
  # (b) row 34: the literal tier name keeps the existing warning.
  _t="$(mk pi-host-34)"; run "$_t" pi; set_tier "$_t" builder standard; put_pin "$_t" standard inherit
  _e="$(run_err "$_t" pi)"
  printf '%s\n' "$_e" | grep -q "models.pin.pi.standard = 'inherit' is a tier name, not a model id" \
    || fail "R3b: the inherit-pin warning is missing"
  grep -q '^model:' "$(pi_file "$_t" builder)" && fail "R3b: an inherit pin stamped a model"
  return 0
}

# ── R3c: config SHAPES — lookup, not grammar ──────────────────────────────────────────────
test_pi_pin_config_shapes() {
  _t="$(mk pi-shape)"; run "$_t" pi; pi_tiers "$_t"
  _c="$(cfg "$_t")"
  # commented, unknown tier key, and a pin nested under another top-level section.
  sed 's|^  # pin\.pi\.cheap: .*|  # pin.pi.cheap: "a/b"|' "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  grep -q '^  # pin\.pi\.cheap: "a/b"$' "$_c" || fail "setup: commented pin line missing"
  put_pin "$_t" turbo '"a/b"'
  printf 'telemetry_extra:\n  pin.pi.reasoning: "a/b"\n' >> "$_c"
  run "$_t" pi
  for _r in architect builder scout reviewer; do
    grep -q '^model:' "$(pi_file "$_t" "$_r")" && fail "R3c: a non-pin shape stamped a model on $_r"
  done
  # a valid pin while every role is inherit stamps nothing.
  _t="$(mk pi-shape-inh)"; run "$_t" pi; put_pin "$_t" standard '"a/b"'; run "$_t" pi
  grep -rq '^model:' "$_t/.pi/agents" && fail "R3c: a pin with every role inherit stamped a model"
  # row 35: a multi-line value is read line-wise.
  _t="$(mk pi-shape-35)"; run "$_t" pi; set_tier "$_t" builder standard
  load_row "$(pin_rows | awk -F"$TAB" '$1 == 35')"; put_pin "$_t" standard "$R_RHS"; run "$_t" pi
  [ "$(pi_line "$_t" builder model)" = "$R_VAL" ] || fail "R3c: row 35 did not stamp '$R_VAL'"
  # an empty pin (row 1) is absent: no model, no warning.
  _t="$(mk pi-shape-1)"; run "$_t" pi; set_tier "$_t" builder standard; put_pin "$_t" standard '""'
  _e="$(run_err "$_t" pi)"
  printf '%s\n' "$_e" | grep 'models.pin.pi.standard' | grep -q '⚠️' && fail "R3c: an empty pin warned"
  grep -q '^model:' "$(pi_file "$_t" builder)" && fail "R3c: an empty pin stamped a model"
  return 0
}

# ── M1: the pin guard, proven by neutralizing it in a scratch copy ───────────────────────
test_pi_pin_guard_mutation() {
  mutant m1 '      if [ "$_rm_pv" != ok ]; then' '      if false; then'
  _t="$(mk pi-m1)"; run "$_t" pi; set_tier "$_t" builder standard
  load_row "$(pin_rows | awk -F"$TAB" '$1 == 25')"; put_pin "$_t" standard "$R_RHS"
  mrun_err "$MS/harness-install.m1.sh" "$_t" >/dev/null
  [ "$(pi_line "$_t" builder model)" = "$R_VAL" ] || fail "M1: with the verdict check neutralized row 25 did not reach model:"
  run "$_t" pi
  grep -q '^model:' "$(pi_file "$_t" builder)" && fail "M1: the real installer left the hostile model: in place"
  return 0
}

# ── R7: models_any counts thinking alone ──────────────────────────────────────────────────
test_pi_models_any() {
  _t="$(mk pi-any1)"; run "$_t" pi
  [ ! -f "$_t/.harness/.escalation-arming" ] || fail "R7: an all-inherit pi target grew an arming file"
  set_tier "$_t" builder standard; run "$_t" pi
  [ -f "$_t/.harness/.escalation-arming" ] || fail "R7: a tier alone (thinking) did not satisfy models_any pi"
  _t="$(mk pi-any2)"; run "$_t" pi; put_pin "$_t" reasoning '"a/b"'; run "$_t" pi
  [ ! -f "$_t/.harness/.escalation-arming" ] || fail "R7: a pin on an unused tier counted as configured"
  return 0
}

# ── R8: verdict cells ─────────────────────────────────────────────────────────────────────
verdict_cell() { # <name> <builder> <heavy> <pin-spec> <expected>   pin-spec: "-" or tier=value,…
  _t="$(mk "pi-v-$1")"; run "$_t" pi
  set_tier "$_t" builder "$2"; set_tier "$_t" builder-heavy "$3"
  if [ "$4" != "-" ]; then
    _oifs="$IFS"; IFS=,
    for _ps in $4; do put_pin "$_t" "${_ps%%=*}" "\"${_ps#*=}\""; done
    IFS="$_oifs"
  fi
  run "$_t" pi
  _got="$(sed -n 's/^pi=//p' "$_t/.harness/.escalation-arming" 2>/dev/null)"
  [ "$_got" = "$5" ] || fail "R8 cell $1: pi verdict '$_got', expected '$5'"
}
test_pi_escalation_verdict_cells() {
  _d="$(mk pi-v-res)"
  ( verdict_cell a standard reasoning - raise; echo done ) >"$_d/a.res" 2>&1 &
  ( verdict_cell b standard standard - same; echo done ) >"$_d/b.res" 2>&1 &
  ( verdict_cell c standard inherit - none; echo done ) >"$_d/c.res" 2>&1 &
  ( verdict_cell d standard reasoning standard=a/b,reasoning=a/b raise; echo done ) >"$_d/d.res" 2>&1 &
  ( verdict_cell e reasoning reasoning reasoning=a/b same; echo done ) >"$_d/e.res" 2>&1 &
  ( verdict_cell f standard reasoning standard=a/b:high raise; echo done ) >"$_d/f.res" 2>&1 &
  wait_cells "$_d"
}
test_pi_verdict_mutation() {
  mutant m3 '  elif [ "$1" = "pi" ]; then' '  elif [ "$1" = "pi-axis-dropped" ]; then'
  _t="$(mk pi-m3)"; run "$_t" pi; set_tier "$_t" builder standard; set_tier "$_t" builder-heavy reasoning
  mrun_err "$MS/harness-install.m3.sh" "$_t" >/dev/null
  [ "$(sed -n 's/^pi=//p' "$_t/.harness/.escalation-arming")" = neither ] \
    || fail "M3: dropping the pi thinking axis did not flip standard/reasoning from raise to neither"
}

# ── R10: pi pins and pi keys leak nowhere when pi is not selected ─────────────────────────
tsnap() { ( cd "$1" && find . -type f | LC_ALL=C sort | while IFS= read -r _f; do cksum "$_f"; done ); }
leak_target() { # <name> <with-pi-keys 0|1>
  _t="$(mk "pi-leak-$1")"; CODEX_HOME="$_t/ch" sh "$SRC/harness-install.sh" --agents=claude,codex,opencode,antigravity "$_t" >/dev/null 2>&1 \
    || fail "R10: seed install failed ($1)"
  set_tier "$_t" architect reasoning; set_tier "$_t" builder standard; set_tier "$_t" builder-heavy reasoning; set_tier "$_t" scout cheap
  set_pin "$_t" claude reasoning opus; set_pin "$_t" codex standard gpt-x; set_pin "$_t" opencode standard openai/x
  if [ "$2" = 1 ]; then put_pin "$_t" standard '"a/b"'; put_pin "$_t" reasoning '"bad pin;"'; put_pin "$_t" cheap '"a/b:high"'; fi
  CODEX_HOME="$_t/ch" sh "$SRC/harness-install.sh" --agents=claude,codex,opencode,antigravity "$_t" >/dev/null 2>&1 \
    || fail "R10: install failed ($1)"
  tsnap "$_t" > "$T/leak-$1.snap"
}
test_pi_pins_do_not_leak() {
  ( leak_target c1 0; echo done ) >"$T/leak-c1.res" 2>&1 &
  ( leak_target c2 0; echo done ) >"$T/leak-c2.res" 2>&1 &
  ( leak_target p 1; echo done ) >"$T/leak-p.res" 2>&1 &
  wait
  for _n in c1 c2 p; do [ "$(tail -n 1 "$T/leak-$_n.res")" = done ] || { cat "$T/leak-$_n.res" >&2; fail "R10: cell $_n failed"; }; done
  # control = paths that legitimately differ between two identical installs (paths, clocks).
  _bad="$(awk '
    FILENAME == ARGV[1] { a[$3] = $1 " " $2; next }
    FILENAME == ARGV[2] { if (a[$3] != $1 " " $2) ctl[$3] = 1; next }
    { if (!($3 in a) || a[$3] != $1 " " $2) if (!($3 in ctl) && $3 != "./.harness/harness.config.yaml") print $3 }
  ' "$T/leak-c1.snap" "$T/leak-c2.snap" "$T/leak-p.snap")"
  [ -z "$_bad" ] || fail "R10: pin.pi.* keys changed non-pi artifacts: $_bad"
  # the set of files must match too
  [ "$(awk '{print $3}' "$T/leak-c1.snap")" = "$(awk '{print $3}' "$T/leak-p.snap")" ] || fail "R10: pin.pi.* keys changed the file set"
}

# ── R11: the seed template and migrate_config converge ───────────────────────────────────
block_of() { # <config> <start-regex> <key>
  awk -v start="$2" -v key="$3" '
    $0 ~ start { p = 1 }
    p && seen && $0 !~ /^  / { exit }
    p { print }
    p && $0 ~ "^" key ":" { seen = 1 }
  ' "$1"
}
test_pi_seed_and_migrate_converge() {
  _seed="$SRC/harness.config.yaml"
  _m="$(awk '/^models:/{k=1;next} /^[a-z_]+:/{k=0} k' "$_seed")"
  printf '%s\n' "$_m" | grep -q '^  # pin\.pi\.cheap: ""$' || fail "R11a: the seed models: block lacks the pin.pi.* comment lines"
  printf '%s\n' "$_m" | tr '\n' ' ' | grep -qE 'pi ALSO derives[^.]{0,140}cheap=low standard=medium reasoning=high frontier=xhigh' \
    || fail "R11a: the seed models: block lacks the pi thinking ladder line"
  _bad="$(printf '%s\n' "$_m" | grep -vE '^[[:space:]]*(#.*)?$' | grep -vE '^  [a-z-]+: inherit([[:space:]]+#.*)?$' || true)"
  [ -z "$_bad" ] || fail "R11a: a non-comment models: value is not inherit: $_bad"
  # (b) migrate_config on a config with neither block appends byte-identical text.
  _t="$(mk pi-mig)"; mkdir -p "$_t/.harness"
  printf 'store:\n  backend: tasks-md\n' > "$_t/.harness/harness.config.yaml"
  run "$_t" pi
  _mc="$(cfg "$_t")"
  [ "$(block_of "$_seed" '^# Per-role model routing' models)" = "$(block_of "$_mc" '^# Per-role model routing' models)" ] \
    || fail "R11b: the migrate_config models: block differs from the seed's"
  [ -n "$(block_of "$_mc" '^# Per-role model routing' models)" ] || fail "R11b: models: block was not migrated in"
  [ "$(block_of "$_seed" '^# Deterministic Builder escalation' escalation)" = "$(block_of "$_mc" '^# Deterministic Builder escalation' escalation)" ] \
    || fail "R11b: the migrate_config escalation: block differs from the seed's"
  [ -n "$(block_of "$_mc" '^# Deterministic Builder escalation' escalation)" ] || fail "R11b: escalation: block was not migrated in"
  block_of "$_seed" '^# Deterministic Builder escalation' escalation | tr '\n' ' ' | grep -qE 'pi +a tier alone stamps NO `model`[^.]{0,200}thinking' \
    || fail "R11a: the escalation: comments lack the pi arming row"
  # (c) a lone commented pin line stamps nothing.
  _t="$(mk pi-mig-c)"; run "$_t" pi; set_tier "$_t" builder standard
  sed 's|^  # pin\.pi\.cheap: .*|  # pin.pi.standard: "a/b"|' "$(cfg "$_t")" > "$(cfg "$_t").t" && mv "$(cfg "$_t").t" "$(cfg "$_t")"
  run "$_t" pi
  grep -q '^model:' "$(pi_file "$_t" builder)" && fail "R11c: a commented pin line resolved"
  return 0
}

test_tier_resolution_order
pass "tier resolves role → models.default → inherit (R4)"
test_inherit_is_omission
pass "inherit compiles to key omission on the tier AND the pin path; the literal string is never generated (R5)"
test_builtin_tier_aliases
pass "built-in floating aliases for claude; no harness-frozen model id (R6)"
test_unpinned_codex_opencode_omits
pass "unpinned codex/opencode omit the key and advise exactly once per (front-end, tier) (R7)"
test_pin_overrides_verbatim
pass "models.pin.<front-end>.<tier> overrides the alias and is written verbatim (R8)"
test_unknown_tier_warns_and_inherits
pass "unknown tier warns, resolves as inherit, exits 0 (R9)"
test_opencode_pin_format_guard
pass "an opencode pin without '/' warns and never reaches opencode.json (R10)"
test_frontier_tier_claude_alias
pass "E99-F159: the frontier tier resolves to the floating fable alias on claude"
test_frontier_unpinned_codex_opencode_omits
pass "E99-F159: an unpinned frontier tier stamps no model on codex/opencode"
test_frontier_pin_honored
pass "E99-F159: pin.codex.frontier / pin.opencode.frontier are honored; the provider/model guard still applies"
test_codex_effort_rides_tier
pass "E99-F161: codex model_reasoning_effort rides the same tier as model, with no pin required and no key for inherit"
test_codex_effort_builtin_ladder_is_fixed
pass "E99-F161: the built-in tier->effort ladder is fixed and never emits model-specific 'ultra'"
test_codex_effort_guard_rejects_bad_value
pass "E99-F161: an invalid built-in effort value is rejected by the guard; removing the guard lets it through"
test_opencode_json_model_member
pass "opencode agent.<role> carries a \"model\" member (R14)"
test_codex_agent_files_project_local
pass "codex .codex/agents/<role>.toml is project-local; \$CODEX_HOME is never touched (R16)"
test_codex_selected_preserves_foreign_and_edited
pass "selected Codex role installs preserve foreign/edited files through last-written ownership stamps"
test_codex_rejects_symlinked_role_destinations
pass "Codex role install/reclamation reject symlinked files and directories without touching external targets"
test_model_stamp_symlinks_are_not_followed
pass "model-agent stamp symlinks are never followed for routing or deselection"
test_new_trees_conditional
pass "Selected Codex always registers seven model-optional roles (R6, R7, R17)"
test_return_to_inherit_reconciles
pass "every role back to inherit regenerates seven model-less Codex roles (R8, R11, R17)"
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

test_pi_thinking_ladder
pass "E35-F03: the pi thinking ladder rides the tier with no pin, no key for inherit/unknown (R1)"
test_pi_thinking_guard_mutation
pass "E35-F03: a corrupt ladder value warns and stamps nothing; without the guard it lands (M2/M2b)"
test_pi_pin_grammar_table
pass "E35-F03: pi_pin_verdict matches the hostile-pin table (R2)"
test_pi_pin_stamped_e2e
pass "E35-F03: valid pi pins land byte-for-byte; unpinned tiers stamp no model; umbrella cascade (R2, R3d)"
test_pi_pin_rejects_hostile_e2e
pass "E35-F03: every rejected pin row warns once, echoes only form/suffix values, stamps no model, keeps thinking (R3)"
test_pi_pin_config_shapes
pass "E35-F03: commented, nested, unknown-tier, inherit-only, empty and multi-line pin shapes (R3)"
test_pi_pin_guard_mutation
pass "E35-F03: neutralizing the pin verdict lets row 25 reach model: (M1)"
test_pi_models_any
pass "E35-F03: models_any pi holds on thinking alone (R7)"
test_pi_escalation_verdict_cells
pass "E35-F03: pi verdict cells raise/same/none (R8)"
test_pi_verdict_mutation
pass "E35-F03: dropping the pi thinking axis flips raise to neither (M3)"
test_pi_pins_do_not_leak
pass "E35-F03: pin.pi.* keys change no artifact when pi is not selected (R10)"
test_pi_seed_and_migrate_converge
pass "E35-F03: seed comments document pi; migrate_config blocks are byte-identical (R11)"

echo "All model-routing tests passed."
