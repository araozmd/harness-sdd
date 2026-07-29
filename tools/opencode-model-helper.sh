#!/usr/bin/env sh
# opencode-model-helper.sh — suggest per-tier model pins for the OpenCode front-end.
#
# OpenCode requires concrete "provider/model" ids (it has no floating tier alias),
# so the harness asks you to fill in `models.pin.opencode.<tier>` in
# harness.config.yaml. This script lists the models OpenCode currently sees and maps
# them to the harness tiers by name heuristic, so you can copy the snippet or apply it
# with --apply.
#
# Usage:
#   sh .harness/tools/opencode-model-helper.sh [--apply] [config-file]
#
# Without --apply it is a dry run: it prints the suggested pins and the manual steps.
# With --apply it appends missing pin lines to the existing models: block, or creates
# the block at the end of the file. Existing pins are never overwritten.

set -eu

# Default config path: when installed under .harness/tools/ the config lives at
# .harness/harness.config.yaml; in the source layout it lives at repo root.
_script_dir=$(cd "$(dirname "$0")" && pwd)
_default_config="$_script_dir/../harness.config.yaml"
[ -f "$_default_config" ] || _default_config="harness.config.yaml"

CONFIG="$_default_config"
APPLY=0

if [ "${1:-}" = "--apply" ]; then
  APPLY=1
  CONFIG="${2:-$_default_config}"
else
  CONFIG="${1:-$_default_config}"
fi

warn() { echo "⚠️  $1" >&2; }
info() { echo "   $1"; }
ok()   { echo "✅ $1"; }

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

if ! cmd_exists opencode; then
  warn "opencode not found on PATH — cannot list models"
  echo "Install the OpenCode CLI and re-run this helper, or set the pins by hand."
  exit 1
fi

MODELS="$(opencode models 2>/dev/null || true)"
if [ -z "$MODELS" ]; then
  warn "opencode models returned nothing"
  echo "Check that opencode is authenticated (opencode providers list)."
  exit 1
fi

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t harness-ocmh)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

# Heuristic tier classification. Lower tiers are checked first so a cheap-flash
# model does not accidentally win the standard tier.
classify_model() {
  _m="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$_m" in
    *opus*|*o1*|*o3*|*reasoning*|*claude-opus*|*claude-thinking*|*gemini-*-pro-thinking*)
      echo "reasoning" ;;
    *haiku*|*flash*|*nano*|*mini*|*lite*|*deepseek-v4-flash*|*glm-5.1*|*glm-5.2*)
      echo "cheap" ;;
    *sonnet*|*claude-sonnet*|*gpt-5*|*gpt-4*|*gemini-*pro*|*gemini-3.1*|*fable*|*deepseek-v4-pro*|*glm-5*)
      echo "standard" ;;
    *)
      echo "" ;;
  esac
}

: > "$TMP/reasoning"; : > "$TMP/standard"; : > "$TMP/cheap"

printf '%s\n' "$MODELS" | while IFS= read -r m; do
  [ -n "$m" ] || continue
  tier="$(classify_model "$m")"
  case "$tier" in
    reasoning) if [ ! -s "$TMP/reasoning" ]; then printf '%s\n' "$m" > "$TMP/reasoning"; fi ;;
    standard)  if [ ! -s "$TMP/standard" ];  then printf '%s\n' "$m" > "$TMP/standard";  fi ;;
    cheap)     if [ ! -s "$TMP/cheap" ];     then printf '%s\n' "$m" > "$TMP/cheap";     fi ;;
  esac
done

REASONING="$(cat "$TMP/reasoning")"
STANDARD="$(cat "$TMP/standard")"
CHEAP="$(cat "$TMP/cheap")"

echo ""
echo "Available OpenCode models:"
echo "--------------------------"
printf '%s\n' "$MODELS" | head -40
_model_count="$(printf '%s\n' "$MODELS" | grep -c '^' || true)"
if [ "$_model_count" -gt 40 ] 2>/dev/null; then
  info "... and $((_model_count - 40)) more"
fi

echo ""
echo "Suggested harness tier mapping (heuristic — review before applying):"
echo "--------------------------------------------------------------------"
[ -n "$REASONING" ] && echo "  reasoning → $REASONING"
[ -n "$STANDARD" ]  && echo "  standard  → $STANDARD"
[ -n "$CHEAP" ]     && echo "  cheap     → $CHEAP"
[ -z "$REASONING" ] && [ -z "$STANDARD" ] && [ -z "$CHEAP" ] && echo "  (none of the available models matched the heuristic tiers)"

{
  echo ""
  echo "Snippet to add under the models: block in $CONFIG:"
  echo "--------------------------------------------------"
  echo "  # OpenCode requires provider/model ids. Pin the tiers you want to use:"
  [ -n "$REASONING" ] && printf '  pin.opencode.reasoning: "%s"\n' "$REASONING"
  [ -n "$STANDARD" ]  && printf '  pin.opencode.standard:  "%s"\n' "$STANDARD"
  [ -n "$CHEAP" ]     && printf '  pin.opencode.cheap:     "%s"\n' "$CHEAP"
} > "$TMP/snippet"
cat "$TMP/snippet"

if [ "$APPLY" -eq 1 ]; then
  if ! cmd_exists python3; then
    warn "python3 not found — cannot apply automatically"
    echo "Add the snippet above by hand."
    exit 1
  fi

  if [ ! -f "$CONFIG" ]; then
    warn "$CONFIG not found — cannot apply"
    exit 1
  fi

  python3 - "$CONFIG" "$REASONING" "$STANDARD" "$CHEAP" <<'PY'
import sys

config_path = sys.argv[1]
reasoning = sys.argv[2] or None
standard = sys.argv[3] or None
cheap = sys.argv[4] or None

with open(config_path) as f:
    lines = f.read().splitlines()

# Find the models: block and its end.
models_start = None
models_end = None
for i, line in enumerate(lines):
    if models_start is None and line.strip().startswith("models:"):
        models_start = i
    elif models_start is not None and models_end is None:
        if line and not line.startswith(" ") and not line.startswith("\t") and not line.startswith("#"):
            models_end = i

if models_start is None:
    # Append a new block at EOF.
    lines.append("")
    lines.append("models:")
    lines.append("  default: inherit")
    models_end = len(lines)

# Build the pin lines to insert, skipping any already present.
existing_keys = {line.split(":", 1)[0].strip() for line in lines if ":" in line}
new_lines = []
if reasoning and "pin.opencode.reasoning" not in existing_keys:
    new_lines.append(f'  pin.opencode.reasoning: "{reasoning}"')
if standard and "pin.opencode.standard" not in existing_keys:
    new_lines.append(f'  pin.opencode.standard: "{standard}"')
if cheap and "pin.opencode.cheap" not in existing_keys:
    new_lines.append(f'  pin.opencode.cheap: "{cheap}"')

if not new_lines:
    print("All pins already present; nothing to apply.")
    sys.exit(0)

# Insert the new lines just before the end of the models block (or at EOF).
insert_at = models_end if models_end is not None else len(lines)
lines = lines[:insert_at] + new_lines + lines[insert_at:]

with open(config_path, "w") as f:
    f.write("\n".join(lines) + "\n")

print("Applied pins to", config_path)
PY
  ok "pins applied to $CONFIG (existing values were preserved)"
else
  echo ""
  echo "Run again with --apply to append these pins to $CONFIG,"
  echo "or add them by hand under the models: block."
fi
