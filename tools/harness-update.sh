#!/bin/sh
# harness-update.sh — the installed harness's self-update tool (E38-F01).
#
#   sh tools/harness-update.sh check     run by .harness/init.sh on every gate run
#   sh tools/harness-update.sh upgrade   exec'd by init.sh after the human consents
#
# `check` asks the harness remote for its highest vX.Y.Z tag, prints ONE notice line when
# that is newer than .harness-version and, only at an interactive terminal, offers to
# install it. It can never hurt the gate: it returns 0 ("carry on") or 10 ("consent given,
# exec upgrade") and nothing else, it never blocks (the remote read is time-bounded and
# can never prompt for credentials) and every doubt degrades to silence.
#
# `upgrade` fetches the tag, previews what the human is about to replace, backs it up, runs
# THAT TAG'S OWN harness-install.sh (never a re-implementation of it) and then PROVES that
# harness.config.yaml values and the user prose in CLAUDE.md / AGENTS.md survived.
#   exit 3  upgraded; commit it (the E24 drift guard fails until then) and re-run init.sh
#   exit 2  declined at the preview; nothing in the target was written
#   exit 4  upgraded, but a protected file did NOT survive (originals are in the backup dir)
#   exit 5  fetch / installer failure
#
# SELF-REPLACEMENT. `upgrade` rewrites this very file (tools/ is a harness-owned directory
# the installer replaces). Two layers keep that safe: init.sh `exec`s us, so no gate process
# is left running over a changing body; and this file is NOTHING BUT function definitions
# ending in a single `main "$@"` line, so the interpreter has parsed all of it before the
# first byte of the body changes. Do not add top-level statements above that last line.
# (The installer also replaces the inode rather than writing in place, but nothing here may
# rely on that.)
#
# POSIX sh, no timeout(1), no jq, no gh: git is the only dependency.

# ── small helpers ──────────────────────────────────────────────────────────────────────
hu_init() {
  HARNESS_DIR="${HARNESS_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
  PROJECT_ROOT="$(dirname "$HARNESS_DIR")"
  HU_DIR="$HARNESS_DIR/progress/update-check"
  HU_REC="$HU_DIR/last"
  HU_REPO="$HU_DIR/repo"
  HU_TAB="$(printf '\t')"
}

# hu_cfg_update_value <key> — a scalar from INSIDE the top-level `update:` block only, so a
# same-named key elsewhere in the config can never be mistaken for it.
hu_cfg_update_value() {
  awk -v k="$1" '
    /^update:[[:space:]]*(#.*)?$/ { u = 1; next }
    u && /^[^[:space:]#]/ { u = 0 }
    u && $0 ~ ("^[[:space:]]+" k ":") {
      v = $0
      sub("^[[:space:]]+" k ":[[:space:]]*", "", v)
      if (v ~ /^"/)        { sub(/^"/, "", v);     i = index(v, "\""); if (i) v = substr(v, 1, i - 1) }
      else if (v ~ /^\047/) { sub(/^\047/, "", v); i = index(v, "\047"); if (i) v = substr(v, 1, i - 1) }
      else                 { sub(/[[:space:]]+#.*$/, "", v); sub(/[[:space:]]+$/, "", v) }
      print v; exit
    }
  ' "$HARNESS_DIR/harness.config.yaml" 2>/dev/null
}

# hu_remote — env (per run) → update.remote → the public harness. Caller rejects a `-` lead.
hu_remote() {
  _hr="${HARNESS_UPDATE_REMOTE:-}"
  [ -n "$_hr" ] || _hr="$(hu_cfg_update_value remote)"
  [ -n "$_hr" ] || _hr="https://github.com/araozmd/harness-sdd.git"
  printf '%s' "$_hr"
}

hu_num_or() { # <value> <default> — a non-negative integer, else the default
  case "$1" in ''|*[!0-9]*) printf '%s' "$2" ;; *) printf '%s' "$1" ;; esac
}

hu_norm() { printf '%s' "$1" | tr -d ' \r\n\t' | sed 's/^v//'; }

# hu_gt <a> <b> — true iff version a is numerically greater than b (three components).
hu_gt() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    split(a, x, "."); split(b, y, ".")
    for (i = 1; i <= 3; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 }
    exit 1 }'
}

hu_is_version() { printf '%s' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; }

