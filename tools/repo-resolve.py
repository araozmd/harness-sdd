#!/usr/bin/env python3
# repo-resolve.py — WHICH repository is a claim about, and may that answer be trusted?
#
# This module answers exactly one question and returns a value that makes its own
# uncertainty impossible to ignore. It contains NO ancestry logic, NO verdicts and NO
# board writes: it does not know what `done` means, and the code that does must not know
# how a repository is found.
#
# ── why this is a module and not a few helpers ───────────────────────────────
# Landing verification decides, for a (ref, repository) pair, whether the work merged.
# Nine rows enumerate those verdicts. Establishing the PAIR is a different question, and
# it was implicit machinery threaded through the write path: a search order here, a
# manifest read there, a fingerprint assembled somewhere else again. Correctness was by
# convention across ~9 functions — every new call path had to remember to participate in
# all of them — and it kept not being remembered. That defect class produced findings in
# five separate review rounds:
#
#   * a slice repository located by DIRECTORY BASENAME, so an aliased path resolved
#     nowhere and unmerged work was accepted unchecked;
#   * the manifest missing from the plan→write fingerprint, so repointing a repo's path
#     mid-probe wrote a verdict computed against the old checkout;
#   * an unbound ref resolving in SEVERAL repositories and silently taking the first —
#     which, because the harness dir is searched before the children, is the umbrella's
#     own bookkeeping repository, the one that never holds feature work;
#   * a lexical path in the fingerprint, which a retargeted symlink walks straight past;
#   * a NEW call path added to fix the third of those, which omitted the fingerprint
#     again — the defect reappearing on the code written to address it;
#   * and `refs/remotes/origin/HEAD` trusted as if it were the remote's answer when it is
#     only a CACHE of a former answer.
#
# The last two are why this is a module. A witness assembled beside a resolution can be
# forgotten by the next path; a witness that IS part of the resolution cannot. And "is
# this base still the default branch?" is a question about the repository's identity, not
# about ancestry — so it belongs to whoever answers "which repository", not to the code
# that runs `merge-base`.
#
# ── the contract ─────────────────────────────────────────────────────────────
#
# I1 — WHEN MAY A REF BE RESOLVED BY SEARCH?
#   A BINDING (`<repo>=<ref>`) names the repository: no search. Without one the ref is
#   searched across the nearby repositories and must resolve in EXACTLY ONE. Two or more
#   is `AMBIGUOUS` — a value the caller must handle, never a repository it can use. Not
#   "take the first": any ordering is a guess, and this one's first entry is the harness
#   dir's own repository. Two candidates are the SAME repository when their common git
#   dir matches, so linked worktrees are one repository and not an ambiguity.
#
# I2 — WHAT IS A REPOSITORY'S IDENTITY?
#   The lexical path AND its realpath, together. The lexical value catches the manifest
#   being rewritten; the realpath catches the same text now pointing somewhere else. They
#   are one value (`Identity`) with one comparison (`Identity.revalidate`), which uses
#   filesystem calls only so a caller may re-check it while holding a lock.
#   NOT covered, deliberately: a repository replaced in place — same realpath, different
#   objects. This is a coherence check against concurrent activity over a sub-second
#   window, not a defence against a checkout swapped under a running process.
#
# I3 — IS THE ANSWER CURRENT, AND BY WHAT EVIDENCE?
#   A resolution carries HOW it knows what the default branch is, because the answers are
#   not equally trustworthy and the caller's decision depends on which one it got:
#     `published`   the remote said so JUST NOW, name AND tip: `ls-remote --symref`
#                   advertises both, so both are established or neither is.
#     `published-stale-tip`
#                   the remote NAMED this branch as its default, but our copy of it is
#                   behind the tip the remote advertised. The name is confirmed; the tip
#                   is not, and an ancestry answer computed against our stale copy would
#                   REFUSE work that is already merged. Callers need not distinguish this
#                   from the other unconfirmed sources to stay correct — `base_confirmed`
#                   already says no — but the value is separate so a warning can say WHY,
#                   and so a caller that happens to hold `base_tip` can do better.
#     `cached`      `refs/remotes/origin/HEAD` — a local snapshot of a FORMER answer. A
#                   remote that moves its default while the old branch still exists leaves
#                   this pointing at the old one, and a commit reachable only from the
#                   former default then looks like it is on the default branch. Measured,
#                   on a remote that moved `main` → `trunk`: `verified: "ancestor"`,
#                   `base: "origin/main"`. So this evidence is NEVER confirmed.
#     `declared`    `git config harness.defaultBranch` — an operator's statement. It is
#                   confirmed only when there is no origin for it to disagree with.
#     `sole-branch` the repository has exactly one branch, so "the default" has no other
#                   candidate. Confirmed only when there is no origin.
#     `none`        nothing authoritative. `base` is not available.
#   `base_confirmed` folds those rules into one boolean so a caller cannot re-derive them
#   differently. A caller may still USE an unconfirmed base — to accept, say — but it must
#   not treat an unconfirmed base as grounds to REFUSE, because refusing on a stale view
#   rejects work that is already merged.
#
# ── what `revalidate()` asserts, exactly ─────────────────────────────────────
#
# `resolve()` is expensive and talks to the network, so a caller runs it BEFORE taking a
# lock and re-checks it INSIDE one. That re-check needs a promise, and it did not have
# one — it had a name and an intuition. Two findings came straight out of the gap: it
# compared the WRONG thing (it read the chosen directory's basename as a manifest key, so
# an unbound resolution under an aliased manifest could never revalidate), and it compared
# TOO FEW things (only the chosen repository, so retargeting a NON-selected candidate left
# it saying "unchanged" while a fresh resolve would now report `ambiguous`). Both are
# answers to a question nobody had stated, so here it is:
#
#   revalidate(r, hdir) is True iff a fresh resolve() with the SAME inputs would return
#   the same OUTCOME, the same REPOSITORY, and the same CERTAINTY.
#
# Everything it checks follows from that sentence, and nothing else belongs in it:
#   * the chosen repository is still that repository        (same repository)
#   * for a BOUND request, the manifest still puts that KEY there   (same authority)
#   * the manifest's state is unchanged                     (absent↔present flips whether
#                                                            a claim can be malformed)
#   * the candidate set — paths AND identities — is unchanged (same CERTAINTY: uniqueness
#                                                            is what made an unbound answer
#                                                            unambiguous, and a candidate
#                                                            that is now a different
#                                                            repository can make it not)
#
# What it deliberately does NOT promise, because these change the WORLD without changing
# the ANSWER:
#   * the default branch advancing. That is somebody else's merge, it happens constantly
#     in a busy repository, and ancestry is monotone under fast-forward — aborting on it
#     would make the guard fire so often it would be switched off. Whether the base is
#     CURRENT is a separate question, answered at resolve() time by `base_evidence` and
#     `base_confirmed`, not here.
#   * file contents, working-tree state, or anything about the ref's own history.
# It also spawns NO child process, so a caller may run it while holding a lock.
#
# ── uncertainty is a value, not an omission ──────────────────────────────────
# `Resolution.directory` and `.base` RAISE if you read them when they do not exist. That
# is deliberate: the failure this module exists to prevent is a caller treating "I could
# not tell" as "yes", and the cheapest way to make that unrepresentable is to make the
# uncertain case impossible to read past. Branch on `.outcome` (and `.base_confirmed`)
# first; the values are there when, and only when, they mean something.

