#!/bin/sh
# Create, enter, and safely retire one deterministic fix worktree.

set -u

die() { echo "fix-worktree: $*" >&2; exit 1; }

usage() {
  die "usage: fix-worktree.sh create <E99-Fn> <slug> [--base <branch>] | run <E99-Fn> <slug> -- <command> [args...] | teardown <E99-Fn> <slug> [--base <branch>]"
}

validate_key() {
  case "$FIX_ID" in
    E99-F*[!0-9]*|E99-F) die "invalid fix id: $FIX_ID" ;;
    E99-F[0-9]*) : ;;
    *) die "invalid fix id: $FIX_ID" ;;
  esac
  case "$FIX_SLUG" in
    ''|*[!a-z0-9-]*|-*|*-) die "invalid slug: $FIX_SLUG" ;;
    *--*) die "invalid slug: $FIX_SLUG" ;;
  esac
}

absolute_dir() {
  (CDPATH= cd -- "$1" 2>/dev/null && pwd -P)
}

resolve_repository() {
  CALLER_TOP="$(git rev-parse --show-toplevel 2>/dev/null)" ||
    die "must run inside a non-bare Git worktree"
  CALLER_TOP="$(absolute_dir "$CALLER_TOP")" ||
    die "cannot resolve caller worktree"
  COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ||
    die "cannot resolve shared Git directory"
  COMMON_DIR="$(absolute_dir "$COMMON_DIR")" ||
    die "cannot resolve shared Git directory"

  PRIMARY=
  PRIMARY_COUNT=0
  while IFS= read -r _line; do
    case "$_line" in
      "worktree "*)
        _candidate=${_line#worktree }
        # Missing linked-worktree paths are handled as explicit stale-registration
        # state by teardown. They cannot be the canonical primary because only an
        # existing checkout can expose the shared Git directory.
        [ -d "$_candidate" ] || continue
        _candidate_git="$(git -C "$_candidate" rev-parse --absolute-git-dir 2>/dev/null)" ||
          die "cannot inspect registered worktree: $_candidate"
        _candidate_git="$(absolute_dir "$_candidate_git")" ||
          die "cannot resolve Git directory for: $_candidate"
        if [ "$_candidate_git" = "$COMMON_DIR" ]; then
          PRIMARY="$(absolute_dir "$_candidate")"
          PRIMARY_COUNT=$((PRIMARY_COUNT + 1))
        fi
        ;;
      bare) die "bare worktree records are unsupported" ;;
    esac
  done <<EOF
$(git worktree list --porcelain 2>/dev/null)
EOF
  [ "$PRIMARY_COUNT" -eq 1 ] ||
    die "cannot identify exactly one canonical primary worktree"

  SELF_DIR="$(absolute_dir "$(dirname -- "$0")")" ||
    die "cannot locate helper"
  case "$SELF_DIR" in
    "$CALLER_TOP/tools") LAYOUT=source; HARNESS_MAIN="$PRIMARY" ;;
    "$CALLER_TOP/.harness/tools") LAYOUT=installed; HARNESS_MAIN="$PRIMARY/.harness" ;;
    *) die "helper must run from tools/ or .harness/tools/ in the caller worktree" ;;
  esac
  BRANCH="feat/$FIX_ID-$FIX_SLUG"
  WORKTREE="$PRIMARY/.claude/worktrees/$FIX_ID-$FIX_SLUG"
}