# ── cache record: one key=value per line, like .harness/.agents ────────────────────────
hu_rec_get() { [ -f "$HU_REC" ] && sed -n "s/^$1=//p" "$HU_REC" | head -n 1; return 0; }

hu_rec_write() { # <checked> <latest> <declined-or-empty>
  mkdir -p "$HU_DIR" 2>/dev/null || return 0
  {
    printf 'checked=%s\nlatest=%s\n' "$1" "$2"
    [ -z "$3" ] || printf 'declined=%s\n' "$3"
  } > "$HU_REC.tmp.$$" 2>/dev/null && mv "$HU_REC.tmp.$$" "$HU_REC" 2>/dev/null
  return 0
}

# hu_kill_tree <pid> — the process and everything below it, children first (a parent killed
# first would orphan them out of reach). `ps -A -o pid= -o ppid=` is POSIX and is on macOS and
# Linux alike; job control (`set -m`) is NOT used because dash ignores it without a terminal.
hu_kill_tree() {
  for _kc in $(ps -A -o pid= -o ppid= 2>/dev/null | awk -v p="$1" '$2 == p { print $1 }'); do
    hu_kill_tree "$_kc"
  done
  kill -TERM "$1" 2>/dev/null
  return 0
}

# hu_ls_remote <remote> <outfile> — `git ls-remote --tags`, abandoned after the bound.
# GIT_TERMINAL_PROMPT=0 is what makes "interactive tool" and "cannot hang the gate" compatible:
# a private or mistyped remote fails instead of asking for a credential.
hu_ls_remote() {
  _lt="$(hu_num_or "${HARNESS_UPDATE_TIMEOUT:-}" 3)"
  _lmax=$((_lt * 10))
  {
    GIT_TERMINAL_PROMPT=0 git ls-remote --tags -- "$1" > "$2" 2>/dev/null &
    _lpid=$!
    _ln=0
    while kill -0 "$_lpid" 2>/dev/null; do
      if [ "$_ln" -ge "$_lmax" ]; then
        hu_kill_tree "$_lpid"
        wait "$_lpid" 2>/dev/null
        return 1
      fi
      sleep 0.1 2>/dev/null || sleep 1
      _ln=$((_ln + 1))
    done
    wait "$_lpid"
    return $?
  } 2>/dev/null
}

# hu_highest_tag <ls-remote-file> — the highest strict vX.Y.Z (peeled ^{}, pre-release suffixes,
# two-component and every other tag name never match). Prints X.Y.Z or nothing.
hu_highest_tag() {
  awk '$2 ~ /^refs\/tags\/v[0-9]+\.[0-9]+\.[0-9]+$/ { sub(/^refs\/tags\/v/, "", $2); print $2 }' "$1" \
    | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1
}

# hu_interactive — stdin AND stdout are terminals, or the test hook says to behave as if.
hu_interactive() {
  [ -n "${HARNESS_UPDATE_ASSUME_TTY:-}" ] || { [ -t 0 ] && [ -t 1 ]; }
}

# hu_resolve_latest <remote> <honour-ttl> — sets HU_LATEST (vX.Y.Z or empty) and HU_DECLINED.
# honour-ttl=1: a record younger than the TTL answers without contacting the remote.
hu_resolve_latest() {
  _rr="$1"; _rttl="$2"
  _rttlv="$(hu_num_or "${HARNESS_UPDATE_TTL:-}" 86400)"
  _rnow="$(date +%s)"
  _rchk="$(hu_rec_get checked)"
  HU_DECLINED="$(hu_rec_get declined)"
  case "$_rchk" in ''|*[!0-9]*) _rchk="" ;; esac
  if [ "$_rttl" = 1 ] && [ -n "$_rchk" ] && [ "$_rnow" -ge "$_rchk" ] && [ $((_rnow - _rchk)) -lt "$_rttlv" ]; then
    HU_LATEST="$(hu_rec_get latest)"
    return 0
  fi
  _rtmp="$HU_DIR/ls-remote.$$"
  mkdir -p "$HU_DIR" 2>/dev/null
  HU_LATEST=""
  if hu_ls_remote "$_rr" "$_rtmp"; then
    _rv="$(hu_highest_tag "$_rtmp")"
    [ -z "$_rv" ] || HU_LATEST="v$_rv"
  fi
  rm -f "$_rtmp"
  # `declined` only means something for the version it was said about.
  [ "$HU_DECLINED" = "$HU_LATEST" ] || HU_DECLINED=""
  hu_rec_write "$_rnow" "$HU_LATEST" "$HU_DECLINED"
  return 0
}

