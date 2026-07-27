#!/bin/sh
# test_fix_worktree.sh — disposable Git fixtures for tools/fix-worktree.sh.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d 2>/dev/null || mktemp -d -t fix-worktree)"
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

make_source_fixture() {
  _name="$1"
  FIXTURE="$TMP_ROOT/$_name"
  ORIGIN="$FIXTURE/origin.git"
  PRIMARY="$FIXTURE/primary"
  HELPER=tools/fix-worktree.sh
  git init --bare "$ORIGIN" >/dev/null
  git clone "$ORIGIN" "$PRIMARY" >/dev/null 2>&1
  git -C "$PRIMARY" config user.name "Fix Worktree Test"
  git -C "$PRIMARY" config user.email "fix-worktree@example.test"
  mkdir -p "$PRIMARY/tools"
  cp "$SRC/tools/fix-worktree.sh" "$PRIMARY/tools/fix-worktree.sh"
  chmod +x "$PRIMARY/tools/fix-worktree.sh"
  printf '#!/bin/sh\nexit 0\n' > "$PRIMARY/init.sh"
  chmod +x "$PRIMARY/init.sh"
  printf 'base\n' > "$PRIMARY/tracked.txt"
  printf '.claude/settings.local.json\n.claude/scheduled_tasks.lock\n.claude/worktrees/\nAGENTS.local.md\nCLAUDE.local.md\nAGENTS.override.md\narbitrary.secret\n' > "$PRIMARY/.gitignore"
  git -C "$PRIMARY" add .gitignore init.sh tools/fix-worktree.sh tracked.txt
  git -C "$PRIMARY" commit -m base >/dev/null
  git -C "$PRIMARY" branch -M main
  git -C "$PRIMARY" push -u origin main >/dev/null 2>&1
  git --git-dir="$ORIGIN" symbolic-ref HEAD refs/heads/main
  git -C "$PRIMARY" remote set-head origin main
}

test_create_exact_branch_and_path() {
  make_source_fixture create
  _out="$(cd "$PRIMARY" && tools/fix-worktree.sh create E99-F101 exact-path)"
  _primary_abs="$(CDPATH= cd -- "$PRIMARY" && pwd -P)"
  _expected="$_primary_abs/.claude/worktrees/E99-F101-exact-path"
  [ "$_out" = "$_expected" ] || fail "create stdout/path mismatch: $_out"
  [ "$(git -C "$_expected" symbolic-ref --short HEAD)" = "feat/E99-F101-exact-path" ] \
    || fail "create branch mismatch"
  pass "test_create_exact_branch_and_path"
}

assert_create_fails() {
  _needle=$1
  shift
  if (cd "$PRIMARY" && "$HELPER" "$@") >"$FIXTURE/out" 2>"$FIXTURE/err"; then
    fail "expected failure: $*"
  fi
  grep -qi "$_needle" "$FIXTURE/err" ||
    fail "failure did not name $_needle: $(cat "$FIXTURE/err")"
}

assert_create_fails_without_mutation() {
  _needle=$1
  _id=$2
  _slug=$3
  shift 3
  _refs_before="$(git -C "$PRIMARY" show-ref)"
  _registrations_before="$(git -C "$PRIMARY" worktree list --porcelain)"
  _destination="$PRIMARY/.claude/worktrees/$_id-$_slug"
  [ ! -e "$_destination" ] && [ ! -L "$_destination" ] ||
    fail "non-mutation precondition has an existing destination: $_destination"
  assert_create_fails "$_needle" create "$_id" "$_slug" "$@"
  [ "$(git -C "$PRIMARY" show-ref)" = "$_refs_before" ] ||
    fail "rejected create mutated refs: $_id $_slug $*"
  [ "$(git -C "$PRIMARY" worktree list --porcelain)" = "$_registrations_before" ] ||
    fail "rejected create mutated worktree registrations: $_id $_slug $*"
  [ ! -e "$_destination" ] && [ ! -L "$_destination" ] ||
    fail "rejected create made destination: $_destination"
}