parse_base() {
  EXPLICIT_BASE=
  if [ "$#" -gt 0 ]; then
    [ "$#" -eq 2 ] && [ "$1" = "--base" ] || usage
    EXPLICIT_BASE=$2
  fi
  if [ -n "$EXPLICIT_BASE" ]; then
    BASE=$EXPLICIT_BASE
  else
    _remote_head="$(git -C "$PRIMARY" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null || :)"
    case "$_remote_head" in
      refs/remotes/origin/*) BASE=${_remote_head#refs/remotes/origin/} ;;
      *) BASE=main ;;
    esac
  fi
  case "$BASE" in -*) die "invalid local base branch: $BASE" ;; refs/*) die "base must be a short local branch name: $BASE" ;; esac
  git check-ref-format --branch "$BASE" >/dev/null 2>&1 ||
    die "invalid local base branch: $BASE"
  BASE_COMMIT="$(git -C "$PRIMARY" rev-parse --verify "refs/heads/$BASE^{commit}" 2>/dev/null)" ||
    die "local base branch does not exist: $BASE"
  _exact="$(git -C "$PRIMARY" for-each-ref --format='%(refname:short)' "refs/heads/$BASE")"
  [ "$_exact" = "$BASE" ] || die "base is not an exact local branch: $BASE"
}

primary_clean() {
  [ -z "$(git -C "$PRIMARY" status --porcelain --untracked-files=all)" ]
}

registration_record() {
  FOUND_REG=0
  REG_BRANCH=
  REG_HEAD=
  _in=0
  while IFS= read -r _line; do
    case "$_line" in
      "worktree "*)
        if [ "${_line#worktree }" = "$WORKTREE" ]; then FOUND_REG=1; _in=1; else _in=0; fi
        ;;
      "HEAD "*) [ "$_in" -eq 1 ] && REG_HEAD=${_line#HEAD } ;;
      "branch "*) [ "$_in" -eq 1 ] && REG_BRANCH=${_line#branch refs/heads/} ;;
      '') _in=0 ;;
    esac
  done <<EOF
$(git -C "$PRIMARY" worktree list --porcelain 2>/dev/null)
EOF
}

remove_managed_links() {
  for _rel in .claude/settings.local.json AGENTS.local.md CLAUDE.local.md AGENTS.override.md; do
    _src="$PRIMARY/$_rel"
    _dst="$WORKTREE/$_rel"
    if [ -L "$_dst" ]; then
      _target="$(readlink "$_dst")"
      [ "$_target" = "$_src" ] ||
        return 1
      rm "$_dst" || return 1
    elif [ -e "$_dst" ]; then
      return 1
    fi
  done
}

verify_managed_links() {
  for _rel in .claude/settings.local.json AGENTS.local.md CLAUDE.local.md AGENTS.override.md; do
    _src="$PRIMARY/$_rel"
    _dst="$WORKTREE/$_rel"
    if [ -L "$_dst" ]; then
      [ "$(readlink "$_dst")" = "$_src" ] || return 1
    elif [ -e "$_dst" ]; then
      return 1
    fi
  done
}

verify_rollback_managed_links() {
  for _rel in .claude/settings.local.json AGENTS.local.md CLAUDE.local.md AGENTS.override.md; do
    _src="$PRIMARY/$_rel"
    _dst="$WORKTREE/$_rel"
    case " $CREATED_MANAGED_LINKS " in
      *" $_rel "*)
        [ -L "$_dst" ] && [ "$(readlink "$_dst")" = "$_src" ] ||
          return 1
        ;;
      *)
        [ ! -e "$_dst" ] && [ ! -L "$_dst" ] ||
          return 1
        ;;
    esac
  done
}

materialize_links() {
  for _rel in .claude/settings.local.json AGENTS.local.md CLAUDE.local.md AGENTS.override.md; do
    _src="$PRIMARY/$_rel"
    _dst="$WORKTREE/$_rel"
    [ -e "$_src" ] || continue
    if [ -e "$_dst" ] || [ -L "$_dst" ]; then
      echo "fix-worktree: unexpected personal-layer destination: $_dst" >&2
      return 1
    fi
    mkdir -p "$(dirname "$_dst")" || return 1
    ln -s "$_src" "$_dst" || return 1
    CREATED_MANAGED_LINKS="$CREATED_MANAGED_LINKS $_rel"
  done
}

rollback_create() {
  if ! verify_rollback_managed_links; then
    echo "fix-worktree: provisioning failed; a managed personal-layer destination changed; preserved worktree $WORKTREE and branch $BRANCH for recovery" >&2
    return 1
  fi
  _head="$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null || :)"
  _branch="$(git -C "$WORKTREE" symbolic-ref --short -q HEAD 2>/dev/null || :)"
  _dirty="$(git -C "$WORKTREE" status --porcelain --untracked-files=all 2>/dev/null || echo dirty)"
  if [ "$_head" = "$BASE_COMMIT" ] && [ "$_branch" = "$BRANCH" ] && [ -z "$_dirty" ]; then
    if ! remove_managed_links >/dev/null 2>&1; then
      echo "fix-worktree: provisioning failed; managed personal-layer cleanup failed; preserved worktree $WORKTREE and branch $BRANCH for recovery" >&2
      return 1
    fi
    if git -C "$PRIMARY" worktree remove "$WORKTREE" >/dev/null 2>&1; then
      if ! git -C "$PRIMARY" worktree prune --expire now >/dev/null 2>&1; then
        echo "fix-worktree: rollback removed worktree path but could not prune its registration; branch $BRANCH preserved" >&2
        return 1
      fi
      if ! git -C "$PRIMARY" update-ref -d "refs/heads/$BRANCH" "$BASE_COMMIT" >/dev/null 2>&1; then
        echo "fix-worktree: rollback removed worktree but exact branch deletion failed; preserved $BRANCH" >&2
        return 1
      fi
      return 0
    fi
  fi
  echo "fix-worktree: provisioning failed; preserved worktree $WORKTREE and branch $BRANCH for recovery" >&2
  return 1
}

do_create() {
  primary_clean || die "canonical primary checkout must be clean"
  [ ! -e "$WORKTREE" ] && [ ! -L "$WORKTREE" ] ||
    die "destination path already exists: $WORKTREE"
  git -C "$PRIMARY" show-ref --verify --quiet "refs/heads/$BRANCH" &&
    die "branch already exists: $BRANCH"
  registration_record
  [ "$FOUND_REG" -eq 0 ] || die "worktree registration already exists: $WORKTREE"

  CREATED_MANAGED_LINKS=
  mkdir -p "$(dirname "$WORKTREE")" || die "cannot create worktree parent"
  if ! git -C "$PRIMARY" worktree add -b "$BRANCH" "$WORKTREE" "$BASE_COMMIT" >/dev/null 2>&1; then
    die "git worktree creation failed for $WORKTREE"
  fi
  if ! materialize_links; then
    rollback_create || exit 1
    die "personal-layer provisioning failed and was rolled back"
  fi
  if [ "$LAYOUT" = source ]; then
    _init="$WORKTREE/init.sh"
  else
    _init="$WORKTREE/.harness/init.sh"
  fi
  if [ ! -x "$_init" ] || ! (cd "$WORKTREE" && "$_init"); then
    rollback_create || exit 1
    die "initialization failed and provisioning was rolled back"
  fi
  printf '%s\n' "$WORKTREE"
}

verify_exact_worktree() {
  registration_record
  [ "$FOUND_REG" -eq 1 ] || die "expected worktree is not registered: $WORKTREE"
  [ -d "$WORKTREE" ] || die "registered worktree path is absent: $WORKTREE"
  _branch="$(git -C "$WORKTREE" symbolic-ref --short -q HEAD 2>/dev/null || :)"
  [ "$_branch" = "$BRANCH" ] ||
    die "worktree has unexpected branch: ${_branch:-detached}; expected $BRANCH"
}

do_run() {
  verify_exact_worktree
  [ "$#" -ge 2 ] && [ "$1" = "--" ] || usage
  shift
  (cd "$WORKTREE" && HARNESS_DIR="$HARNESS_MAIN" export HARNESS_DIR && "$@")
}

require_primary_on_base() {
  primary_clean || die "canonical primary checkout must be clean for teardown"
  _primary_branch="$(git -C "$PRIMARY" symbolic-ref --short -q HEAD 2>/dev/null || :)"
  [ "$_primary_branch" = "$BASE" ] ||
    die "canonical primary must be checked out on resolved base $BASE"
  _primary_head="$(git -C "$PRIMARY" rev-parse HEAD 2>/dev/null || :)"
  [ "$_primary_head" = "$BASE_COMMIT" ] ||
    die "canonical primary is not on captured base commit $BASE_COMMIT"
}

branch_merged() {
  git -C "$PRIMARY" merge-base --is-ancestor "$BRANCH" "$BASE_COMMIT" 2>/dev/null
}

do_teardown() {
  registration_record
  _branch_exists=0
  git -C "$PRIMARY" show-ref --verify --quiet "refs/heads/$BRANCH" && _branch_exists=1
  _path_exists=0
  { [ -e "$WORKTREE" ] || [ -L "$WORKTREE" ]; } && _path_exists=1

  [ "$FOUND_REG" -eq 1 ] || {
    [ "$_path_exists" -eq 0 ] || die "path exists without exact worktree registration: $WORKTREE"
    [ "$_branch_exists" -eq 1 ] || return 0
    require_primary_on_base
    branch_merged || die "feature branch is not merged into resolved base: $BRANCH"
    git -C "$PRIMARY" branch -d "$BRANCH" >/dev/null ||
      die "safe branch deletion failed; preserved $BRANCH"
    return 0
  }

  [ "$REG_BRANCH" = "$BRANCH" ] ||
    die "worktree registration has unexpected branch: ${REG_BRANCH:-detached}"
  [ "$_branch_exists" -eq 1 ] || die "registered worktree branch is absent: $BRANCH"
  _tip="$(git -C "$PRIMARY" rev-parse "refs/heads/$BRANCH")"
  [ "$REG_HEAD" = "$_tip" ] ||
    die "worktree registration HEAD does not match branch tip"
  require_primary_on_base
  branch_merged || die "feature branch is not merged into resolved base: $BRANCH"

  if [ "$_path_exists" -eq 0 ]; then
    git -C "$PRIMARY" worktree prune --expire now >/dev/null ||
      die "could not prune stale worktree registration: $WORKTREE"
  else
    verify_exact_worktree
    verify_managed_links ||
      die "personal-layer destination changed; preserved worktree: $WORKTREE"
    [ -z "$(git -C "$WORKTREE" status --porcelain --untracked-files=all)" ] ||
      die "worktree has staged, unstaged, or untracked work; preserved: $WORKTREE"
    remove_managed_links ||
      die "could not remove unchanged managed links; preserved worktree: $WORKTREE"
    git -C "$PRIMARY" worktree remove "$WORKTREE" >/dev/null ||
      die "non-forced worktree removal failed; preserved: $WORKTREE"
    git -C "$PRIMARY" worktree prune --expire now >/dev/null ||
      die "worktree prune failed after removal"
  fi
  git -C "$PRIMARY" branch -d "$BRANCH" >/dev/null ||
    die "safe branch deletion failed; preserved $BRANCH"
}

[ "$#" -ge 3 ] || usage
OP=$1
FIX_ID=$2
FIX_SLUG=$3
shift 3
validate_key
resolve_repository

case "$OP" in
  create) parse_base "$@"; do_create ;;
  run) do_run "$@" ;;
  teardown) parse_base "$@"; do_teardown ;;
  *) usage ;;
esac