hu_record_declined() { # <vX.Y.Z>
  _dchk="$(hu_rec_get checked)"; [ -n "$_dchk" ] || _dchk="$(date +%s)"
  hu_rec_write "$_dchk" "$1" "$1"
}

# ── check ──────────────────────────────────────────────────────────────────────────────
hu_check_inner() {
  [ -f "$HARNESS_DIR/.harness-version" ] || exit 0
  [ -z "${HARNESS_SKIP_UPDATE_CHECK:-}" ] || exit 0
  [ -z "${HARNESS_UPDATE_CHILD:-}" ] || exit 0
  command -v git >/dev/null 2>&1 || exit 0
  [ "$(hu_cfg_update_value check)" != "false" ] || exit 0
  _cr="$(hu_remote)"
  case "$_cr" in -*) exit 0 ;; esac
  _cinst="$(hu_norm "$(cat "$HARNESS_DIR/.harness-version" 2>/dev/null)")"
  hu_is_version "$_cinst" || exit 0
  hu_resolve_latest "$_cr" 1
  [ -n "$HU_LATEST" ] || exit 0
  hu_gt "${HU_LATEST#v}" "$_cinst" || exit 0
  echo "🔔 harness $HU_LATEST available (installed v$_cinst)"
  hu_interactive || exit 0
  [ "$HU_DECLINED" != "$HU_LATEST" ] || exit 0
  printf 'Install now? [y/N] '
  _cans=""
  read -r _cans || _cans=""
  [ -t 0 ] || echo
  case "$_cans" in
    y|Y) exit 10 ;;
  esac
  hu_record_declined "$HU_LATEST"
  exit 0
}

hu_check() {
  # A subshell: whatever goes wrong inside degrades to "carry on", never to a gate failure.
  ( hu_check_inner )
  case $? in 10) return 10 ;; *) return 0 ;; esac
}

# ── upgrade ────────────────────────────────────────────────────────────────────────────
hu_fail() { echo "❌ upgrade: $1" >&2; exit 5; }

# hu_fetch <remote> <tag> <old-tag> — the tag checked out under progress/update-check/repo.
hu_fetch() {
  mkdir -p "$HU_DIR" || return 1
  if [ ! -d "$HU_REPO/.git" ]; then
    rm -rf "$HU_REPO"
    GIT_TERMINAL_PROMPT=0 git clone -q --no-checkout -- "$1" "$HU_REPO" >/dev/null 2>&1 || return 1
  fi
  GIT_TERMINAL_PROMPT=0 git -C "$HU_REPO" fetch -q --tags --force -- "$1" >/dev/null 2>&1 || return 1
  git -C "$HU_REPO" checkout -q -f "refs/tags/$2" >/dev/null 2>&1 || return 1
  [ -f "$HU_REPO/harness-install.sh" ] || return 1
  return 0
}