test_default_and_explicit_base_resolution() {
  make_source_fixture bases
  git -C "$PRIMARY" branch release/1.2 main
  git -C "$PRIMARY" checkout -b ambient >/dev/null 2>&1
  printf 'ambient\n' >> "$PRIMARY/tracked.txt"
  git -C "$PRIMARY" commit -am ambient >/dev/null
  git -C "$PRIMARY" checkout main >/dev/null 2>&1
  _main="$(git -C "$PRIMARY" rev-parse main)"
  (cd "$PRIMARY" && tools/fix-worktree.sh create E99-F102 default-base) >/dev/null
  [ "$(git -C "$PRIMARY" rev-parse feat/E99-F102-default-base)" = "$_main" ] ||
    fail "default base did not use origin/HEAD local branch"
  (cd "$PRIMARY" && tools/fix-worktree.sh create E99-F103 explicit-base --base release/1.2) >/dev/null
  [ "$(git -C "$PRIMARY" rev-parse feat/E99-F103-explicit-base)" = "$(git -C "$PRIMARY" rev-parse release/1.2)" ] ||
    fail "explicit base was not honored"

  git -C "$PRIMARY" remote set-head origin -d
  (cd "$PRIMARY" && tools/fix-worktree.sh create E99-F104 fallback-main) >/dev/null
  [ "$(git -C "$PRIMARY" rev-parse feat/E99-F104-fallback-main)" = "$_main" ] ||
    fail "missing origin/HEAD did not fall back to main"

  git -C "$PRIMARY" checkout -b trunk main >/dev/null 2>&1
  printf 'trunk\n' >> "$PRIMARY/tracked.txt"
  git -C "$PRIMARY" commit -am trunk >/dev/null
  _trunk="$(git -C "$PRIMARY" rev-parse trunk)"
  git -C "$PRIMARY" push origin trunk >/dev/null 2>&1
  git -C "$PRIMARY" checkout main >/dev/null 2>&1
  git -C "$PRIMARY" remote set-head origin trunk
  (cd "$PRIMARY" && tools/fix-worktree.sh create E99-F131 non-main-default) >/dev/null
  [ "$(git -C "$PRIMARY" rev-parse feat/E99-F131-non-main-default)" = "$_trunk" ] ||
    fail "origin/HEAD default other than main was ignored"
  pass "test_default_and_explicit_base_resolution"
}

test_base_is_ref_not_ambient_head() {
  make_source_fixture ambient
  _base="$(git -C "$PRIMARY" rev-parse main)"
  git -C "$PRIMARY" checkout -b ambient >/dev/null 2>&1
  printf 'ambient\n' >> "$PRIMARY/tracked.txt"
  git -C "$PRIMARY" commit -am ambient >/dev/null
  (cd "$PRIMARY" && tools/fix-worktree.sh create E99-F105 no-ambient) >/dev/null
  [ "$(git -C "$PRIMARY" rev-parse feat/E99-F105-no-ambient)" = "$_base" ] ||
    fail "create used ambient HEAD instead of base ref"
  pass "test_base_is_ref_not_ambient_head"
}

test_dirty_primary_fails_before_mutation() {
  make_source_fixture dirty_unstaged
  printf 'dirty\n' >> "$PRIMARY/tracked.txt"
  assert_create_fails_without_mutation clean E99-F106 dirty-unstaged

  make_source_fixture dirty_staged
  printf 'staged\n' >> "$PRIMARY/tracked.txt"
  git -C "$PRIMARY" add tracked.txt
  assert_create_fails_without_mutation clean E99-F132 dirty-staged

  make_source_fixture dirty_untracked
  printf 'untracked\n' > "$PRIMARY/not-ignored.txt"
  assert_create_fails_without_mutation clean E99-F133 dirty-untracked
  pass "test_dirty_primary_fails_before_mutation"
}

test_invalid_inputs_are_non_mutating() {
  make_source_fixture invalid
  assert_create_fails_without_mutation invalid E98-F1 slug
  assert_create_fails_without_mutation invalid E99-Fx slug
  assert_create_fails_without_mutation invalid E99-F107 Bad-Slug
  assert_create_fails_without_mutation invalid E99-F107 double--dash
  pass "test_invalid_inputs_are_non_mutating"
}

test_slug_rejection_is_locale_independent() {
  make_source_fixture locale_slug
  _ran=0
  for _loc in en_US.UTF-8 C; do
    # Skip gracefully where the locale is not installed; never fail on absence.
    locale -a 2>/dev/null | grep -qix "$_loc" || continue
    _ran=$((_ran + 1))
    for _slug in Bad-Slug UPPER caf.e; do
      _refs_before="$(git -C "$PRIMARY" show-ref)"
      _registrations_before="$(git -C "$PRIMARY" worktree list --porcelain)"
      _destination="$PRIMARY/.claude/worktrees/E99-F149-$_slug"
      [ ! -e "$_destination" ] && [ ! -L "$_destination" ] ||
        fail "locale slug precondition has an existing destination: $_destination"
      if (cd "$PRIMARY" && LC_ALL="$_loc" "$HELPER" create E99-F149 "$_slug") \
          >"$FIXTURE/out" 2>"$FIXTURE/err"; then
        fail "LC_ALL=$_loc accepted invalid slug: $_slug"
      fi
      grep -qi invalid "$FIXTURE/err" ||
        fail "LC_ALL=$_loc rejection did not name invalid: $(cat "$FIXTURE/err")"
      [ "$(git -C "$PRIMARY" show-ref)" = "$_refs_before" ] ||
        fail "LC_ALL=$_loc rejected slug mutated refs: $_slug"
      [ "$(git -C "$PRIMARY" worktree list --porcelain)" = "$_registrations_before" ] ||
        fail "LC_ALL=$_loc rejected slug mutated worktree registrations: $_slug"
      [ ! -e "$_destination" ] && [ ! -L "$_destination" ] ||
        fail "LC_ALL=$_loc rejected slug made destination: $_destination"
    done
  done
  [ "$_ran" -ge 1 ] || fail "no locale leg ran; expected at least the C locale"
  pass "test_slug_rejection_is_locale_independent"
}