import io
import os
import subprocess

# ── outcomes: a CLOSED set, because an unrecognised one would read as success ──
RESOLVED = "resolved"          # exactly one repository, and it is `directory`
AMBIGUOUS = "ambiguous"        # several repositories answer to this ref
UNDECLARED = "undeclared"      # a binding names a repo the manifest does not contain
UNLOCATABLE = "unlocatable"    # named or declared, but not readable from here
UNKNOWN = "unknown"            # located, but nothing there resolves the ref
UNREADABLE = "unreadable"      # the authority exists and could not be read
OUTCOMES = (RESOLVED, AMBIGUOUS, UNDECLARED, UNLOCATABLE, UNKNOWN, UNREADABLE)

# ── how we know what the default branch is (see I3) ───────────────────────────
BASE_PUBLISHED = "published"                    # name AND tip agree with the remote
BASE_PUBLISHED_STALE_TIP = "published-stale-tip"  # name confirmed; our copy is behind
BASE_CACHED = "cached"
BASE_DECLARED = "declared"
BASE_SOLE_BRANCH = "sole-branch"
BASE_NONE = "none"
BASE_EVIDENCE = (BASE_PUBLISHED, BASE_PUBLISHED_STALE_TIP, BASE_CACHED,
                 BASE_DECLARED, BASE_SOLE_BRANCH, BASE_NONE)

DECLARED_DEFAULT_CONFIG = "harness.defaultBranch"


class Uncertain(Exception):
    """Raised when a caller reads a value the resolution does not have (see the header)."""


