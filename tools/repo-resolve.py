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
#     `published`   the remote said so JUST NOW (`ls-remote --symref`).
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
OUTCOMES = (RESOLVED, AMBIGUOUS, UNDECLARED, UNLOCATABLE, UNKNOWN)

# ── how we know what the default branch is (see I3) ───────────────────────────
BASE_PUBLISHED = "published"
BASE_CACHED = "cached"
BASE_DECLARED = "declared"
BASE_SOLE_BRANCH = "sole-branch"
BASE_NONE = "none"
BASE_EVIDENCE = (BASE_PUBLISHED, BASE_CACHED, BASE_DECLARED, BASE_SOLE_BRANCH, BASE_NONE)

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


class Resolution(object):
    """The answer, with its own uncertainty attached. See the header.

    `outcome` is always readable. `directory` and `base` raise `Uncertain` when the
    resolution does not have them, so a caller cannot slide from "I could not tell" to
    "yes" by forgetting a branch.
    """

    __slots__ = ("outcome", "repo", "identity", "detail", "candidates",
                 "manifest_state", "_directory", "_base", "base_evidence",
                 "has_origin", "commit")

    def __init__(self, outcome, repo=None, directory=None, identity=None, detail=None,
                 candidates=(), manifest_state="absent", base=None,
                 base_evidence=BASE_NONE, has_origin=False, commit=None):
        assert outcome in OUTCOMES, outcome
        assert base_evidence in BASE_EVIDENCE, base_evidence
        self.outcome = outcome
        self.repo = repo
        self.identity = identity
        self.detail = detail
        self.candidates = tuple(candidates)
        self.manifest_state = manifest_state
        self._directory = directory
        self._base = base
        self.base_evidence = base_evidence
        self.has_origin = has_origin
        self.commit = commit

    @property
    def certain(self):
        return self.outcome == RESOLVED

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
        return False

    def witness(self):
        """Everything about IDENTITY this resolution assumed, as one comparable value.

        A caller re-checks a resolution by comparing witnesses, so it never assembles the
        parts itself — the omission that let a new call path silently lose the manifest
        from its fingerprint is not expressible here, because the witness comes back with
        the resolution or not at all.
        """
        return (
            self.outcome,
            self.repo,
            self.identity.as_tuple() if self.identity else None,
            self.manifest_state,
            self.candidates,
        )


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
            current = key
            repos.setdefault(current, None)
        elif current is not None and key == "path" and value:
            repos[current] = os.path.normpath(
                os.path.join(mdir, value.strip('"').strip("'"))
            )
    if not repos:
        return "unreadable", {}
    return "present", repos


def candidates(hdir):
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
            seen.append(path)

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
    return seen


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
    """(base, evidence, has_origin) — WHAT the default branch is and HOW we know.

    Order: what the remote says NOW, then the local cache of what it used to say, then
    what this repository can establish about itself. The cache is deliberately NOT first:
    `refs/remotes/origin/HEAD` is a snapshot, and a remote that moves its default while
    the old branch still exists leaves it pointing at the old one. Asking costs one
    bounded call on a path that already talks to the network; being wrong costs a false
    attestation, which is the thing this whole feature exists to prevent.
    """
    has_origin = _git(["remote", "get-url", "origin"], cwd=repo) is not None

    if has_origin:
        symref = _git(["ls-remote", "--symref", "origin", "HEAD"], cwd=repo, timeout=10)
        for line in (symref or "").splitlines():
            parts = line.split()
            if len(parts) >= 3 and parts[0] == "ref:" and parts[2] == "HEAD":
                branch = parts[1]
                if branch.startswith("refs/heads/"):
                    ref = "origin/" + branch[len("refs/heads/"):]
                    if resolve_commit(repo, ref):      # usable only if we have it locally
                        return ref, BASE_PUBLISHED, has_origin
                break

    cached = _git(["symbolic-ref", "--quiet", "refs/remotes/origin/HEAD"], cwd=repo)
    if cached:
        ref = cached[len("refs/remotes/"):] if cached.startswith("refs/remotes/") else cached
        if resolve_commit(repo, ref):
            return ref, BASE_CACHED, has_origin

    declared = _git(["config", "--get", DECLARED_DEFAULT_CONFIG], cwd=repo)
    if declared and resolve_commit(repo, declared):
        return declared, BASE_DECLARED, has_origin

    if not has_origin:
        names = _git_lines(["for-each-ref", "--format=%(refname:short)", "refs/heads/"], cwd=repo)
        if names is not None and len(names) == 1 and resolve_commit(repo, names[0]):
            return names[0], BASE_SOLE_BRANCH, has_origin

    return None, BASE_NONE, has_origin