test_base_accepts_short_local_ref_only() {
  make_source_fixture base_validation
  git -C "$PRIMARY" branch release/1.2 main
  (cd "$PRIMARY" && tools/fix-worktree.sh create E99-F108 release --base release/1.2) >/dev/null
  assert_create_fails_without_mutation base E99-F109 full-ref --base refs/heads/main
  assert_create_fails_without_mutation base E99-F134 revision --base main~1
  assert_create_fails_without_mutation base E99-F135 option --base --help
  assert_create_fails_without_mutation base E99-F136 missing --base missing
  pass "test_base_accepts_short_local_ref_only"
}

test_branch_path_and_registration_collisions_fail_closed() {
  make_source_fixture collisions
  git -C "$PRIMARY" branch feat/E99-F110-branch main
  assert_create_fails branch create E99-F110 branch
  mkdir -p "$PRIMARY/.claude/worktrees/E99-F111-path"
  assert_create_fails path create E99-F111 path

  _registered="$PRIMARY/.claude/worktrees/E99-F137-registration"
  git -C "$PRIMARY" worktree add -b unrelated-registration "$_registered" main >/dev/null 2>&1
  mv "$_registered" "$FIXTURE/registration-away"
  _registration_before="$(git -C "$PRIMARY" worktree list --porcelain)"
  assert_create_fails registration create E99-F137 registration
  [ "$(git -C "$PRIMARY" worktree list --porcelain)" = "$_registration_before" ] ||
    fail "registration collision was mutated"
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/unrelated-registration ||
    fail "registration collision branch was removed"
  pass "test_branch_path_and_registration_collisions_fail_closed"
}

test_two_active_worktrees_are_isolated() {
  make_source_fixture isolation
  _one="$(cd "$PRIMARY" && tools/fix-worktree.sh create E99-F112 one)"
  _two="$(cd "$PRIMARY" && tools/fix-worktree.sh create E99-F113 two)"
  printf 'one\n' > "$_one/tracked.txt"
  git -C "$_one" add tracked.txt
  printf 'two\n' > "$_two/tracked.txt"
  [ "$(git -C "$_one" symbolic-ref --short HEAD)" = feat/E99-F112-one ] || fail "first branch changed"
  [ "$(git -C "$_two" symbolic-ref --short HEAD)" = feat/E99-F113-two ] || fail "second branch changed"
  git -C "$_one" diff --cached --quiet && fail "first index was not independently staged"
  git -C "$_two" diff --cached --quiet || fail "second index was changed by first"
  [ "$(cat "$_one/tracked.txt")" = one ] && [ "$(cat "$_two/tracked.txt")" = two ] ||
    fail "worktree files are not isolated"
  pass "test_two_active_worktrees_are_isolated"
}

test_personal_layer_allowlist_only() {
  make_source_fixture links
  mkdir -p "$PRIMARY/.claude"
  printf '{}\n' > "$PRIMARY/.claude/settings.local.json"
  printf lock > "$PRIMARY/.claude/scheduled_tasks.lock"
  printf agents > "$PRIMARY/AGENTS.local.md"
  printf claude > "$PRIMARY/CLAUDE.local.md"
  printf codex > "$PRIMARY/AGENTS.override.md"
  printf secret > "$PRIMARY/arbitrary.secret"
  _wt="$(cd "$PRIMARY" && tools/fix-worktree.sh create E99-F114 links)"
  for _rel in .claude/settings.local.json AGENTS.local.md CLAUDE.local.md AGENTS.override.md; do
    [ -L "$_wt/$_rel" ] || fail "allowlisted file not linked: $_rel"
    [ "$(readlink "$_wt/$_rel")" = "$(CDPATH= cd -- "$PRIMARY" && pwd -P)/$_rel" ] ||
      fail "allowlisted link is not absolute/canonical: $_rel"
  done
  [ ! -e "$_wt/.claude/scheduled_tasks.lock" ] || fail "scheduler lock was linked"
  [ ! -e "$_wt/arbitrary.secret" ] || fail "arbitrary ignored file was linked"
  [ -z "$(git -C "$_wt" status --porcelain --untracked-files=all)" ] ||
    fail "managed personal links dirtied worktree"

  mv "$PRIMARY/AGENTS.override.md" "$FIXTURE/AGENTS.override.md-away"
  _missing_wt="$(cd "$PRIMARY" && tools/fix-worktree.sh create E99-F138 missing-link)"
  [ ! -e "$_missing_wt/AGENTS.override.md" ] && [ ! -L "$_missing_wt/AGENTS.override.md" ] ||
    fail "missing allowlisted source created a destination"
  [ -L "$_missing_wt/AGENTS.local.md" ] ||
    fail "existing allowlisted source was not linked in missing-source case"
  pass "test_personal_layer_allowlist_only"
}