# hu_scope — "label<TAB>repo-root" for the target and, on a coordinator, each manifest child
# that holds a harness.config.yaml. The same minimal YAML read init.sh performs on the
# manifest: top-level `repos:` → `  <key>:` → `path:`.
hu_scope() {
  printf 'root\t%s\n' "$PROJECT_ROOT"
  [ -n "${HARNESS_UPDATE_UMBRELLA_MANIFEST:-}" ] && [ -f "$HARNESS_UPDATE_UMBRELLA_MANIFEST" ] || return 0
  awk -v base="${HARNESS_UPDATE_UMBRELLA_DIR:-.}" '
    /^repos:[[:space:]]*(#.*)?$/ { r = 1; next }
    r && /^[^[:space:]#]/ { r = 0 }
    r && /^  [A-Za-z0-9_-]+:[[:space:]]*(#.*)?$/ { key = $1; sub(/:$/, "", key); next }
    r && key != "" && /^[[:space:]]+path:/ {
      p = $0
      sub(/^[[:space:]]+path:[[:space:]]*/, "", p); sub(/[[:space:]]+#.*$/, "", p)
      gsub(/^"|"$|^\047|\047$/, "", p)
      if (p !~ /^\//) p = base "/" p
      print key "\t" p
      key = ""
    }
  ' "$HARNESS_UPDATE_UMBRELLA_MANIFEST" | while IFS="$HU_TAB" read -r _sl _sp; do
    [ -f "$_sp/.harness/harness.config.yaml" ] && printf '%s\t%s\n' "$_sl" "$_sp"
  done
  return 0
}

# hu_body_entries — the paths the FETCHED installer will copy, read from its own lists.
hu_body_entries() {
  _bp="$(sed -n "s/^HARNESS_BODY_PROSE='\(.*\)'$/\1/p" "$HU_REPO/harness-install.sh" 2>/dev/null | head -n 1)"
  _bl="$(sed -n "s/^HARNESS_BODY_LOCAL='\(.*\)'$/\1/p" "$HU_REPO/harness-install.sh" 2>/dev/null | head -n 1)"
  if [ -z "$_bp$_bl" ]; then
    HU_FALLBACK=1
    _bp='AGENTS.md agents docs specs/_templates'
    _bl='init.sh store tools umbrella.manifest.example.yaml umbrella.gitignore.example'
  else
    HU_FALLBACK=0
  fi
  printf '%s %s\n' "$_bp" "$_bl"
}

# hu_body_files <entries> — regular files, relative to .harness/, under those entries.
hu_body_files() {
  for _be in $1; do
    if [ -d "$HARNESS_DIR/$_be" ]; then
      ( cd "$HARNESS_DIR" && find "$_be" -type f ! -path '*/__pycache__/*' ! -name '*.pyc' ! -name .DS_Store )
    elif [ -f "$HARNESS_DIR/$_be" ] && [ ! -L "$HARNESS_DIR/$_be" ]; then
      printf '%s\n' "$_be"
    fi
  done | sort
}

# hu_conflicts <entries> <baseline-tag> — one line per locally edited / locally added file:
#   M<TAB>path<TAB>+A -D     A<TAB>path
hu_conflicts() {
  hu_body_files "$1" > "$HU_DIR/body-files.txt"
  while IFS= read -r _cf; do
    [ -n "$_cf" ] || continue
    if git -C "$HU_REPO" cat-file -e "refs/tags/$2:$_cf" 2>/dev/null; then
      git -C "$HU_REPO" show "refs/tags/$2:$_cf" > "$HU_DIR/baseline.tmp" 2>/dev/null
      if ! cmp -s "$HU_DIR/baseline.tmp" "$HARNESS_DIR/$_cf"; then
        _cc="$(diff "$HU_DIR/baseline.tmp" "$HARNESS_DIR/$_cf" 2>/dev/null \
          | awk '/^>/ { a++ } /^</ { d++ } END { printf "+%d -%d", a + 0, d + 0 }')"
        printf 'M\t%s\t%s\n' "$_cf" "$_cc"
      fi
    else
      printf 'A\t%s\n' "$_cf"
    fi
  done < "$HU_DIR/body-files.txt"
  rm -f "$HU_DIR/baseline.tmp"
}

# hu_outside_block <file> — the file with the harness block removed and trailing blank lines
# trimmed. The installer appends a block to a block-less entrypoint after ONE separating blank
# line; that separator belongs to the block, not to the user's prose, so it must not read as
# a change to the prose.
hu_outside_block() {
  awk '
    index($0, "<!-- harness:begin -->") { b = 1; next }
    index($0, "<!-- harness:end -->")   { b = 0; next }
    !b { buf[++n] = $0 }
    END { while (n > 0 && buf[n] == "") n--; for (i = 1; i <= n; i++) print buf[i] }
  ' "$1"
}

# hu_config_preserved <pre> <post> — every pre line present in post, in order (blank lines
# included); appended or inserted lines allowed. Greedy two-pointer = exact subsequence test.
# Strings are forced with `""` so awk never compares "1.0" and "1" as numbers.
hu_config_preserved() {
  awk 'NR == FNR { pre[++n] = $0 ""; next }
       { if (i < n && ($0 "") == pre[i + 1]) i++ }
       END { exit (i == n) ? 0 : 1 }' "$1" "$2"
}

hu_backup_dir() { # <old-version> — a fresh directory; an existing one is never reused
  _bb="$HARNESS_DIR/progress/upgrade-backup/$1"
  _bn=1
  while [ -e "$_bb" ]; do _bn=$((_bn + 1)); _bb="$HARNESS_DIR/progress/upgrade-backup/$1.$_bn"; done
  printf '%s' "$_bb"
}

hu_upgrade() {
  [ -f "$HARNESS_DIR/.harness-version" ] || hu_fail "no .harness-version here — not an installed harness"
  _uremote="$(hu_remote)"
  case "$_uremote" in -*) hu_fail "the update remote '$_uremote' begins with '-' — refusing it as a misconfiguration (set HARNESS_UPDATE_REMOTE or update.remote in harness.config.yaml)" ;; esac
  _uold="$(hu_norm "$(cat "$HARNESS_DIR/.harness-version")")"
  hu_is_version "$_uold" || hu_fail "cannot read the installed version from .harness-version"
  command -v git >/dev/null 2>&1 || hu_fail "git is not on PATH"

  HU_DECLINED=""; HU_LATEST="$(hu_rec_get latest)"
  [ -n "$HU_LATEST" ] || hu_resolve_latest "$_uremote" 0
  _unew="$HU_LATEST"
  [ -n "$_unew" ] || hu_fail "the remote advertises no vX.Y.Z tag to upgrade to"
  hu_gt "${_unew#v}" "$_uold" || hu_fail "$_unew is not newer than the installed v$_uold"
  _ubk_would="$HARNESS_DIR/progress/upgrade-backup/$_uold"

  # 1. fetch — before the preview, because the preview is computed from the FETCHED installer.
  if ! hu_fetch "$_uremote" "$_unew"; then
    echo "❌ upgrade: could not fetch $_unew from $_uremote — nothing was changed (no backup was made; it would have gone to $_ubk_would)" >&2
    exit 5
  fi

  # 2/3. what the fetched installer will replace, and what of it is locally edited
  _uentries="$(hu_body_entries)"
  if git -C "$HU_REPO" rev-parse -q --verify "refs/tags/v$_uold^{commit}" >/dev/null 2>&1; then
    _ubase="v$_uold"; _ubasenote=""
  else
    _ubase="$_unew"
    _ubasenote="v$_uold is not on the remote — comparing local files against the incoming $_unew instead"
  fi
  hu_conflicts "$_uentries" "$_ubase" > "$HU_DIR/conflicts.txt"
  hu_scope > "$HU_DIR/scope.txt"

  # 4. preview + the one question that gates every write
  echo "── harness upgrade preview: v$_uold → $_unew ──"
  echo "   remote:    $_uremote"
  echo "   installer: harness-install.sh from tag $_unew (run as-is, never re-implemented)"
  [ -z "$_ubasenote" ] || echo "   note:      $_ubasenote"
  [ "$HU_FALLBACK" = 0 ] || echo "   note:      the body list could not be read from the fetched installer — using the built-in list"
  if [ -s "$HU_DIR/conflicts.txt" ]; then
    echo "   These harness-owned files are locally changed and will be REPLACED (copies go to the backup first):"
    while IFS="$HU_TAB" read -r _ck _cp _cx; do
      if [ "$_ck" = M ]; then echo "     M $_cp ($_cx)"; else echo "     A $_cp local addition"; fi
    done < "$HU_DIR/conflicts.txt"
  else
    echo "   (no local edits to harness-owned files)"
  fi
  echo "   Preserved, and checked afterwards: every line of each harness.config.yaml (new keys may be appended)"
  echo "   and all CLAUDE.md / AGENTS.md text outside the harness block."
  printf 'Proceed with the upgrade? [y/N] '
  _uans=""
  read -r _uans || _uans=""
  [ -t 0 ] || echo
  case "$_uans" in
    y|Y) : ;;
    *)
      hu_record_declined "$_unew"
      echo "Upgrade declined — nothing was changed."
      exit 2
      ;;
  esac

  # 5. backups precede the installer
  _ubk="$(hu_backup_dir "$_uold")"
  mkdir -p "$_ubk" || hu_fail "cannot create the backup directory $_ubk"
  while IFS="$HU_TAB" read -r _ck _cp _cx; do
    [ -n "$_cp" ] || continue
    mkdir -p "$_ubk/$(dirname "$_cp")" && cp -p "$HARNESS_DIR/$_cp" "$_ubk/$_cp" \
      || hu_fail "cannot back up $_cp to $_ubk — nothing was replaced"
  done < "$HU_DIR/conflicts.txt"
  while IFS="$HU_TAB" read -r _sl _sp; do
    mkdir -p "$_ubk/preservation/$_sl"
    for _sf in .harness/harness.config.yaml CLAUDE.md AGENTS.md; do
      [ -f "$_sp/$_sf" ] && { cp -p "$_sp/$_sf" "$_ubk/preservation/$_sl/$(basename "$_sf")" \
        || hu_fail "cannot snapshot $_sp/$_sf to $_ubk — nothing was replaced"; }
    done
  done < "$HU_DIR/scope.txt"

  # 6/7. the fetched tag's own installer; stdin is not a terminal, so it takes its documented
  # non-interactive upgrade path (recorded selection, backend and pr_loop kept).
  echo "── running harness-install.sh from $_unew ──"
  if [ -n "${HARNESS_UPDATE_UMBRELLA_DIR:-}" ] && [ -f "${HARNESS_UPDATE_UMBRELLA_MANIFEST:-/nonexistent}" ]; then
    ( unset HARNESS_DIR; cd "$PROJECT_ROOT" && sh "$HU_REPO/harness-install.sh" --umbrella "$HARNESS_UPDATE_UMBRELLA_DIR" < /dev/null )
    _uirc=$?
    # 3 = "installed but unlanded" (E24-F02): the expected outcome of an upgrade nobody has committed.
    [ "$_uirc" = 0 ] || [ "$_uirc" = 3 ] && _uiok=1 || _uiok=0
  else
    ( unset HARNESS_DIR; cd "$PROJECT_ROOT" && sh "$HU_REPO/harness-install.sh" "$PROJECT_ROOT" < /dev/null )
    _uirc=$?
    [ "$_uirc" = 0 ] && _uiok=1 || _uiok=0
  fi
  if [ "$_uiok" != 1 ]; then
    echo "❌ upgrade: the $_unew installer exited $_uirc. Your originals are in $_ubk — nothing was committed." >&2
    exit 5
  fi
  _unow="$(hu_norm "$(cat "$HARNESS_DIR/.harness-version" 2>/dev/null)")"
  if [ "v$_unow" != "$_unew" ]; then
    echo "❌ upgrade: the installer finished but .harness-version reads v$_unow, not $_unew. Your originals are in $_ubk." >&2
    exit 5
  fi

  # 8. the proof — what was promised is verified, not assumed
  echo "── preservation check ──"
  _uviol=0
  while IFS="$HU_TAB" read -r _sl _sp; do
    _snap="$_ubk/preservation/$_sl"
    if [ -f "$_snap/harness.config.yaml" ]; then
      if [ -f "$_sp/.harness/harness.config.yaml" ] && hu_config_preserved "$_snap/harness.config.yaml" "$_sp/.harness/harness.config.yaml"; then
        echo "✅ preserved $_sl harness.config.yaml"
      else
        echo "❌ changed $_sl harness.config.yaml (original: $_snap/harness.config.yaml)"; _uviol=1
      fi
    fi
    for _sf in CLAUDE.md AGENTS.md; do
      [ -f "$_snap/$_sf" ] || continue
      hu_outside_block "$_snap/$_sf" > "$HU_DIR/outside.pre"
      if [ -f "$_sp/$_sf" ]; then hu_outside_block "$_sp/$_sf" > "$HU_DIR/outside.post"; else : > "$HU_DIR/outside.post"; echo "-missing-" >> "$HU_DIR/outside.post"; fi
      if cmp -s "$HU_DIR/outside.pre" "$HU_DIR/outside.post"; then
        echo "✅ preserved $_sl $_sf"
      else
        echo "❌ changed $_sl $_sf (original: $_snap/$_sf)"; _uviol=1
      fi
    done
  done < "$HU_DIR/scope.txt"
  rm -f "$HU_DIR/outside.pre" "$HU_DIR/outside.post"

  # 9. report. Never commits: that is the human's call.
  echo "── harness upgraded: v$_uold → $_unew ──"
  echo "   backup:  $_ubk"
  echo "   The upgrade is NOT committed. The init.sh drift guard fails until you commit it"
  echo "   (git add -A && git commit), because agents must not run on a body no commit describes."
  echo "   Re-run init.sh afterwards."
  if [ "$_uviol" = 1 ]; then
    echo "❌ a protected file did not survive the upgrade — restore it from $_ubk/preservation before committing." >&2
    exit 4
  fi
  exit 3
}

main() {
  hu_init
  case "${1:-}" in
    check)   hu_check ;;
    upgrade) hu_upgrade ;;
    *) echo "usage: harness-update.sh check|upgrade" >&2; return 64 ;;
  esac
}

main "$@"