# ── the one entry point ───────────────────────────────────────────────────────


def resolve(ref, repo_name, hdir):
    """WHICH repository is this claim about? Returns a `Resolution`, never a guess.

    `repo_name` is the binding (`<repo>=<ref>`) or None. Everything the caller needs to
    re-check this answer later comes back attached to it — see `Resolution.witness`.
    """
    state, mapping = manifest_repos(hdir)

    if repo_name is not None:
        if state == "present":
            if repo_name not in mapping:
                return Resolution(
                    UNDECLARED, repo=repo_name, manifest_state=state,
                    detail="%s is not declared in the umbrella manifest" % repo_name,
                )
            lexical = mapping[repo_name]
            if not lexical or not os.path.exists(os.path.join(lexical, ".git")):
                return Resolution(
                    UNLOCATABLE, repo=repo_name, manifest_state=state,
                    identity=Identity(lexical) if lexical else None,
                    detail="%s is declared but cannot be read from this checkout"
                           % repo_name,
                )
            dirs = [lexical]
        else:
            dirs = [c for c in candidates(hdir) if os.path.basename(c) == repo_name]
            if not dirs:
                return Resolution(
                    UNLOCATABLE, repo=repo_name, manifest_state=state,
                    detail="no repository named %r is visible near %s" % (repo_name, hdir),
                )
    else:
        dirs = candidates(hdir)

    hits = [d for d in dirs if resolve_commit(d, ref)]
    if not hits:
        return Resolution(
            UNKNOWN, repo=repo_name, manifest_state=state,
            candidates=tuple(dirs) if repo_name is None else (),
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
                AMBIGUOUS, manifest_state=state, candidates=tuple(dirs),
                detail="%s resolves in %d different repositories (%s)"
                       % (ref, len(distinct),
                          ", ".join(os.path.basename(d) for d in distinct)),
            )
        hits = distinct

    chosen = hits[0]
    base, evidence, has_origin = default_branch(chosen)
    return Resolution(
        RESOLVED,
        repo=repo_name or os.path.basename(os.path.realpath(chosen)),
        directory=chosen,
        identity=Identity(chosen),
        manifest_state=state,
        candidates=tuple(dirs) if repo_name is None else (),
        base=base, base_evidence=evidence, has_origin=has_origin,
        commit=resolve_commit(chosen, ref),
    )


def revalidate(resolution, hdir):
    """Does this resolution still describe the world? Filesystem + one file read only.

    Safe to call while holding a lock: it re-reads the manifest text and re-resolves the
    recorded paths, but spawns no child process and touches no network. Returns
    (True, None) or (False, what changed).
    """
    if resolution.identity is not None and not resolution.identity.revalidate():
        return False, "%s now resolves to %s, not %s" % (
            resolution.identity.lexical,
            os.path.realpath(resolution.identity.lexical),
            resolution.identity.real,
        )
    state, mapping = manifest_repos(hdir)
    if state != resolution.manifest_state:
        return False, "the manifest went from %s to %s" % (resolution.manifest_state, state)
    if resolution.repo is not None and state == "present":
        now = mapping.get(resolution.repo)
        was = resolution.identity.lexical if resolution.identity else None
        if now != was:
            return False, "the manifest now puts %s at %s, not %s" % (
                resolution.repo, now, was)
    if resolution.candidates:
        if tuple(candidates(hdir)) != resolution.candidates:
            return False, "the set of nearby repositories changed"
    return True, None