test_source_and_installed_init_gate() {
  make_source_fixture init_source
  printf '#!/bin/sh\npwd > .source-init-ran\nprintf "source init banner\\n"\nprintf "source init diagnostic\\n" >&2\nexit 0\n' > "$PRIMARY/init.sh"
  printf '.source-init-ran\n.installed-init-ran\n' >> "$PRIMARY/.gitignore"
  git -C "$PRIMARY" add init.sh
  git -C "$PRIMARY" add .gitignore
  git -C "$PRIMARY" commit -m init-record >/dev/null
  (cd "$PRIMARY" && tools/fix-worktree.sh create E99-F115 source-init) \
    >"$FIXTURE/source.out" 2>"$FIXTURE/source.err"
  _source_wt="$(cat "$FIXTURE/source.out")"
  [ "$(wc -l < "$FIXTURE/source.out" | tr -d ' ')" -eq 1 ] ||
    fail "source-layout create stdout was not exactly one line: $(cat "$FIXTURE/source.out")"
  case "$_source_wt" in
    /*) : ;;
    *) fail "source-layout create stdout was not an absolute path: $_source_wt" ;;
  esac
  grep -q '^source init banner$' "$FIXTURE/source.err" ||
    fail "source-layout init stdout was not redirected to stderr"
  grep -q '^source init diagnostic$' "$FIXTURE/source.err" ||
    fail "source-layout init stderr diagnostic was not preserved"
  [ "$(cat "$_source_wt/.source-init-ran")" = "$_source_wt" ] ||
    fail "source-layout init did not run in the new worktree"

  make_source_fixture init_installed
  mkdir -p "$PRIMARY/.harness/tools"
  mv "$PRIMARY/tools/fix-worktree.sh" "$PRIMARY/.harness/tools/fix-worktree.sh"
  mkdir -p "$PRIMARY/.harness"
  printf '#!/bin/sh\npwd > .installed-init-ran\nprintf "installed init banner\\n"\nprintf "installed init diagnostic\\n" >&2\nexit 0\n' > "$PRIMARY/.harness/init.sh"
  printf '.installed-init-ran\n' >> "$PRIMARY/.gitignore"
  chmod +x "$PRIMARY/.harness/init.sh" "$PRIMARY/.harness/tools/fix-worktree.sh"
  git -C "$PRIMARY" rm tools/fix-worktree.sh >/dev/null
  git -C "$PRIMARY" add .harness
  git -C "$PRIMARY" add .gitignore
  git -C "$PRIMARY" commit -m installed-layout >/dev/null
  HELPER=.harness/tools/fix-worktree.sh
  (cd "$PRIMARY" && .harness/tools/fix-worktree.sh create E99-F116 installed-init) \
    >"$FIXTURE/installed.out" 2>"$FIXTURE/installed.err"
  _installed_wt="$(cat "$FIXTURE/installed.out")"
  [ "$(wc -l < "$FIXTURE/installed.out" | tr -d ' ')" -eq 1 ] ||
    fail "installed-layout create stdout was not exactly one line: $(cat "$FIXTURE/installed.out")"
  case "$_installed_wt" in
    /*) : ;;
    *) fail "installed-layout create stdout was not an absolute path: $_installed_wt" ;;
  esac
  grep -q '^installed init banner$' "$FIXTURE/installed.err" ||
    fail "installed-layout init stdout was not redirected to stderr"
  grep -q '^installed init diagnostic$' "$FIXTURE/installed.err" ||
    fail "installed-layout init stderr diagnostic was not preserved"
  [ "$(cat "$_installed_wt/.installed-init-ran")" = "$_installed_wt" ] ||
    fail "installed-layout init did not run in the new worktree"

  printf '#!/bin/sh\nprintf "failing init banner\\n"\nprintf "failing init diagnostic\\n" >&2\nexit 17\n' > "$PRIMARY/.harness/init.sh"
  git -C "$PRIMARY" commit -am installed-init-failure >/dev/null
  assert_create_fails initialization create E99-F139 installed-init-fail
  grep -q '^failing init banner$' "$FIXTURE/err" ||
    fail "failing installed init stdout was not redirected to stderr"
  grep -q '^failing init diagnostic$' "$FIXTURE/err" ||
    fail "failing installed init stderr diagnostic was not preserved"
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/feat/E99-F139-installed-init-fail &&
    fail "installed-layout init failure left branch"
  [ ! -e "$PRIMARY/.claude/worktrees/E99-F139-installed-init-fail" ] ||
    fail "installed-layout init failure left path"
  pass "test_source_and_installed_init_gate"
}

test_init_failure_triggers_safe_rollback() {
  make_source_fixture init_failure
  printf '#!/bin/sh\nprintf "failing source init banner\\n"\nprintf "failing source init diagnostic\\n" >&2\nexit 9\n' > "$PRIMARY/init.sh"
  git -C "$PRIMARY" commit -am failing-init >/dev/null
  assert_create_fails initialization create E99-F117 init-fail
  grep -q '^failing source init banner$' "$FIXTURE/err" ||
    fail "failing source init stdout was not redirected to stderr"
  grep -q '^failing source init diagnostic$' "$FIXTURE/err" ||
    fail "failing source init stderr diagnostic was not preserved"
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/feat/E99-F117-init-fail &&
    fail "safe init failure left branch"
  [ ! -e "$PRIMARY/.claude/worktrees/E99-F117-init-fail" ] ||
    fail "safe init failure left path"
  pass "test_init_failure_triggers_safe_rollback"
}

test_init_failure_rolls_back_from_divergent_ambient_branch() {
  make_source_fixture init_failure_divergent
  printf '#!/bin/sh\nexit 9\n' > "$PRIMARY/init.sh"
  git -C "$PRIMARY" commit -am failing-init >/dev/null
  git -C "$PRIMARY" checkout --orphan ambient >/dev/null 2>&1
  git -C "$PRIMARY" commit -m divergent-ambient >/dev/null
  assert_create_fails initialization create E99-F130 divergent-rollback
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/feat/E99-F130-divergent-rollback &&
    fail "divergent ambient rollback left branch"
  [ ! -e "$PRIMARY/.claude/worktrees/E99-F130-divergent-rollback" ] ||
    fail "divergent ambient rollback left path"
  pass "test_init_failure_rolls_back_from_divergent_ambient_branch"
}

test_run_context_argv_and_status() {
  make_source_fixture run
  _wt="$(cd "$PRIMARY" && tools/fix-worktree.sh create E99-F118 run)"
  set +e
  (cd "$PRIMARY" && tools/fix-worktree.sh run E99-F118 run -- sh -c \
    'printf "%s\n%s\n%s\n" "$PWD" "$HARNESS_DIR" "$1" > run.out; exit 23' sh 'space * literal')
  _status=$?
  set -e
  [ "$_status" -eq 23 ] || fail "run did not preserve exit 23 (got $_status)"
  _canonical="$(CDPATH= cd -- "$PRIMARY" && pwd -P)"
  [ "$(sed -n '1p' "$_wt/run.out")" = "$_wt" ] || fail "run cwd mismatch"
  [ "$(sed -n '2p' "$_wt/run.out")" = "$_canonical" ] || fail "run HARNESS_DIR mismatch"
  [ "$(sed -n '3p' "$_wt/run.out")" = 'space * literal' ] || fail "run reparsed argv"
  pass "test_run_context_argv_and_status"
}

test_installed_run_uses_installed_harness_dir() {
  make_source_fixture run_installed
  mkdir -p "$PRIMARY/.harness/tools"
  mv "$PRIMARY/tools/fix-worktree.sh" "$PRIMARY/.harness/tools/fix-worktree.sh"
  printf '#!/bin/sh\nexit 0\n' > "$PRIMARY/.harness/init.sh"
  chmod +x "$PRIMARY/.harness/init.sh" "$PRIMARY/.harness/tools/fix-worktree.sh"
  git -C "$PRIMARY" rm tools/fix-worktree.sh >/dev/null
  git -C "$PRIMARY" add .harness
  git -C "$PRIMARY" commit -m installed-run-layout >/dev/null
  _wt="$(cd "$PRIMARY" && .harness/tools/fix-worktree.sh create E99-F140 installed-run)"
  (cd "$PRIMARY" && .harness/tools/fix-worktree.sh run E99-F140 installed-run -- sh -c \
    'printf "%s\n" "$HARNESS_DIR" > installed-run.out')
  _primary_abs="$(CDPATH= cd -- "$PRIMARY" && pwd -P)"
  [ "$(cat "$_wt/installed-run.out")" = "$_primary_abs/.harness" ] ||
    fail "installed-layout run HARNESS_DIR mismatch"
  pass "test_installed_run_uses_installed_harness_dir"
}

test_provision_failure_safe_rollback() {
  make_source_fixture rollback
  printf '#!/bin/sh\nexit 9\n' > "$PRIMARY/init.sh"
  git -C "$PRIMARY" commit -am failing-init >/dev/null
  assert_create_fails initialization create E99-F124 rollback
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/feat/E99-F124-rollback &&
    fail "safe provisioning failure left branch"
  [ ! -e "$PRIMARY/.claude/worktrees/E99-F124-rollback" ] ||
    fail "safe provisioning failure left path"
  pass "test_provision_failure_safe_rollback"
}

test_provision_failure_preserves_unexpected_work() {
  make_source_fixture preserve_failure
  printf '#!/bin/sh\nprintf user > unexpected.txt\nexit 7\n' > "$PRIMARY/init.sh"
  git -C "$PRIMARY" commit -am dirty-failing-init >/dev/null
  assert_create_fails preserved create E99-F119 preserve
  [ -f "$PRIMARY/.claude/worktrees/E99-F119-preserve/unexpected.txt" ] ||
    fail "unexpected provisioning work was not preserved"
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/feat/E99-F119-preserve ||
    fail "dirty provisioning branch was not preserved"
  pass "test_provision_failure_preserves_unexpected_work"
}

test_provision_failure_preserves_changed_managed_link() {
  make_source_fixture preserve_changed_link
  printf 'personal\n' > "$PRIMARY/AGENTS.local.md"
  printf '%s\n' \
    '#!/bin/sh' \
    'rm AGENTS.local.md' \
    'ln -s /tmp/fix-worktree-retargeted AGENTS.local.md' \
    'exit 7' > "$PRIMARY/init.sh"
  git -C "$PRIMARY" commit -am retargeted-failing-init >/dev/null
  _wt="$PRIMARY/.claude/worktrees/E99-F148-retargeted-link"
  assert_create_fails preserved create E99-F148 retargeted-link
  [ -d "$_wt" ] ||
    fail "changed managed-link provisioning failure removed worktree"
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/feat/E99-F148-retargeted-link ||
    fail "changed managed-link provisioning failure removed branch"
  [ -L "$_wt/AGENTS.local.md" ] ||
    fail "changed managed-link destination did not survive"
  [ "$(readlink "$_wt/AGENTS.local.md")" = /tmp/fix-worktree-retargeted ] ||
    fail "changed managed-link target did not survive"
  pass "test_provision_failure_preserves_changed_managed_link"
}

merge_fix_to_base() {
  _branch=$1
  git -C "$PRIMARY" merge --no-ff -m merge "$_branch" >/dev/null
}

test_teardown_refuses_dirty_wrong_branch_unmerged_and_wrong_primary_head() {
  make_source_fixture teardown_refusals
  _wt="$(cd "$PRIMARY" && tools/fix-worktree.sh create E99-F120 refuse)"
  printf dirty >> "$_wt/tracked.txt"
  assert_create_fails work teardown E99-F120 refuse
  [ -d "$_wt" ] || fail "unmerged/dirty teardown removed path"
  git -C "$_wt" checkout -- tracked.txt
  printf merged > "$_wt/merged.txt"
  git -C "$_wt" add merged.txt
  git -C "$_wt" commit -m merged >/dev/null
  assert_create_fails merged teardown E99-F120 refuse
  merge_fix_to_base feat/E99-F120-refuse
  git -C "$PRIMARY" checkout -b other >/dev/null 2>&1
  assert_create_fails primary teardown E99-F120 refuse
  [ -d "$_wt" ] || fail "wrong-primary teardown removed path"

  make_source_fixture teardown_staged
  _wt="$(cd "$PRIMARY" && tools/fix-worktree.sh create E99-F141 staged)"
  printf staged > "$_wt/staged.txt"
  git -C "$_wt" add staged.txt
  assert_create_fails work teardown E99-F141 staged
  [ -f "$_wt/staged.txt" ] || fail "staged teardown removed user file"
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/feat/E99-F141-staged ||
    fail "staged teardown removed branch"
  git -C "$PRIMARY" worktree list --porcelain | grep -F "worktree $_wt" >/dev/null ||
    fail "staged teardown removed registration"

  make_source_fixture teardown_untracked
  _wt="$(cd "$PRIMARY" && tools/fix-worktree.sh create E99-F142 untracked)"
  printf untracked > "$_wt/untracked.txt"
  assert_create_fails work teardown E99-F142 untracked
  [ -f "$_wt/untracked.txt" ] || fail "untracked teardown removed user file"
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/feat/E99-F142-untracked ||
    fail "untracked teardown removed branch"
  git -C "$PRIMARY" worktree list --porcelain | grep -F "worktree $_wt" >/dev/null ||
    fail "untracked teardown removed registration"

  make_source_fixture wrong_branch
  git -C "$PRIMARY" branch alternate main
  _wt="$(cd "$PRIMARY" && tools/fix-worktree.sh create E99-F128 wrong-branch)"
  git -C "$_wt" checkout alternate >/dev/null 2>&1
  assert_create_fails branch teardown E99-F128 wrong-branch
  [ -d "$_wt" ] || fail "wrong-branch teardown removed path"
  pass "test_teardown_refuses_dirty_wrong_branch_unmerged_and_wrong_primary_head"
}

test_clean_merged_teardown_removes_exact_resources() {
  make_source_fixture teardown
  mkdir -p "$PRIMARY/.claude"
  printf '{}\n' > "$PRIMARY/.claude/settings.local.json"
  _unrelated="$(cd "$PRIMARY" && tools/fix-worktree.sh create E99-F143 unrelated)"
  _unrelated_stale="$(CDPATH= cd -- "$PRIMARY" && pwd -P)/.claude/worktrees/unrelated-stale"
  git -C "$PRIMARY" worktree add -b unrelated-stale "$_unrelated_stale" main >/dev/null 2>&1
  mv "$_unrelated_stale" "$FIXTURE/unrelated-stale-away"
  git -C "$PRIMARY" worktree list --porcelain | grep -F "worktree $_unrelated_stale" >/dev/null ||
    fail "unrelated stale registration precondition missing"
  _wt="$(cd "$PRIMARY" && tools/fix-worktree.sh create E99-F121 clean)"
  printf merged > "$_wt/merged.txt"
  git -C "$_wt" add merged.txt
  git -C "$_wt" commit -m merged >/dev/null
  merge_fix_to_base feat/E99-F121-clean
  (cd "$PRIMARY" && tools/fix-worktree.sh teardown E99-F121 clean)
  [ ! -e "$_wt" ] || fail "clean teardown left path"
  git -C "$PRIMARY" worktree list --porcelain | grep -F "worktree $_wt" >/dev/null &&
    fail "clean teardown left registration"
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/feat/E99-F121-clean &&
    fail "clean teardown left branch"
  [ -d "$_unrelated" ] || fail "clean teardown removed unrelated worktree"
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/feat/E99-F143-unrelated ||
    fail "clean teardown removed unrelated branch"
  git -C "$PRIMARY" worktree list --porcelain | grep -F "worktree $_unrelated" >/dev/null ||
    fail "clean teardown removed unrelated registration"
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/unrelated-stale ||
    fail "clean teardown removed unrelated stale branch"
  git -C "$PRIMARY" worktree list --porcelain | grep -F "worktree $_unrelated_stale" >/dev/null ||
    fail "clean teardown pruned unrelated stale registration"
  pass "test_clean_merged_teardown_removes_exact_resources"
}

test_teardown_idempotent_and_partial_safe() {
  make_source_fixture teardown_idempotent
  _wt="$(cd "$PRIMARY" && tools/fix-worktree.sh create E99-F125 repeated)"
  printf merged > "$_wt/merged.txt"
  git -C "$_wt" add merged.txt
  git -C "$_wt" commit -m merged >/dev/null
  merge_fix_to_base feat/E99-F125-repeated
  (cd "$PRIMARY" && tools/fix-worktree.sh teardown E99-F125 repeated)
  (cd "$PRIMARY" && tools/fix-worktree.sh teardown E99-F125 repeated)
  git -C "$PRIMARY" branch feat/E99-F126-lone main
  (cd "$PRIMARY" && tools/fix-worktree.sh teardown E99-F126 lone)
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/feat/E99-F126-lone &&
    fail "safe lone merged branch was not reconciled"
  mkdir -p "$PRIMARY/.claude/worktrees/E99-F127-path-only"
  assert_create_fails registration teardown E99-F127 path-only
  [ -d "$PRIMARY/.claude/worktrees/E99-F127-path-only" ] ||
    fail "unsafe path-only partial state was removed"

  _stale="$(cd "$PRIMARY" && tools/fix-worktree.sh create E99-F129 stale)"
  printf stale > "$_stale/stale.txt"
  git -C "$_stale" add stale.txt
  git -C "$_stale" commit -m stale-merged >/dev/null
  merge_fix_to_base feat/E99-F129-stale
  rm -rf "$_stale"
  if ! (cd "$PRIMARY" && tools/fix-worktree.sh teardown E99-F129 stale) 2>"$FIXTURE/stale.err"; then
    fail "safe stale teardown failed: $(cat "$FIXTURE/stale.err")"
  fi
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/feat/E99-F129-stale &&
    fail "safe stale registration/branch was not reconciled"

  make_source_fixture unexpected_registration_branch
  _unexpected="$PRIMARY/.claude/worktrees/E99-F144-unexpected-registration"
  git -C "$PRIMARY" worktree add -b unrelated-partial "$_unexpected" main >/dev/null 2>&1
  assert_create_fails branch teardown E99-F144 unexpected-registration
  [ -d "$_unexpected" ] || fail "unexpected-branch registration path was removed"
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/unrelated-partial ||
    fail "unexpected registration branch was removed"

  make_source_fixture missing_expected_branch
  _missing="$(cd "$PRIMARY" && tools/fix-worktree.sh create E99-F145 missing-branch)"
  _missing_tip="$(git -C "$PRIMARY" rev-parse refs/heads/feat/E99-F145-missing-branch)"
  git -C "$PRIMARY" update-ref -d refs/heads/feat/E99-F145-missing-branch "$_missing_tip"
  assert_create_fails absent teardown E99-F145 missing-branch
  [ -d "$_missing" ] || fail "registration with missing expected branch was removed"
  git -C "$PRIMARY" worktree list --porcelain | grep -F "worktree $_missing" >/dev/null ||
    fail "registration with missing expected branch was pruned"

  make_source_fixture mismatched_registration_head
  _mismatch="$(cd "$PRIMARY" && tools/fix-worktree.sh create E99-F146 mismatch)"
  _base_oid="$(git -C "$PRIMARY" rev-parse main)"
  _tree_oid="$(git -C "$PRIMARY" rev-parse 'main^{tree}')"
  _new_oid="$(printf 'race\n' | git -C "$PRIMARY" commit-tree "$_tree_oid" -p "$_base_oid")"
  _real_git="$(command -v git)"
  mkdir -p "$FIXTURE/race-bin"
  printf '%s\n' \
    '#!/bin/sh' \
    'if [ "$*" = "-C $RACE_PRIMARY rev-parse refs/heads/$RACE_BRANCH" ]; then' \
    '  "$REAL_GIT" -C "$RACE_PRIMARY" update-ref "refs/heads/$RACE_BRANCH" "$RACE_NEW_OID"' \
    'fi' \
    'exec "$REAL_GIT" "$@"' > "$FIXTURE/race-bin/git"
  chmod +x "$FIXTURE/race-bin/git"
  _race_primary="$(CDPATH= cd -- "$PRIMARY" && pwd -P)"
  if (cd "$PRIMARY" && PATH="$FIXTURE/race-bin:$PATH" REAL_GIT="$_real_git" \
      RACE_PRIMARY="$_race_primary" RACE_BRANCH=feat/E99-F146-mismatch RACE_NEW_OID="$_new_oid" \
      tools/fix-worktree.sh teardown E99-F146 mismatch) >"$FIXTURE/out" 2>"$FIXTURE/err"; then
    fail "mismatched recorded HEAD teardown unexpectedly succeeded"
  fi
  grep -qi match "$FIXTURE/err" ||
    fail "mismatched recorded HEAD diagnostic missing: $(cat "$FIXTURE/err")"
  [ -d "$_mismatch" ] || fail "mismatched recorded HEAD removed path"
  [ "$(git -C "$PRIMARY" rev-parse refs/heads/feat/E99-F146-mismatch)" = "$_new_oid" ] ||
    fail "mismatched recorded HEAD branch was changed after detection"

  make_source_fixture unmerged_partial
  _base_oid="$(git -C "$PRIMARY" rev-parse main)"
  _tree_oid="$(git -C "$PRIMARY" rev-parse 'main^{tree}')"
  _unmerged_oid="$(printf 'unmerged\n' | git -C "$PRIMARY" commit-tree "$_tree_oid" -p "$_base_oid")"
  git -C "$PRIMARY" update-ref refs/heads/feat/E99-F147-unmerged "$_unmerged_oid"
  assert_create_fails merged teardown E99-F147 unmerged
  [ "$(git -C "$PRIMARY" rev-parse refs/heads/feat/E99-F147-unmerged)" = "$_unmerged_oid" ] ||
    fail "unmerged lone branch was removed or changed"
  pass "test_teardown_idempotent_and_partial_safe"
}

test_helper_rejects_forced_or_recursive_cleanup() {
  grep -q -- 'worktree remove --force' "$SRC/tools/fix-worktree.sh" &&
    fail "helper contains forced worktree removal"
  grep -q -- 'branch -D' "$SRC/tools/fix-worktree.sh" &&
    fail "helper contains forced branch deletion"
  grep -q -- 'rm -rf' "$SRC/tools/fix-worktree.sh" &&
    fail "helper contains recursive filesystem deletion"
  pass "test_helper_rejects_forced_or_recursive_cleanup"
}

test_create_exact_branch_and_path
test_default_and_explicit_base_resolution
test_base_is_ref_not_ambient_head
test_dirty_primary_fails_before_mutation
test_invalid_inputs_are_non_mutating
test_slug_rejection_is_locale_independent
test_base_accepts_short_local_ref_only
test_branch_path_and_registration_collisions_fail_closed
test_two_active_worktrees_are_isolated
test_personal_layer_allowlist_only
test_source_and_installed_init_gate
test_init_failure_triggers_safe_rollback
test_init_failure_rolls_back_from_divergent_ambient_branch
test_run_context_argv_and_status
test_installed_run_uses_installed_harness_dir
test_provision_failure_safe_rollback
test_provision_failure_preserves_unexpected_work
test_provision_failure_preserves_changed_managed_link
test_teardown_refuses_dirty_wrong_branch_unmerged_and_wrong_primary_head
test_clean_merged_teardown_removes_exact_resources
test_teardown_idempotent_and_partial_safe
test_helper_rejects_forced_or_recursive_cleanup