def _git(args, cwd, timeout=5):
    """`git <args>` in <cwd> → stripped stdout, or None on ANY error. Never raises."""
    try:
        out = subprocess.run(
            ["git"] + list(args), cwd=cwd,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    text = out.stdout.decode("utf-8", "replace").strip()
    return text or None


def _git_lines(args, cwd):
    """Like `_git`, but EMPTY output is a result (no branches) rather than a failure."""
    try:
        out = subprocess.run(
            ["git"] + list(args), cwd=cwd,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    return [l for l in out.stdout.decode("utf-8", "replace").split("\n") if l.strip()]


def resolve_commit(repo, ref):
    """The immutable commit id `ref` names in `repo`, or None. NO PATTERN MATCHING.

    Git decides what an object is: a hand-written pattern excluded SHA-256's 64-character
    ids once already, and will exclude whatever git learns to resolve next. `--verify`
    with `^{commit}` peels a tag or a branch to the commit it points at.
    """
    return _git(["rev-parse", "--verify", "--quiet", ref + "^{commit}"], cwd=repo)


class Identity(object):
    """WHERE a repository is, in the two ways that can independently change (I2)."""

    __slots__ = ("lexical", "real")

    def __init__(self, lexical):
        self.lexical = lexical
        self.real = os.path.realpath(lexical) if lexical else None

    def revalidate(self):
        """True iff the lexical path STILL resolves where it did. Filesystem only.

        No child process, so a caller may run this while holding a lock — which is the
        whole point: the expensive resolution happens outside the lock and only this
        cheap re-check happens inside it.
        """
        return bool(self.lexical) and os.path.realpath(self.lexical) == self.real

    def as_tuple(self):
        return (self.lexical, self.real)

    def __eq__(self, other):
        return isinstance(other, Identity) and self.as_tuple() == other.as_tuple()

    def __repr__(self):  # pragma: no cover - diagnostics
        return "Identity(%r -> %r)" % (self.lexical, self.real)


def _git_storage_root(directory):
    """(gitdir, commondir) for a work tree, resolved with FILE READS ONLY.

    `.git` may be a DIRECTORY (ordinary checkout) or a FILE containing `gitdir: <path>`
    (a linked worktree, or `git init --separate-git-dir`). A linked worktree splits its
    refs: per-worktree ones (HEAD, refs/bisect) live in its own git dir, while the shared
    ones (refs/heads, refs/remotes) and ALL objects live in the COMMON dir, which git
    records in `<gitdir>/commondir`.

    `same_repository()` asks git for the same notion with `rev-parse --git-common-dir`;
    this reads the file git wrote, because a fingerprint has to be recomputable inside a
    lock where no child process may run. Both must agree on where a repository's refs
    actually live, or one of them is looking at the wrong place.
    """
    entry = os.path.join(directory, ".git")
    if os.path.isdir(entry):
        gitdir = entry
    elif os.path.isfile(entry):
        try:
            with io.open(entry, encoding="utf-8") as fh:
                text = fh.read().strip()
        except (OSError, ValueError):
            return None
        if not text.startswith("gitdir:"):
            return None
        gitdir = os.path.normpath(
            os.path.join(directory, text.split(":", 1)[1].strip()))
    else:
        return None
    common = gitdir
    marker = os.path.join(gitdir, "commondir")
    if os.path.isfile(marker):
        try:
            with io.open(marker, encoding="utf-8") as fh:
                common = os.path.normpath(os.path.join(gitdir, fh.read().strip()))
        except (OSError, ValueError):
            return None
    return gitdir, common


def _stat_of(path):
    try:
        st = os.stat(path)
        return (st.st_mtime_ns, st.st_size)
    except OSError:
        return None


def _storage_fingerprint(directory):
    """A FILESYSTEM-ONLY change detector over where a repository keeps refs and objects.

    THE PROPERTY IT IMPLEMENTS: a repository cannot come to hold a commit without writing
    into its object store, and cannot come to hold a NAME for one without writing into its
    ref store. So this observes those two stores directly — and, importantly, at the level
    git actually writes:

      * refs: the whole `refs/` tree is WALKED, every directory and every file, because a
        loose ref is written inside `refs/heads/…` and that touches only its own
        directory — the parent `refs/` mtime does not move. Plus `packed-refs`.
      * objects: every fan-out directory `objects/<xx>` is stat'd, because a loose object
        lands inside one of them and `objects/` itself does not change; plus the listing
        of `objects/pack`, because a fetch usually arrives as a new pack file.

    An earlier version stat'd only the five PARENTS (`.git`, `refs`, `packed-refs`,
    `objects`, `objects/pack`) while its comment claimed exactly the property above. The
    reasoning was right and the paths did not implement it: rewriting a loose ref left the
    fingerprint byte-identical. A comment asserting a guarantee the code does not have is
    worse than no comment, because it invites the next reader to trust it instead of
    re-deriving it — so this docstring now ends with what it does NOT see.

    Both the COMMON dir (shared refs, all objects) and the per-worktree dir (HEAD and its
    private refs) are covered, via `_git_storage_root`, so gitfile and linked-worktree
    layouts are not blind spots.

    It over-reports by design: unrelated local activity in a neighbouring repository looks
    like a change. A false alarm costs a re-run; a miss spends an answer whose uniqueness
    has lapsed.

    ⚠️ WHAT IT DOES NOT SEE, precisely:
      * objects borrowed through `objects/info/alternates` — the store lives in another
        repository entirely, and following that chain is more filesystem walking than a
        lock-held check should do. The alternates FILE is fingerprinted, so the borrowing
        being set up or changed is visible; objects appearing in the borrowed store are not.
      * a change that leaves both the directory listing and every mtime/size identical.
      * anything about the ref's own history — this answers "did this store change", never
        "is this commit here". That question needs git, and git may not be run here.
    """
    roots = _git_storage_root(directory)
    if roots is None:
        return None
    gitdir, common = roots
    parts = [("gitentry", _stat_of(os.path.join(directory, ".git")))]
    for label, base in (("common", common), ("private", gitdir)):
        if label == "private" and os.path.realpath(gitdir) == os.path.realpath(common):
            continue                       # ordinary checkout: one store, not two
        refs_root = os.path.join(base, "refs")
        for root, dirs, files in os.walk(refs_root):
            dirs.sort()
            rel = os.path.relpath(root, base)
            parts.append((label, "refsdir", rel, tuple(sorted(files)),
                          _stat_of(root)))
            for name in sorted(files):
                parts.append((label, "ref", rel, name,
                              _stat_of(os.path.join(root, name))))
        for name in ("packed-refs", "HEAD", os.path.join("objects", "info", "alternates")):
            parts.append((label, name, _stat_of(os.path.join(base, name))))
        objects = os.path.join(base, "objects")
        try:
            entries = sorted(os.listdir(objects))
        except OSError:
            entries = []
        for name in entries:
            if len(name) == 2:             # a loose-object fan-out directory
                parts.append((label, "fanout", name,
                              _stat_of(os.path.join(objects, name))))
        pack = os.path.join(objects, "pack")
        try:
            packs = tuple(sorted(os.listdir(pack)))
        except OSError:
            packs = ()
        parts.append((label, "packs", packs, _stat_of(pack)))
    return tuple(parts)


class Witness(object):
    """What a resolution DEPENDED ON, captured by `resolve()` at the point of use.

    `revalidate()` used to re-derive this list by inspecting a finished `Resolution`, and
    three review findings were the same shape: it compared the wrong field, then too few
    things, then too few things again. The contract sentence was never wrong — "a fresh
    resolve() would return the same answer" already entails all of them — but the list of
    inputs was maintained in two places, and only one of them actually knew. So the
    capture moved to where the dependency is USED. A dimension `resolve()` consults and
    forgets to witness is now a dimension it did not consult.

    `still_holds()` is filesystem-only and spawns no child process, so a caller may run it
    while holding a lock.

    What it deliberately does NOT promise (unchanged): the CHOSEN repository's default
    branch advancing. That is somebody else's merge, it happens constantly, and ancestry is
    monotone under fast-forward. This is why the storage fingerprints cover only the
    candidates that were NOT chosen: their ref membership is what uniqueness depends on,
    while the chosen repository's own refs moving changes the world without changing which
    repository this answer is about.
    """

    __slots__ = ("outcome", "repo", "binding", "identity", "manifest_state",
                 "manifest_entry", "candidates", "others")

    def __init__(self, outcome, repo, binding, identity, manifest_state,
                 manifest_entry, candidates, others):
        self.outcome = outcome
        self.repo = repo
        self.binding = binding
        self.identity = identity
        self.manifest_state = manifest_state
        self.manifest_entry = manifest_entry
        self.candidates = tuple(candidates)
        self.others = tuple(others)

    def still_holds(self, hdir):
        """Would a fresh `resolve()` give the same outcome, repository and certainty?

        Returns (True, None) or (False, what changed).
        """
        # same REPOSITORY
        if self.identity is not None and not self.identity.revalidate():
            return False, "%s now resolves to %s, not %s" % (
                self.identity.lexical, os.path.realpath(self.identity.lexical),
                self.identity.real)
        # same AUTHORITY
        state, mapping = manifest_repos(hdir)
        if state != self.manifest_state:
            return False, "the manifest went from %s to %s" % (self.manifest_state, state)
        if self.binding is not None and state == "present":
            if mapping.get(self.binding) != self.manifest_entry:
                return False, "the manifest now puts %s at %s, not %s" % (
                    self.binding, mapping.get(self.binding), self.manifest_entry)
        # same CERTAINTY — the search space, by path AND identity...
        if self.candidates and tuple(candidates(hdir, pairs=True)) != self.candidates:
            return False, ("the nearby repositories changed (a path or an identity), so "
                           "this answer may no longer be the only one")
        # ...and by REF MEMBERSHIP: a neighbour that acquires this ref makes a unique
        # answer ambiguous while every path and identity above stays identical.
        for lexical, fingerprint in self.others:
            if _storage_fingerprint(lexical) != fingerprint:
                return False, ("%s changed its refs or objects, so it may now hold this "
                               "ref too and the answer may no longer be the only one"
                               % lexical)
        return True, None


class Resolution(object):
    """The answer, with its own uncertainty attached. See the header.

    `outcome` is always readable. `directory` and `base` raise `Uncertain` when the
    resolution does not have them, so a caller cannot slide from "I could not tell" to
    "yes" by forgetting a branch.
    """

    __slots__ = ("outcome", "repo", "binding", "identity", "detail", "candidates",
                 "manifest_state", "_directory", "_base", "base_evidence",
                 "has_origin", "commit", "base_tip", "_witness")

    def __init__(self, outcome, repo=None, binding=None, directory=None,
                 identity=None, detail=None,
                 candidates=(), manifest_state="absent", base=None,
                 base_evidence=BASE_NONE, has_origin=False, commit=None,
                 base_tip=None, witness=None):
        assert outcome in OUTCOMES, outcome
        assert base_evidence in BASE_EVIDENCE, base_evidence
        self.outcome = outcome
        # `repo` is the NAME TO RECORD — for a bound request the key, for a search the
        # chosen directory's basename. `binding` is what the CALLER ASKED FOR, or None.
        # They are separate fields on purpose: a single field whose meaning depended on how
        # you arrived is exactly how revalidate came to read a basename as a manifest key.
        self.repo = repo
        self.binding = binding
        self.identity = identity
        self.detail = detail
        self.candidates = tuple(candidates)
        self.manifest_state = manifest_state
        self._directory = directory
        self._base = base
        self.base_evidence = base_evidence
        self.has_origin = has_origin
        self.commit = commit
        # The sha the remote advertised for its default branch, when it was asked. Carried
        # so a caller holding that object can answer against the REAL tip instead of our
        # copy of it; `None` when the remote was not, or could not be, asked.
        self.base_tip = base_tip
        self._witness = witness

    @property
    def certain(self):
        return self.outcome == RESOLVED

    def __bool__(self):
        """`if resolution:` means "did this resolve", never "did I get an object".

        The whole design goal is that a caller cannot slide from "I could not tell" to
        "yes", and `if r:` is exactly that slide: `resolve()` ALWAYS returns an object, so
        a default-truthy value would read as success for `ambiguous` and `unknown` alike.
        `.directory`/`.base` already protect anyone who USES the resolution; this protects
        the one who only asks whether there is one.
        """
        return self.certain

    __nonzero__ = __bool__      # Python 2 name, matching this file's style

    @property
    def directory(self):
        if self.outcome != RESOLVED:
            raise Uncertain(
                "no repository was resolved (%s): %s" % (self.outcome, self.detail)
            )
        return self._directory

    @property
    def base(self):
        if self._base is None:
            raise Uncertain(
                "no default branch could be determined for %s" % (self.repo or "?")
            )
        return self._base

    @property
    def base_confirmed(self):
        """May this base be trusted as CURRENT? (I3)

        `published` was asked for just now. `declared` and `sole-branch` are local
        signals: they are the whole truth only when there is no remote for them to be out
        of date with. `cached` is a snapshot of a FORMER answer and is never confirmed —
        that is exactly the defect this folds in one place, so no caller re-derives it.
        """
        if self._base is None:
            return False
        if self.base_evidence == BASE_PUBLISHED:
            return True
        if self.base_evidence in (BASE_DECLARED, BASE_SOLE_BRANCH):
            return not self.has_origin
        # `published-stale-tip` deliberately does NOT confirm. The remote named this branch
        # as its default, but our copy of it is behind what the remote advertised, and an
        # ancestry answer computed against a stale tip REFUSES work that is already merged.
        # A false refusal is worse than a silent pass — a guard that rejects merged work
        # gets switched off — so this degrades and the caller records `unchecked`.
        return False

    def witness(self):
        """The `Witness` captured while resolving. See that class for the contract.

        It comes back WITH the resolution or not at all, and it is built by `resolve()` at
        the point each dependency is used — so neither "the call path forgot the witness"
        nor "the re-check forgot a dimension" is expressible.
        """
        return self._witness


# ── the manifest: what it says, and where it says it from ─────────────────────


def _config_value(hdir, dotted):
    """One dotted key out of harness.config.yaml, or None. A deliberately tiny reader.

    The board write path must not acquire a YAML dependency, and the only key this needs
    is `umbrella.manifest`.
    """
    try:
        with io.open(os.path.join(hdir, "harness.config.yaml"), encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, ValueError):
        return None
    section, _, leaf = dotted.partition(".")
    in_section = False
    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        key, sep, value = line.strip().partition(":")
        if not sep:
            continue
        if indent == 0:
            in_section = key.strip() == section
            continue
        if in_section and key.strip() == leaf:
            return value.strip().strip('"').strip("'")
    return None


def manifest_repos(hdir):
    """(state, {repo: lexical path}) from the umbrella manifest.

    state is "absent" (none configured, or the file is not there — umbrella mode is off,
    so there is no authority to call a claim malformed), "unreadable" (named but unusable
    — treated like absent: this checkout's problem, not the operator's), or "present".

    ⚠️ `path:` resolves against THE MANIFEST FILE'S OWN DIRECTORY. Nothing requires a key
    to equal a directory name, and the shipped example uses siblings (`../viernes-bff`) —
    assuming the key was the basename is what made an aliased repository resolve nowhere.
    """
    rel = _config_value(hdir, "umbrella.manifest")
    if not rel:
        return "absent", {}
    mpath = os.path.join(hdir, rel)
    if not os.path.isfile(mpath):
        return "absent", {}
    try:
        with io.open(mpath, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, ValueError):
        return "unreadable", {}
    mdir = os.path.dirname(os.path.abspath(mpath))
    repos = {}
    repos_indent = None
    key_indent = None
    current = None
    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if "\t" in raw[: len(raw) - len(raw.lstrip())]:
            return "unreadable", {}
        indent = len(raw) - len(raw.lstrip(" "))
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        key, sep, value = line.strip().partition(":")
        if not sep:
            continue
        key, value = key.strip(), value.strip()
        if repos_indent is None:
            if indent == 0 and key == "repos":
                repos_indent = indent
            continue
        if indent <= repos_indent:
            repos_indent = None
            current = None
            continue
        if key_indent is None:
            key_indent = indent
        if indent == key_indent:
            if key in repos:
                # A DUPLICATE key is a malformed authority. `setdefault` silently kept the
                # first and let the later `path:` win, so a conflicted or partial edit
                # resolved confidently against the LAST checkout — and `next-task.mjs`
                # rejects duplicates outright, so the two readers of one file disagreed
                # about whether the manifest was usable at all. Same family as
                # unreadable≠absent: an authority that contradicts itself is not one.
                return "unreadable", {}
            current = key
            repos[current] = None
        elif current is not None and key == "path" and value:
            repos[current] = os.path.normpath(
                os.path.join(mdir, value.strip('"').strip("'"))
            )
    if not repos:
        return "unreadable", {}
    return "present", repos


def candidates(hdir, pairs=False):
    """Repositories to search when no manifest names one — nearest first, deduplicated.

    (1) the harness dir; (2) its parent; (3) that parent's immediate children. Directory
    probing only — no git process — so a caller may recompute this cheaply.

    The ORDER is documented and then deliberately not relied upon: (1) is the harness
    dir's own repository, which never holds feature work, so "first hit wins" is at its
    worst here. Ambiguity is refused instead (I1).
    """
    seen = []
    reals = []

    def add(path):
        if not path:
            return
        real = os.path.realpath(path)
        if real in reals:
            return
        if os.path.exists(os.path.join(real, ".git")):
            reals.append(real)
            seen.append((path, real))

    hdir = os.path.realpath(hdir)
    add(hdir)
    parent = os.path.dirname(hdir)
    add(parent)
    for root in (parent, hdir):
        try:
            entries = sorted(os.listdir(root))
        except OSError:
            continue
        for name in entries:
            if not name.startswith("."):
                add(os.path.join(root, name))
    # With `pairs`, each entry is (lexical, realpath). Uniqueness is what makes an unbound
    # answer certain, so a re-check needs each candidate's IDENTITY, not just its spelling:
    # a candidate that is now a different repository can turn a unique answer ambiguous.
    return seen if pairs else [lex for lex, _real in seen]


def same_repository(a, b):
    """True iff two directories are the SAME repository (I2).

    Two linked worktrees are two directories and one repository; comparing paths would
    read them as an ambiguity and refuse a claim that is not ambiguous. `--git-common-dir`
    is how git itself answers this.
    """
    ca = _git(["rev-parse", "--git-common-dir"], cwd=a)
    cb = _git(["rev-parse", "--git-common-dir"], cwd=b)
    if ca is None or cb is None:
        return False
    return os.path.realpath(os.path.join(a, ca)) == os.path.realpath(os.path.join(b, cb))


# ── the default branch, and how sure we are of it (I3) ────────────────────────


def default_branch(repo):
    """(base, evidence, has_origin, advertised_tip) — WHAT it is and HOW WELL we know it.

    Order: what the remote says NOW, then the local cache of what it used to say, then
    what this repository can establish about itself. The cache is deliberately NOT first:
    `refs/remotes/origin/HEAD` is a snapshot, and a remote that moves its default while
    the old branch still exists leaves it pointing at the old one. Asking costs one
    bounded call on a path that already talks to the network; being wrong costs a false
    attestation, which is the thing this whole feature exists to prevent.
    """
    has_origin = _git(["remote", "get-url", "origin"], cwd=repo) is not None

    if has_origin:
        # ONE call answers both halves of the question. `--symref` prints the symbolic
        # target AND the sha the remote advertises for HEAD:
        #     ref: refs/heads/main<TAB>HEAD
        #     5f0296f…<TAB>HEAD
        # Reading only the first line confirms the branch NAME and says nothing about the
        # TIP, which are different claims: with the name right and our tracking ref behind,
        # an ancestry check runs against a stale tip and REFUSES work that is already
        # merged. The sha is free here, so both are established or neither is.
        symref = _git(["ls-remote", "--symref", "origin", "HEAD"], cwd=repo, timeout=10)
        branch_ref = None
        advertised = None
        for line in (symref or "").splitlines():
            parts = line.split()
            if len(parts) >= 3 and parts[0] == "ref:" and parts[2] == "HEAD":
                if parts[1].startswith("refs/heads/"):
                    branch_ref = "origin/" + parts[1][len("refs/heads/"):]
            elif len(parts) >= 2 and parts[1] == "HEAD":
                advertised = parts[0]
        if branch_ref:
            local = resolve_commit(repo, branch_ref)   # usable only if we have it locally
            if local:
                if advertised and local != advertised:
                    return branch_ref, BASE_PUBLISHED_STALE_TIP, has_origin, advertised
                return branch_ref, BASE_PUBLISHED, has_origin, advertised

    cached = _git(["symbolic-ref", "--quiet", "refs/remotes/origin/HEAD"], cwd=repo)
    if cached:
        ref = cached[len("refs/remotes/"):] if cached.startswith("refs/remotes/") else cached
        if resolve_commit(repo, ref):
            return ref, BASE_CACHED, has_origin, None

    declared = _git(["config", "--get", DECLARED_DEFAULT_CONFIG], cwd=repo)
    if declared and resolve_commit(repo, declared):
        return declared, BASE_DECLARED, has_origin, None

    if not has_origin:
        names = _git_lines(["for-each-ref", "--format=%(refname:short)", "refs/heads/"], cwd=repo)
        if names is not None and len(names) == 1 and resolve_commit(repo, names[0]):
            return names[0], BASE_SOLE_BRANCH, has_origin, None

    return None, BASE_NONE, has_origin, None


# ── the one entry point ───────────────────────────────────────────────────────


def _capture(outcome, repo_name, identity, state, mapping, cand, chosen=None):
    """Build the Witness from exactly what `resolve()` consulted (see `Witness`)."""
    # Exclude every candidate that IS the chosen repository, not merely the one directory
    # that was picked. A sibling linked worktree is a different path over the same store,
    # so fingerprinting it as an unrelated candidate made any commit in the chosen repo
    # flip the re-check to false while a fresh resolve was unchanged — a FALSE ALARM that
    # breaks the not-promised clause by the back door. `same_repository()` already knows
    # this (common git dir), and using it here is what stops the two notions disagreeing.
    # It is the layout this tool actually runs in: harness-sdd is worked through linked
    # worktrees. Called at RESOLVE time, where child processes are allowed.
    others = tuple(
        (lex, _storage_fingerprint(lex))
        for lex, _real in cand
        if chosen is None or not same_repository(lex, chosen)
    )
    return Witness(
        outcome=outcome, repo=repo_name,
        binding=repo_name, identity=identity, manifest_state=state,
        manifest_entry=mapping.get(repo_name) if repo_name is not None else None,
        candidates=cand, others=others,
    )


def resolve(ref, repo_name, hdir):
    """WHICH repository is this claim about? Returns a `Resolution`, never a guess.

    `repo_name` is the binding (`<repo>=<ref>`) or None. Everything the caller needs to
    re-check this answer later comes back attached to it — see `Resolution.witness`.
    """
    state, mapping = manifest_repos(hdir)

    if repo_name is not None:
        cand = ()          # a binding did no search, so there is no uniqueness to witness
        if state == "unreadable":
            # UNREADABLE IS NOT ABSENT. `absent` means no authority exists, and only that
            # licenses a search; `unreadable` means the authority exists and this checkout
            # cannot read it (a partial write, tab indentation). Falling back to a basename
            # search there can return a confident `resolved` for the WRONG repository —
            # precisely the guess I1 exists to forbid. Preserve the uncertainty instead.
            return Resolution(
                UNREADABLE, repo=repo_name, binding=repo_name, manifest_state=state,
                witness=_capture(UNREADABLE, repo_name, None, state, mapping, cand),
                detail="the umbrella manifest is configured but could not be read, so "
                       "there is no authority for where %r is — and a search would be a "
                       "guess" % repo_name,
            )
        if state == "present":
            if repo_name not in mapping:
                return Resolution(
                    UNDECLARED, repo=repo_name, binding=repo_name, manifest_state=state,
                    witness=_capture(UNDECLARED, repo_name, None, state, mapping, cand),
                    detail="%s is not declared in the umbrella manifest" % repo_name,
                )
            lexical = mapping[repo_name]
            if not lexical or not os.path.exists(os.path.join(lexical, ".git")):
                return Resolution(
                    UNLOCATABLE, repo=repo_name, binding=repo_name,
                    manifest_state=state,
                    identity=Identity(lexical) if lexical else None,
                    witness=_capture(UNLOCATABLE, repo_name,
                                     Identity(lexical) if lexical else None,
                                     state, mapping, cand),
                    detail="%s is declared but cannot be read from this checkout"
                           % repo_name,
                )
            dirs = [lexical]
        else:
            dirs = [c for c in candidates(hdir) if os.path.basename(c) == repo_name]
            if not dirs:
                return Resolution(
                    UNLOCATABLE, repo=repo_name, binding=repo_name,
                    manifest_state=state,
                    witness=_capture(UNLOCATABLE, repo_name, None, state, mapping, cand),
                    detail="no repository named %r is visible near %s" % (repo_name, hdir),
                )
    else:
        cand = tuple(candidates(hdir, pairs=True))
        dirs = [lex for lex, _real in cand]

    hits = [d for d in dirs if resolve_commit(d, ref)]
    if not hits:
        return Resolution(
            UNKNOWN, repo=repo_name, binding=repo_name, manifest_state=state,
            candidates=cand,
            witness=_capture(UNKNOWN, repo_name,
                             Identity(dirs[0]) if (repo_name is not None and dirs) else None,
                             state, mapping, cand),
            identity=Identity(dirs[0]) if (repo_name is not None and dirs) else None,
            detail="%s does not name a commit in %s"
                   % (ref, repo_name or ("any repository near %s" % hdir)),
        )

    if repo_name is None and len(hits) > 1:
        distinct = []
        for h in hits:
            if not any(same_repository(h, d) for d in distinct):
                distinct.append(h)
        if len(distinct) > 1:
            return Resolution(
                AMBIGUOUS, manifest_state=state, candidates=cand,
                witness=_capture(AMBIGUOUS, None, None, state, mapping, cand),
                detail="%s resolves in %d different repositories (%s)"
                       % (ref, len(distinct),
                          ", ".join(os.path.basename(d) for d in distinct)),
            )
        hits = distinct

    chosen = hits[0]
    base, evidence, has_origin, advertised = default_branch(chosen)
    return Resolution(
        RESOLVED,
        repo=repo_name or os.path.basename(os.path.realpath(chosen)),
        binding=repo_name,
        directory=chosen,
        identity=Identity(chosen),
        manifest_state=state,
        candidates=cand,
        base=base, base_evidence=evidence, has_origin=has_origin,
        base_tip=advertised, commit=resolve_commit(chosen, ref),
        witness=_capture(RESOLVED, repo_name, Identity(chosen), state, mapping, cand,
                         chosen=chosen),
    )


def revalidate(resolution, hdir):
    """Would a fresh `resolve()` give the same answer? Delegates to the captured Witness.

    Kept as the callable entry point; the LIST of what matters lives in `Witness`, built by
    `resolve()` where each dependency is used, so this function can no longer disagree with
    it about which inputs were relevant.
    """
    w = resolution.witness()
    if w is None:
        return False, "this resolution carries no witness"
    return w.still_holds(hdir)
