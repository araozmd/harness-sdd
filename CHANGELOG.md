# Changelog

All notable changes to the harness body are recorded here. Versions follow
[SemVer](https://semver.org/) and are stamped into every install's
`.harness/.harness-version` (see `CLAUDE.md` → Versioning).

## [0.67.0] — 2026-08-18

### Added — ✨ the landing record becomes a VERDICT (E99-F129)

v0.64.0 made `done` carry a landing record and deliberately verified nothing: every ref
landed as `verified: "unchecked"`. This turns that record into a checked claim — the ref is
resolved with git, tested against the repository's default branch, and a claim that is
**provably wrong** is refused.

**One question, answered once.** Verification is not a feature; it is a single question
asked of every ref: *what happens when verification is impossible?* The first attempt
answered it per input, as fixes accumulated, and five review rounds each found the same
shape again — a default branch guessed by name, one sha attesting many slices, a stale local
tip, a slice repository located by directory basename, an unrecognised hash format. Every
one was another input for which "I cannot check" silently became "fine, proceed". So the
answer is a **table**, written before the code, carried in `tools/tasks-lock.py`'s header and
`store/local.md`, and mirrored row-for-row by the suite:

| # | situation | outcome | what the row costs |
|---|---|---|---|
| 1 | `none:<why>` | `declared` | no-code work stays expressible; the reason is required |
| 2 | the ref resolves to no git object anywhere | `unchecked` + warning | an offline machine, or a repo this checkout cannot see, is never blocked |
| 3 | a binding names a repo the **manifest does not contain** | **REFUSED** | a board that would be refused here is one `next-task.mjs` already halts on |
| 4 | the manifest names it, directory absent/unreadable here | `unchecked` | a partial checkout keeps working |
| 5 | the repo is located, the object is unknown in it | `unchecked` | an unfetched clone is not an accusation |
| 6 | no default branch can be determined | `unchecked` | nothing is invented to compare against |
| 7 | ancestry is checkable and TRUE **against a confirmed base** | `ancestor` | the only source of a proof |
| 8 | ancestry is FALSE **and** the base tip is confirmed current | **REFUSED** | the guard's whole point |
| 9 | ancestry is FALSE, tip **not** confirmed | `unchecked` | a stale view never rejects merged work |

**The asymmetry that decides every row, stated in the code:** a *false attestation* is worse
than no attestation — the record gains the authority of a check that never happened, and
every later reader treats it as settled — so `ancestor` comes only from row 7. A *false
refusal* is worse than a silent pass — a guard that rejects genuinely merged work gets
routed around, switched off, or worked around with `none:<why>`, after which it protects
nothing — so refusal is reserved for the two provably-wrong claims: rows 8 and 3.

**Rows 3 and 4 are the distinction the previous attempt was missing.** A **malformed claim**
(the board names a repository the project does not declare — checkable with no I/O at all)
is refused; **not being able to see a repository from here** is this checkout's limitation
and degrades. Row 3 applies only where a manifest is configured and readable: with none
there is no authority to call a claim malformed, so resolution falls back to a best-effort
search and every miss degrades.

**Newly enforced here** (rows 3, 4, and the two fixes below). **Carried from the earlier
attempt, already built and reviewed there**: per-slice ancestry checked in the slice's OWN
repository (row 7/8 scoping); default-branch **discovery** — the published symref, else
`ls-remote --symref`, else an explicit `harness.defaultBranch` or a repository's single
branch, never a name guess (row 6); remote-tip confirmation before a definitive refusal
(rows 8/9); and probes resolved **before** the board lock with a shape fingerprint
re-validated inside it — holding the sole write lock across bounded network probes starved
concurrent writers out of their own transitions.

**A repository's location is the manifest's answer** (round-5 P1). The previous code scanned
the harness dir's parent for a child whose basename equalled the manifest key, so the
shipped example's sibling layout (`path: ../viernes-bff`) and any aliased key resolved
**nowhere** — and unmerged evidence for such a slice was accepted as `unchecked`, reaching
`done` unexamined. Paths now resolve against the **manifest file's own directory**, which is
what `umbrella.manifest.example.yaml` has always documented. Measured on a fixture whose key
(`alpha`) is deliberately not its directory (`../elsewhere/alpha-checkout`): the landed
commit verifies and the unmerged one is refused. Both readers of that file — this helper and
`next-task.mjs`, which parses it independently — are held to the same answer by a test.

**What an object id is, is git's answer** (round-5 P2). `^[0-9a-fA-F]{7,40}$` silently
excluded SHA-256's 64-character ids: they fell through to "not a commit id" and were
recorded unchecked, so an unmerged sha256 commit reached `done` unexamined. Nothing
pattern-matches an id now — every non-`none:` value goes to
`git rev-parse --verify <ref>^{commit}` and git decides. Proven on a real
`--object-format=sha256` repository, not a synthetic 64-character string.

Two consequences of asking git, handled deliberately: a **branch name resolves too**, and a
branch **moves**. So the record keeps both, and they mean different things — `ref` is what
the operator claimed, verbatim; **`commit`** (new, additive) is the immutable id it resolved
to, which is what ancestry was computed on and what a re-audit must re-check. `commit` is
present exactly when this checkout resolved the object.

**A proof names the FULL proof set** (round-5 P2). All three acceptance surfaces require, of
every `ancestor` record, the three things a re-check needs: **`commit`** (WHAT was checked —
`ref` may be a branch, which moves), **`repo`** (WHERE — a commit id proves nothing until you
know which repository to look for it in) and **`base`** (AGAINST WHAT — "ancestor of" has a
second operand). Only `commit` was required at first, so a hand-edited or imported board
could assert `{"ref":"x","commit":"deadbeef","verified":"ancestor"}` and be **accepted** by
all three — a claim nobody can re-run `git merge-base --is-ancestor` on, which is the defect
this whole feature exists to remove rather than a milder form of it. Per-slice records gained
`base` for the same reason (`repo` was already required of every slice). Scoped to the
unsliced feature-level record and to each slice record: a **sliced** feature's `ref` is a
joined summary across repositories, so there is no single commit/repo/base for it and each
slice carries its own — a carve-out held in place by its own test, because the failure mode
of over-reaching is that every sliced `done` the tool writes fails its own validation.

**A second dimension: WHICH repository is the claim about?** The nine rows decide a verdict
for a *(ref, repository)* pair and silently presumed that pair was settled. It is not — it
is established by a search order, a path out of a manifest, and an assumption that a ref
names one repository — and that presumption produced findings four separate times before it
was written down. It now has its own stated contract beside the rows:

- **A binding names the repository; an unbound ref must be unambiguous.** `<repo>=<ref>` is
  legal on **any** feature (the contract half refused it on single-repo features because
  nothing verified the name; the name is checked now, and a binding is the only way to
  disambiguate). An unbound ref that resolves in two or more repositories is **REFUSED**,
  naming both remedies. Never "take the first": the harness dir and its parent are searched
  *before* the children, so the first hit is the umbrella's own bookkeeping repository —
  the one that never holds feature work. Measured: `--evidence main` recorded
  `{"verified": "ancestor", "repo": "umb"}` for a feature whose work was in a child.
- **Identity is the `realpath`, kept beside the lexical path.** A lexical path is not an
  identity: retargeting a symlink leaves the manifest text identical while the repository
  underneath changes, and the old witness walked straight past it. Two candidates are the
  *same* repository when their common git dir matches, so linked worktrees are not
  ambiguity. Not covered, deliberately: a repository replaced in place — the fingerprint is
  a coherence check over a sub-second window, not a defence against a swapped checkout, and
  hashing the base tip in would abort whenever anyone else's merge advanced the branch.
- **The single-repo path now carries the same discipline** — the chosen repository *and*
  the candidate set that made the choice unambiguous, so a repository appearing beside the
  board between plan and write aborts instead of re-deciding silently.

**That contract is not implemented here.** `tools/tasks-lock.py` **consumes**
`tools/repo-resolve.py` (0.65.0) rather than carrying a second copy of it: ~350 lines of
inline repository search, manifest reading, default-branch discovery and remote-tip
confirmation are **deleted**, and what remains is one `resolve()` call dispatched on
`.outcome`, then ancestry. Two of the findings above are now answered *by construction*
instead of by code that has to keep remembering:

- `refs/remotes/origin/HEAD` can never drive a refusal. A row-8 refusal is gated on
  `Resolution.base_confirmed`, which is `False` for a `cached` base **inside the resolver**;
  there is deliberately no code here that re-derives it. Mutating only the resolver — making
  `cached` confirmable — flips the same command from `unchecked` to REFUSED, which is the
  proof that the rule has exactly one home.
- The plan→write fingerprint cannot be omitted by a call path. It is no longer assembled
  beside the resolution: `resolve()` returns a `Witness` captured where each dependency was
  used, and every resolution's witness is collected. The bound-but-**unsliced** path — which
  previously skipped the manifest witness, because the old fingerprint scoped it to sliced
  features — now aborts when its repository is repointed mid-write, with no new code for
  that case.

What is left in the board writer is what only it can know: the nine rows, the ancestry call
(which needs an **exit code**, deliberately not offered by the resolver, so "not an ancestor"
and "the invocation failed" cannot be confused), the shape fingerprint over the **board's**
slice set, and the refusal wording.

**Row 8 vs row 9, one misapplication fixed:** a declared local default was treated as
definitive even with an `origin` configured but unreachable. Discovery only falls back to a
local signal *after* `ls-remote` fails, so in that state what "merged" means was never
established — that is row 9. Measured: a commit already on the remote's `main` was REFUSED
in an offline clone.

**Additive.** `landed` and `commit` are optional in the schema; boards written by v0.64.0
stay valid, and their `unchecked` rows stay `unchecked` until something rewrites them.

**The fingerprint covers the manifest, not just the slice names.** The pre-lock resolution
is re-validated under the lock against a fingerprint of what it assumed — and since the
manifest is the authority for row 3 and the locator for row 4, it is part of that. It was
not: repointing a repo's `path` while the probe was in flight left the slice names matching,
so a proof computed against the old checkout was written for a repository the board no
longer pointed at (reproduced: `verified: "ancestor"` landed while the manifest named a
checkout that had never seen the commit). The witness pins **exactly what this
resolution consulted** — the manifest's state and the entry the binding resolved through,
not the whole file, or an unrelated repo's edit would abort ordinary concurrent writes; and
the entry itself rather than a content hash, because both detect the change but only the
entry lets the abort name *which* repository moved and *where*. (It is captured by
`resolve()` at the point of use, so this is now one clause of the resolver's
`Witness.still_holds` rather than a separate list this file maintains.)
A manifest that has become absent or unreadable also aborts: an abort is **not** a refusal —
nothing is written and the re-run converges (it plans and re-validates under the same new
state) — whereas degrading would write a record justified by an authority that no longer
exists.

**The suite no longer depends on the developer's git config.** Two bare remotes were created
without setting `HEAD`, so on a host with `init.defaultBranch=main` they published `main`
and the suite was green — while on git's historical default they publish an unborn `master`,
default-branch discovery (which never guesses a branch NAME) finds nothing to compare
against, and a
local-only commit was recorded `unchecked` instead of REFUSED. Measured: forcing
`init.defaultBranch=master` exited **1** at R10. Every fixture now names its own branch, and
the suite **overrides `init.defaultBranch` with a sentinel** that is neither `main` nor
`master`, so inheriting it is never accidentally correct and the dependency cannot be
reintroduced silently — with a setup-time assertion that the override actually reached git
(`GIT_CONFIG_*` needs git ≥ 2.31 and is otherwise ignored). A `set -e` abort at a fixture
step now says so instead of looking like a truncated pass. Measured both ways: the pre-fix
state is **green here and red on a `master` host**; with the sentinel, the same omission is
**red here**.

**The installed interfaces no longer describe the half that was replaced** (round-5 P2). The
0.64.0 contract half verified nothing, and several places still said so: `store/local.md`
told the reader that anything other than `none:<why>` "is transcribed verbatim and recorded
`verified: "unchecked"` … that code does not exist here yet"; `set-status --help` said
"(recorded verbatim and marked unchecked — this half verifies nothing)"; and the three
acceptance surfaces' own comments (`store/tasks.schema.json`, `tools/validate-board.py`,
`tools/next-task.mjs`) each claimed the write path could not produce `ancestor`. The harm is
concrete: an operator reading either INSTALLED interface is told an unmerged but resolvable
ref will be accepted as `unchecked`, when row 8 now **refuses** it — and concludes the tool
is broken. Swept rather than spot-fixed, after the same class appeared in two consecutive
rounds.

The suite mirrors the table and the identity contract: **25 cases**, every refusal paired with a control that must
SUCCEED. The contract half's `R18` — which proved that half performed **no** I/O — is
deliberately **retired rather than weakened**: that claim is false here by design, and its
successor is `R17`, which allows I/O but proves none of it happens **inside** the board lock.

## [0.66.0] — 2026-08-18

### Added — ✨ a round's outcome is stated, and the trend counts what was acted on (E99-F126 + E99-F116)

`tools/pr-round-trend.sh` read exactly one file per round, `round-<n>/blocking.json`, and
took its **length** as the round's finding count. That file answers neither question the
trend asks, and the two failures that follow are one defect surface.

**An empty array meant two opposite things.** "Reviewed, nothing blocked" and "no review ever
landed" are both `[]`, byte for byte. Measured on araozmd/harness-sdd#141: the rounds went 2
blocking → round 2 **watcher timeout** (exit `2`, zero Codex activity) → 2 blocking; recording
the timed-out round as `[]` produced *"converging — the finding rate is coming down. One more
round is rational."* and deleting that one file changed the verdict to `insufficient`. The
flat 2,2 was the honest signal and the tool never saw it, so the bias ran toward "spend
another round" **exactly when review was not landing** — the case where another round is most
wasteful — and recording a timeout as a clean round was silently rewarded. The loop already
guards this two-meanings-of-empty hazard at the MERGE gate (`tools/pr-gate.sh` consults
`wait-for-codex.sh evaluate` for precisely this reason); it did not guard it here.

**The rate was blind to a severity override.** `blocking.json` is filtered to the configured
`pr_loop.blocking_severities`. On viernes-ai/viernes-web PR #85 three consecutive Codex **P2**s
were each judged blocking and fixed while P2 sat outside that filter, so every `blocking.json`
was empty and the tool reported *"no round with a readable blocking.json — nothing to trend"*
through a textbook non-converging run. The one tool built to detect non-convergence was silent.

Two files the loop now writes and the trend now reads:

- **`round-<n>/outcome`** — one word: `findings` | `clean` | `timeout` | `unresolved`. Written
  at **every** terminal state, including the ones that previously just aborted. Only
  `findings`/`clean` enter the finding **rate**. `timeout`/`unresolved` are reported in their
  own `NEVER REVIEWED` block and in `not_reviewed[]` — neither folded into the rate nor
  dropped, because omitting them would answer `insufficient` and hide a run that is failing to
  get reviewed at all.
- **`round-<n>/acted.json`** — one row per finding the round **acted on**, `severity` preserved
  per row plus an `override` flag. Appended at **dispatch** (immediately before a finding goes
  to a `pr-fixer`, before an in-session fix, or as the cap row declares a surviving comment) —
  never at classification time, where the gate has not been asked yet and its answer can be
  `merge`. A set written at classification would record *intent*, and a round can contradict
  it two steps later; `acted.json` has to mean *these findings were acted on* or it is not an
  honest input to a convergence rate.

`blocking.json` and `tools/pr-gate.sh` are **unchanged**: whether a P2 may block a MERGE stays
a separate, deliberately conservative decision from whether it counts as review work. The
runbook now names the two honest moves when the badge is wrong — raise the threshold, or
override this one finding and record it — and says plainly that recording is not permission,
it is what makes the work countable.

**Backward compatible, and honest about it.** A cache written before this change has neither
file. Derivation order: a recorded `outcome` → a non-empty finding set ⇒ `findings`
(self-proving) → an empty set with `pr.json` on disk ⇒ ask `wait-for-codex.sh evaluate`, the
same offline probe the merge gate uses, which catches the #141 shape in an **old** cache too →
otherwise `unknown`: still counted so a legacy cache keeps trending, but named in
`unrecorded_rounds[]` with the verdict flagged as possibly optimistic. Never silently clean.

**The non-converging remedy is conditioned on the diff.** New optional `--diff-files` /
`--diff-lines` (fed from `tools/change-size.sh`). "SPLIT THIS PR" is right for the
17,202-addition diff this tool was built on and unfollowable on PR #85's 2-file/~150-line diff
whose four findings all landed in one function — the operator overrode it by hand, and E17-F04
disputed the same verdict on the record. The downgrade requires **both** a supplied width and a
single concentrating file, so with no flags the output is byte-identical to before.

**A round that leaves the rate does so into one of two named buckets, never one.** The first
cut of this fix reproduced its own defect one level down: a round carrying `outcome=findings`
whose count file was missing landed in `not_reviewed` and printed under **NEVER REVIEWED**,
sending the operator to check the Codex GitHub App and the watcher ceiling — while the
recorded outcome *proves* a review landed and the component that actually failed is
classification. Healthy component inspected, broken step unnamed. `not_reviewed[]` now means
only "the review did not resolve" (`timeout`/`unresolved`, remedy: the App/watcher). The new
`uncounted[]` means "there is no number to trend and the review is not what failed" — either
`reviewed-uncounted` (an outcome proves a review landed; the count file is missing or
unparseable) or `no-record` (nothing on disk says what happened, which is a claim that we
cannot tell, not a claim that the review failed). Its remedy names the round's own cache:
re-derive it with `wait-for-codex.sh evaluate`, re-run classification for that round dir, or
rebuild it from the gh API. Both stay out of the rate — an uncounted round is not evidence of
convergence either way.

**An outcome file is evidence, and a step that did not observe the review may not overwrite
it.** The bucket split above is undone at the write path if a later step clobbers a recorded
`findings` with `unresolved`, and two steps did exactly that. The rule the runbook now states
as a principle, and applies at both sites: before overwriting an outcome, ask whether the exit
code being reacted to actually carries information about whether a review landed.
`pr-gate.sh` exit **9** does — the gate ran `wait-for-codex.sh evaluate` against the round's
own files and nothing resolved — so it may replace. `pr-gate.sh` exit **4** (`blocking.json`
missing or not a JSON array) and a `pr.json` too broken to yield a `headRefOid` do **not**:
they are statements about the *cache*, not about Codex, and a review may have landed and been
recorded seconds earlier. Both now call a new `outcome_mark_unresolved` helper that leaves a
recorded `findings`/`clean` alone, so the round reads as `reviewed-uncounted` — a review
landed, the count is missing — instead of being reported as NEVER REVIEWED and sending the
operator to inspect a healthy Codex App. The `case` at step 2b keeps its bare writes: the
watcher IS the observer and it is the first write to the file.

New JSON fields on `--format json`: `not_reviewed[]`, `uncounted[]`, `unrecorded_rounds[]`,
`overrides`, `override_severities[]`, `remedy`. Every existing field keeps its meaning.

New suite `tests/test_pr_round_outcome.sh` (parses and runs under `/bin/dash`).

## [0.68.0] — 2026-08-18

### Added — ✨ the gate runs the strictest available shell, and says which one (E99-F135)

`tools/run-tests.sh` invoked `sh`. On Debian/Ubuntu `sh` **is** dash, so every bashism in a
suite was already a live defect for those users — and invisible from a Mac, where `sh` is bash
in POSIX mode. `all 42 suites passed` was therefore a claim about the developer's machine.

The runner now probes for the strictest shell it can actually find (dash → posh → ash → sh),
**executes** the suites under it, and prints it: `all 42 suites passed (/bin/dash [PROGRAM:dash
PROJECT:dash-16], --jobs 8)`.

**Executing matters, parsing is not enough.** `local`, `[[ ]]`, arrays, `echo -e` and `${x^^}`
all parse cleanly under dash and fail at RUNTIME, so a `-n` check alone would have shipped a
green meaning "it parses on Debian". The `-n` pre-flight is kept as well — it is nearly free and
catches the class at the cheapest point — and it runs over **every** suite, including exempt
ones. New exit code **3** = a suite or tool did not parse; nothing was executed.

**The allowlist ships EMPTY, and that is the point.** `tests/dash-allowlist.txt` exists so that
if a suite ever cannot run under the strict shell, the exemption is NAMED and attributable
(`# known-broken under dash: <suite> — <issue id>`) rather than a suite that quietly stopped
running. An unnamed skip is the invisible debt this gate exists to end, so the runner exits 4 on
a malformed entry rather than guessing. An exemption buys exemption from EXECUTING and nothing
else: the suite still runs under the host `sh`, still gets its parse pre-flight, and is counted
on the stdout summary (`, N exempt`) — not only in a stderr warning a caller may never capture.

**Two scopes, on purpose.** Allowlist *validation* is file-wide: every entry is parsed and
checked against the disk on every invocation, so a stale entry is reported even by someone
running a single suite (narrowing it to the selection would let the list rot until the next full
run). *Exemption* is intersected with the selected suites: applied file-wide it reported
`ran under /bin/sh` about a suite that had not run at all, which is a false statement in the one
line this feature exists to make trustworthy.

Sequenced deliberately after E99-F134 so the list could start empty rather than as a list of
excuses.

### Fixed — 🐛 the pr-loop sandbox trusted `command -v` (E99-F135)

`tests/test_pr_loop.sh`'s `mk_sandbox_bin` linked `command -v env` into a sandbox PATH. **dash
returns the first NAME match on PATH regardless of the execute bit; bash skips
non-executables.** With a mode-0644 `env` earlier on PATH, dash linked the unusable one and
`env … sh` died with 126 — one assertion, in one suite, green under bash. It also did
`ln -sf printf <bin>/printf`, a symlink to itself, broken under every shell and unnoticed
because nothing exec'd it. Replaced with a PATH walk that demands `-f` and `-x`.

Found by running the suites under dash for the first time — which is the whole argument for
this change.

## [0.65.0] — 2026-08-17

### Added — ✨ an explicit repository resolver (E99-F129c)

`tools/repo-resolve.py` answers one question — **which repository is a claim about, and
may that answer be trusted?** — and returns a value that makes its own uncertainty
impossible to ignore. It contains no ancestry logic, no verdicts and no board writes.

**Why it is a module and not a few helpers.** Landing verification decides, for a
*(ref, repository)* pair, whether work merged; nine rows enumerate those verdicts.
Establishing the **pair** is a different question, and it was implicit machinery threaded
through the write path — a search order here, a manifest read there, a fingerprint
assembled somewhere else. Correctness was by convention across ~9 functions, and every new
call path had to remember to participate in all of them. It kept not being remembered, in
six separate review findings: a slice repository located by directory basename; the
manifest missing from the plan→write fingerprint; an unbound ref silently taking the first
of several candidates; a lexical path a retargeted symlink walks past; **a new call path,
added to fix the third of those, which omitted the fingerprint again**; and
`refs/remotes/origin/HEAD` trusted as the remote's answer when it is only a cache of a
former one. The last two are the argument: a witness assembled *beside* a resolution can be
forgotten by the next path, while a witness that **is** the resolution cannot; and "is this
base still the default branch?" is a question about identity, not about ancestry.

The contract it publishes (and now owns):

- **I1 — search only when unambiguous.** A binding names the repository; without one the
  ref must resolve in exactly one, and two or more is `AMBIGUOUS` — a value the caller must
  handle, never a repository it can use. Never "the first": the search order starts at the
  harness dir's own repository, which never holds feature work. Linked worktrees of one
  repository are one repository (`--git-common-dir`), not an ambiguity.
- **I2 — identity is the lexical path *and* its realpath**, as one value with one
  comparison, using filesystem calls only so a caller may re-check it while holding a lock.
  Not covered, deliberately: a repository replaced in place.
- **I3 — the default branch carries its evidence**: `published` (the remote, asked just
  now — name **and** tip), `published-stale-tip` (the remote named this branch, but our copy
  of it is behind the tip it advertised), `cached` (`origin/HEAD` — a snapshot of a *former*
  answer, never confirmed), `declared`, `sole-branch`, `none`. `base_confirmed` folds the
  rules into one boolean so no caller re-derives them differently.
  Confirming the *name* is not confirming the *tip*: `ls-remote --symref` advertises both in
  one call, and reading only the symref line left a base marked confirmed while the tracking
  ref was behind — an ancestry check against that stale copy **refuses work that is already
  merged**, and a false refusal is worse than a silent pass. The advertised sha comes back as
  `base_tip`, so a caller that happens to hold that object can answer against the real tip;
  callers need not distinguish the two `published*` values to stay correct, because
  `base_confirmed` already says no. The resolver never fetches: a resolver that mutates the
  repository it inspects is a new hazard, and it would spend a timing budget its caller did
  not agree to.
- **Uncertainty is falsy as well as unreadable.** `resolve()` always returns an object, so a
  default-truthy `Resolution` made `if r:` read as success for `ambiguous` and `unknown`
  alike — the same slide the raising accessors exist to prevent, one level cheaper.
  `__bool__`/`__nonzero__` now follow `certain`.
- **Uncertainty is a value you cannot spend.** `Resolution.directory` and `.base` *raise*
  when the resolution does not have them, so "I could not tell" cannot slide into "yes".
- **The witness comes back with the resolution**, so a call path cannot omit it.
- **`resolve()` captures what it depended on, as a `Witness`.** The promise below was
  never wrong, but the LIST of inputs it entails was maintained in two places — and only
  `resolve()` actually knew. Three findings were the same shape: the re-check compared the
  wrong field, then too few things, then too few things again (a neighbouring repository
  that *acquires* the ref between resolve and the locked re-check leaves every path and
  identity identical while a fresh resolve would answer `ambiguous`). So the capture moved
  to where each dependency is **used**: `Witness.still_holds(hdir)` is the entry point, and
  a dimension `resolve()` consults and forgets to witness is now a dimension it did not
  consult. Ref membership is captured as a conservative, filesystem-only fingerprint of each
  **non-chosen** candidate's refs and objects — sound in the direction that matters (a
  repository cannot gain a commit without writing to them) and deliberately over-reporting,
  since the cost is a re-run. The chosen repository is excluded precisely so the
  not-promised clause survives: its own branch advancing is somebody else's merge.
  The fingerprint observes where git actually **writes**: the whole `refs/` tree is walked
  (a loose ref goes inside `refs/heads/…`, which the parent's mtime does not follow) and
  every `objects/<xx>` fan-out directory is stat'd (a loose object lands inside one), plus
  `packed-refs` and the `objects/pack` listing. Gitfile and linked-worktree layouts are
  resolved by reading `commondir` — file reads only, so it stays lock-safe while reaching
  the same store `same_repository()` reasons about. It states what it does **not** see:
  objects borrowed via `objects/info/alternates` (the file is fingerprinted, the borrowed
  store is not), and any change leaving both listing and mtimes identical. Candidates are
  excluded from that membership check by REPOSITORY, not by directory: a sibling linked
  worktree is another path over the same store, and fingerprinting it as an unrelated
  neighbour made any commit in the chosen repository flip the re-check to false while a
  fresh resolve was unchanged — a false alarm that broke the not-promised clause by the
  back door, in the layout this tool actually runs in.
- **A manifest that declares the same repository twice is `unreadable`.** The later `path:`
  silently won, so a conflicted or partial edit resolved confidently against the *last*
  checkout — while `next-task.mjs` rejects duplicate keys outright, so the two readers of
  one file disagreed about whether it was usable at all.
- **An unreadable manifest is not an absent one.** `absent` means no authority exists, and
  only that licenses a basename search; `unreadable` (a partial write, tab indentation)
  means the authority exists and cannot be read, where a search can return a confident
  `resolved` for the **wrong** repository. New outcome `unreadable`, and the binding is
  refused.
- **`revalidate()` has a stated promise**: *a fresh `resolve()` with the same inputs would
  return the same outcome, the same repository, and the same certainty.* It had a name and
  an intuition instead, and two findings fell straight out of the gap — it compared the
  **wrong** thing (reading the chosen directory's basename as a manifest key, so an unbound
  resolution under an aliased manifest could never revalidate: fail-safe, but useless on the
  layout the manifest exists for) and **too few** things (only the chosen repository, so
  retargeting a *non-selected* candidate left it saying "unchanged" while a fresh resolve
  would answer `ambiguous`). Everything it checks now follows from that sentence — the
  chosen identity, the manifest's state, the manifest entry for a **bound** request, and the
  candidate set in paths **and identities**. What it deliberately does not promise: the
  default branch advancing (somebody else's merge, constant in a busy repository, and
  ancestry is monotone under fast-forward — aborting on it would make the guard fire so
  often it would be switched off). `binding` is now its own field: `repo` is the name to
  record, and a single field whose meaning depended on how you arrived is how the first of
  those findings happened.

Measured, on a remote that moved its default `main` → `trunk` while `main` still existed:
the cached symref still said `main`, and a commit reachable only from the *former* default
was previously attested as being on the default branch. The resolver answers
`origin/trunk` / `published`, and — when the remote is unreachable — falls back to the cache
while marking it `cached` / **not confirmed**.

New suite `tests/test_repo_resolver.sh` (7 cases, each paired with a control that must come
out *differently* on the same fixture; 4 mutations against the tip and truthiness rules, 4
killed, 0 survivors). It is verified under **dash** as well as the host `sh`: backticks
inside a double-quoted string are command substitution in every POSIX shell, and dash
parses eagerly where bash defers — so a suite that only ever ran under bash had never
actually been parsed by the shell Debian and Ubuntu call `sh`. It lands **unused by design**: this is the first of
two staged changes, and the verification rows consume it next.

## [0.64.0] — 2026-08-17

### Added — ✨ `done` must carry a landing record (E99-F102, contract half)

`done` is what stops the selector routing an item. So a feature marked `done` whose work
never merged is **both unshipped and unreachable** — nothing will ever pick it up again,
while downstream briefs cite it as a landed mechanism and reviewers act on the citation.
An audit of **148 `done` features across seven repositories** found **four**:

| feature | board says | reality |
|---|---|---|
| `E99-F58` | done | `b86e7cf` + `cfabbbd` on a **never-pushed** local branch here |
| `E99-F59` | done | `5f0296f` on a **never-pushed** local branch here |
| `E09-F02` | done, **all three slices `merged: true`** | its only PR, viernes-infra #24, **closed unmerged** |
| `E99-F29` | done | PR viernes-infra #31 **closed unmerged**; `origin/main` still emits `'en'` |

Every one was found by accident, and the harm is already in the corpus: the board entry for
`E99-F32` — the feature that actually shipped the Spanish Managed Login — **cites `E99-F29`
as landed**.

```
tasks-lock.py set-status <id> done --evidence <ref|none:why>
# a SLICED feature: one binding per slice repository
tasks-lock.py set-status <id> done --evidence <repo-a>=<ref> --evidence <repo-b>=none:<why>
```

⚠️ **What this records, and what it does NOT check.** This change is the **contract**: it
requires the attestation, parses it, binds it per repository, and enforces the record's
shape across all three acceptance surfaces. It performs **no verification** — it never runs
git, never opens a network connection, never resolves a repository, and never decides
whether a commit is reachable from a default branch. Every ref therefore lands as
`verified: "unchecked"` (or `"declared"` for `none:<why>`), with a warning saying so, and
`repo`/`base` are absent. **It cannot record `verified: "ancestor"`, by construction** —
that value is not in the writer's rank table and the literal appears nowhere in
`tools/tasks-lock.py`'s code. Verification is the follow-up, and it is what turns
`unchecked` into a verdict.

**Why ship the contract first.** Five review passes over a combined
contract-plus-verification change found the same defect class every time, at a flat rate,
and all of it on the verification side: a default branch guessed by name, one sha attesting
many slices, a stale local tip, a slice repository located by directory basename, an
unrecognised hash format. Every one is a way to reach a **wrong or missing verdict** —
*the guard cannot verify, so it lets `done` through anyway*. A half that never issues a
verdict cannot issue a wrong one. The worst this can do is record honestly that nothing was
checked, which is already strictly better than the say-so it replaces, because
`verified: "unchecked"` is greppable on the board and a silent `done` is not. It also makes
the follow-up reviewable on its own terms: everything left in it is I/O.

**Every feature, sliced or not — `slices[]` is NOT an attestation.** A sliced feature
*looks* attested: the schema refuses `done` unless every slice is `done` **and** `merged`.
But **nothing in the harness ever WRITES `slice.merged`** — every occurrence in `tools/` is
a read or a type assertion, and `store/local.md` has the agent set it through
`apply --mutator`. It is hand-typed, i.e. exactly the say-so this replaces, and `E09-F02` is
the proof: three slices all `merged: true`, the first slice's own `pr` pointing at that
closed PR. The two invariants are independent and a sliced feature must satisfy **both**.

**A sliced feature's evidence is bound per slice repository** — `--evidence <repo>=<ref>`,
repeated once per slice repo. A single feature-level value names no repository, so it
attests no particular slice: one slice's merge commit would carry the whole feature to
`done` while another sat unmerged. A bare ref on a sliced feature is **REFUSED** (naming the
form and the repos), as are an unknown repository, a repeated binding, and a missing one
(naming the repos still owed). `none:<why>` stays expressible per slice. The binding is also
what makes a *per-repository* verdict expressible at all when verification lands; here the
record keeps the repositories apart so that verdict has somewhere to go.

| `--evidence` | outcome |
|---|---|
| any reference (a sha, a PR URL, a tag) | accepted with a **warning**, recorded `verified: "unchecked"` — recorded, not proved |
| `none:<why>` | accepted, recorded `verified: "declared"`; the reason is required |
| omitted, on **any** feature (sliced included) | **REFUSED**, board byte-identical |
| **unbound** (`<ref>`, no `<repo>=`) on a **sliced** feature | **REFUSED** — it names no repository, so it attests no particular slice |
| `<repo>=<ref>` for a repo the feature has no slice in, or a slice repo left unbound | **REFUSED**, naming the unknown repo / the repos still owed |
| `<repo>=<ref>` on a feature with **no** slices | **REFUSED** — the repo name would be recorded against a repository the feature does not have |
| on any **non-`done`** transition | **REFUSED** — the record means one thing |

Note what is deliberately absent: this half never asks whether a string *looks like* a
commit id. That is a verification question — the 40-hex assumption it invites misses
SHA-256's 64-character ids entirely — and it belongs with the code that resolves objects.
Everything that is not `none:<why>` is transcribed verbatim and marked unchecked.

**The record, and the one rule that outlives the split.** `landed` is
`{ref, verified, repo?, base?}` plus `landed.slices` (one `{repo, ref, verified, base?}` per
slice repository), with `verified` a **closed enum** and `repo`/`base` **non-empty** —
mirrored and agreeing across `store/tasks.schema.json`, `tools/validate-board.py` (including
its zero-dependency fallback) and `tools/next-task.mjs`. The **rollup rule** — a feature-level
`ancestor` is illegal if any slice is not `ancestor` — is enforced on all three even though
nothing here can write that value, because it is what stops a proof being re-entered by
hand, and it must already be in place when the follow-up starts writing verdicts.
`repo`/`base` being non-empty matters for the same reason: a plain-string schema and an
`isinstance(..., str)` fallback both accept `""`, while the selector's `assertString` always
rejected it, so a board carrying `"repo": ""` would pass `init.sh` and then make **every**
`next-task.mjs` run die with `input-error` — legal by two acceptance surfaces and unusable
by the third.

**The documented workflow now writes `done` after the merge, not on the approval.** The
harness previously instructed *approve → `set-status done` → open the PR*. That order
defeats this mechanism twice over: at `done` time the only ref that exists is an unmerged
branch tip, so the "prefer the merge commit" instruction could not be followed and every
record would be unverifiable by construction (and, once verification lands, actively
**refused** as not-an-ancestor); and a PR later closed or abandoned leaves the feature
`done` and unselectable with work that never shipped — precisely the failure the record
exists to prevent. The order is now approve → open the PR (the feature stays `in-review`) →
**observe the merge** → `set-status done --evidence <merge commit>`, corrected in
`agents/orchestrator.md` (the route table, the build↔review loop, and its own
`### Writing \`done\`` section), `docs/WORKFLOW.md` (including the state diagram, whose
approve edge no longer lands on `done`), `store/local.md` and `.claude/commands/sdd-next.md`
(plus the installer's embedded copy). Pinned by **R19**, which greps the sections by
heading rather than the whole file. `none:<why>` is unchanged and remains the one legitimate
`done` with nothing to merge.

⚠️ **Known gap, stated rather than papered over: there is no board state for "approved,
awaiting merge".** Measured on the shipped selector: a feature left `in-review` is *not*
inert — `featureRoute` maps `in-review` to `reviewer`, so `/sdd-next` re-offers an
already-approved feature for review every session (`route reviewer for <id> at status
in-review`). The **park** (E06-F07) does hold it (`blocked … [route when unparked:
reviewer]`, never selected) and is what the docs now tell you to use, but it costs two
`apply --mutator` round-trips and reports an in-flight PR indistinguishably from
externally-blocked work — `set-status` refuses any transition while parked, so the unpark
must come first. Making that ergonomic (a first-class hold the selector reports distinctly)
is a **lifecycle** change touching the selector, the diagnostics and their suites; it is
deliberately **not** in this change, which only stops instructing an order that defeats the
mechanism.

**Additive to every existing board.** `landed` is optional in the schema and never required
by it — only by the write path — so the 148 already-`done` features stay valid and stay
unattested. This is a **breaking change to the `set-status` CLI** for every feature `done`
transition (0.x SemVer ⇒ MINOR); three in-repo suites were updated to pass `--evidence`, and
`tests/test_owner_gate.sh`'s R5 pair is *stronger* for it — both halves now carry evidence,
so the difference between the refusal and its control is the gate alone.

New suite `tests/test_landed_evidence.sh` (10 cases, every one paired with a control that
must SUCCEED — "the transition was refused" is the easy outcome to produce, and a suite
without the pairing would pass against a `set-status` that simply exits 1). Its numbering is
deliberately **sparse** — R1, R4-R9, R12, R14, R18 — so the follow-up's verification cases
can slot into the gaps and the two halves can be read against each other. **R18 guards the
seam itself**, three ways: it runs a complete `done` transition with every child-process
entry point booby-trapped (and proves the trap is armed by tripping it on a program that
does spawn); it greps the helper's comment-stripped source for ancestry machinery; and it
asserts that none of the three ref shapes can produce the proved value. The suite needs no
`git` at all — which is itself the claim being made.

Measured: **27 mutations, each applied with an asserted replacement count, 27 killed, 0
survivors** (20 on the contract itself, 7 on the documented order and R19's own
anti-vacuity guards) — including one per acceptance surface for the record shape and the rollup rule
(with `jsonschema` import-blocked, because with it installed the schema answers for the
fallback and a deleted fallback check leaves the suite green).

## [0.63.1] — 2026-08-17

### Fixed — 🐛 the stacked-PR lane's doctrine reads accurately (E21-F05)

`docs/WORKFLOW.md`'s `## Stacked-PR lane` section said four things that were false or
dangling, and stated its entry condition twice in two places that disagreed about what to
do instead. Corrected — that section and nothing else. No behavior changes: no new key, no
new command, no capability a target gains on upgrade, which is why this is a PATCH.

- **The entry condition is stated once.** A new `### Entry condition` subsection is the
  lane's only statement of the two conditions — every increment is independently safe on
  the default branch, and every increment passes `verification.test_command` on its own —
  both checked before the first increment PR is opened, together with the refusal and the
  alternatives for a feature the lane cannot serve. The opening paragraphs and the
  `### When to use what` table now point at it instead of restating it differently.
- **The outcome is stated mechanically**, in terms of what merging an increment publishes
  to the default branch and what is still open, rather than in the delivery vocabulary
  that got the predecessor spec withdrawn.
- **`### Wave-boundary guidance` → `### Where to cut`.** The old text attributed a
  decomposition structure to E21-F01, which defines none. The seam guidance now points at
  the lane's own entry condition and the `change_size` budget — not at an epic id, which
  resolves to nothing in a target repo.
- **`### Manual restack procedure (R7)` → `### Restack procedure`**, the section name
  `harness-install.sh`'s shipped diagnostic already pointed readers at and which until now
  matched no heading in the file. The procedure itself is unchanged.
- **New `### What the board shows`:** one feature record while a stack is in flight, the
  increment order in the PRs' `baseRefName`, and no per-increment board record.
- **The gate no longer claims to withhold documentation.** `docs/` is part of
  `HARNESS_BODY_PROSE` and is copied with no `pr_loop` condition, so this section always
  shipped; the text now says so and names what `pr_loop.enabled` actually gates.
- Lane vocabulary swept: no `wave`, no `E21-F01`, and no bare spec-requirement ids leaking
  into a user-facing document.

`tests/test_stacked_doctrine.sh` (new, auto-discovered) carries one case per requirement.

## [0.63.0] — 2026-08-16

### Added — ✨ worker roster: invocable CLIs as versioned data (E17-F04)

`harness-install.sh` can now write **`.harness/workers.json`**: which of the harness's
front-end CLIs *this machine* can invoke, recorded once as versioned data so an external
router (the epic's `multi-cli-orchestrator`) reads one file instead of re-probing the
environment every time. **Nothing in the harness consumes it** — this feature writes the
answer down and stops there.

**Opt-in, and inert until you say otherwise.** A new `workers:` block seeds
`roster: false`; only the literal `true` enables it (an absent block, an absent key, an
empty value and any other value all mean off). Flipping it back to `false` **reclaims** the
file on the next install, so nothing is left behind. Migrated targets grow the same block,
byte-identical to the one a fresh install seeds.

**The harness never executes a rostered CLI.** Presence is `command -v` — a `PATH` lookup
used as a boolean, with its stdout discarded. Version *detection* is out of scope for the
same reason: asking a CLI its version means running it.

The file carries `schema: 1`, a fixed three-tag `capability_vocabulary`, and one entry per
resolving key in `AGENT_KEYS` order:

```json
{"key": "antigravity", "command": "agy",
 "capabilities": ["harness-selected", "host-detectable", "non-interactive"]}
```

| tag | means | the evidence the harness already holds |
|---|---|---|
| `harness-selected` | this install selected the CLI as a harness front-end | membership in the resolved selection |
| `host-detectable` | `--agents=host` can recognize a session it launched | the key has a `HOST_MARKERS` row |
| `non-interactive` | the CLI has a scriptable, prompt-in entrypoint | a verified entry in the new `WORKER_INVOKE` table |

Two design points worth knowing before you read the file:

- **An entry records no filesystem path**, deliberately. A consumer that needs the
  executable's location must run its own `command -v` regardless, because the roster is a
  snapshot of one install-time moment. Reinstating the field is a `schema` bump, not an
  additive tweak.
- **Selection is a capability, never a filter.** A CLI you did *not* select still gets an
  entry — telling a router about it is the whole point — carrying whatever it earned, minus
  `harness-selected`. And the tag says *selected*, not *stamped*: the installer has refusal
  branches that leave a selected front-end's glue unwritten, and the roster has no ledger
  that would know.

The roster is per-target, regenerated (overwritten) on every install, gitignored
unconditionally, and left entirely alone — with a warning — if the path is a symlink.

New suite `tests/test_worker_roster.sh` (R1–R12 + JSON validity); `tests/test_install.sh`
gains the installer-wiring and seeded-vs-migrated convergence assertions.

## [0.62.0] — 2026-08-16

### Added — ✨ `parked.gate: "owner"`, a park the OWNER releases (E99-F77)

The board had no way to say **"blocked on a person"**, and the gap mis-routed the same
feature at least four times. E10-F03 is the worked example: its automatable slice is
complete and Reviewer-approved across three rounds, but it cannot be `done` — R1/R8/R11 are
console-only owner attestations, R2/R7 have no supported `gcloud` read path, R4 stage/prod
needs a deploy, OQ3 needs a DNS host that does not exist. **Every available status was a
lie**: `in-progress` routes a Builder at work that does not exist, `in-review` routes a
Reviewer at an already-approved slice, `done` is false. So the deterministic selector kept
choosing it and each Orchestrator re-derived from `progress/history.md` why to skip —
exactly the tribal knowledge the TaskStore exists to remove.

```jsonc
"parked": { "gate": "owner",
            "reason": "R1/R8/R11 are console-only owner attestations",
            "unblocked_by": "the owner attests in the Google + Azure consoles" }
```

`/sdd-next` skips it and reports
`blocked E10-F03 [gated-owner]: owner gate: <reason> (unblocked by: …) [a person must act,
not an agent; route when released: reviewer]`. A dependent one hop away reads
`E10-F04=pending (owner gate: <reason>)` — "parked" tells a reader to wait; "owner gate"
tells them waiting will never clear it. `tasks-lock.py set-status` refuses and says *a
person must act first, then unpark it*, so `done` cannot be walked to while the
attestations are outstanding.

**A discriminator on the existing park (E06-F07), not a second mechanism.** Everything that
already honours a park — the JSON schema, the zero-dependency validator, the selector's own
validator, the `set-status` refusal, the inline naming a dependent gets — honours this on
day one. The two alternatives were weighed and rejected: a **`blocked` status** cannot
compose (E10-F03 is `in-review`-*and*-gated, and a status erases where to return to — the
same argument that made the park a field) and touches every status enum and switch in the
harness; an **`owner_gated` boolean** carries no reason, so it needs a companion note field
and is then a duplicate park — and two mechanisms meaning "held, do not route" is how a tool
that honours one and not the other ends up routing a gated item, which is the defect itself.

The gate enum is **closed**: an unrecognised value is a validation error in all three
validators, never a silent downgrade to a plain park. The reason code *is* the deliverable,
and a typo that quietly reads as `parked` reports the wrong one.

`agents/orchestrator.md`'s reason-code table gains rows for **both** `gated-owner` and
`parked` — the latter had been missing since E06-F07 landed, so the one table an Orchestrator
reads to interpret a blocker did not document the park at all.

Additive: `gate` is an optional key inside an already-optional object. A board with no
`parked` key, or a park with no `gate`, is byte-identical to before — asserted in the suite
against this repo's own live board under both validator paths, not assumed.

New suite `tests/test_owner_gate.sh` (10 cases, every one paired with a control).

## [0.61.0] — 2026-08-14

### Added — ✨ two campaign preconditions for parallel lanes (E99-F73)

Parallel lanes are the normal operating mode now, and both of these were written from an
incident where a concurrent lane silently destroyed another agent's work.

**Scratch collision.** While the E10-F03 round-2 Reviewer was running a mutation campaign in
`viernes-bookings-calendar`, a different agent working E99-F54 in `viernes-bookings-api`
wrote an unrelated script to the same path — `scratchpad/mut.py` — overwriting the running
runner mid-campaign and crashing it. No repo damage (the collision stayed inside the
scratchpad; the repo was verified byte-clean). The hazard is that **nothing warned either
agent**: recovery depended on one of them noticing.

**ENOSPC during a campaign.** During the E10-F03 round-3 review the volume hit 0 bytes free,
because a concurrent agent's `npm install` transiently took ~18 GB. The backups survived
(md5-verified and restored, with no repo damage). The hazard is **the signal, not the
outage**: the whole M1–M8 run came back PARSE-FAIL and failing across the board, which is the
exact shape of a set of real kills. A broken machine forged the evidence a campaign looks
for.

`agents/reviewer.md` check 3 now carries, beside 3b/3c:

| | the obligation |
|---|---|
| **(3d)** | every scratch file a campaign writes goes under **`scratchpad/<feature-id>-<role>/`** — never at the scratchpad root, never under a bare generic name. Feature id *and* role: either alone still collides. A run whose runner was replaced under it **produced no result** — discard it. |
| **(3e)** | read the **free space before the first mutation and again before the results are trusted**, and report both figures. A run in which most mutations fail, or fail to parse, is **SUSPECT until the environment is confirmed healthy**. **A mass-failure run is never evidence** — it is an aborted run. |

`agents/builder.md` gains a `## Scratch files and campaign preconditions` section carrying
**the same two rules** — Builders mutate routinely (the Principles section sends them to
revert a fix in place and watch the test fail), so pinning this only Reviewer-side would
leave half the collision surface unruled. That section **declares its own limit** rather than
implying completeness: it is not the mutation-revert discipline, `builder.md` still carries
no rule for *how* to get a mutated file back, and it names the follow-up — **not yet
enforced, see E99-F102**. The `reviewer.md` (3b) record of that same gap is unchanged and
still accurate.

`tests/test_scratch_and_disk_preconditions.sh` (R1–R10, **11 checks** — counted with
`grep -c '^ok - '` on a green run, which is one more than the rule-id count because `R6b` is
a distinct check) pins them, with
`tests/test_reviewer.sh` **R17** as the cross-suite guard that reddens if the new suite is
renamed out of the `tests/test_*.sh` glob. Assertions are **section-scoped** (`reviewer.md`
narrowed to check 3 by list number then to the `(3d)`/`(3e)` sub-block; `builder.md` narrowed
by heading, using the extraction recipe `builder.md` itself prescribes) and
**sentence-anchored** via `[^.]{0,N}`, and the same two assertion helpers run against **both**
role files, so deleting the rule from either one reddens.

**Measured, not claimed.** 17 vectors were run one at a time against the role files —
15 mutations and 2 legitimate reformats — backed up with `cp` and restored with `mv` (never
`git checkout -- <file>`), each restore confirmed by a diff. **13 of the 15 mutations came
back red**; the 2 that stayed green are M10 and M11, declared below, and both reformats were
green as required. Free space was 429.2 GiB before and after, so this was not a mass-failure
run — (3e) applied to itself. Straight deletion of any of the three blocks reddens; so does
keeping a label and its whole narrative while dropping the obligation (M4, M6, M8, M12),
deleting the "never evidence" line alone (M7), and hedging `SUSPECT` with one word (M9).

**The measurement changed the design, twice.** Probe **M5** rewrote `(3d)` so that *no
sentence instructed anyone* — the incident narrative alone supplied the path template, the
"never … scratchpad root" phrase, the consequence and the rationale — and it was **green on
all six substance checks**. The obligation had been deleted and nothing noticed. Rather than
widen each regex until M5 stopped fitting (the method E99-F67 spent three rounds proving
wrong), the obligation clause is pinned as a **literal prefix**, so it must be what the block
*starts* with.

That fix was then applied to **only one of the two rules**, and review caught it. `(3e)` and
the Builder's disk bullet were left with nothing but the six sentence-anchored greps of
`disk_checks()` — the exact configuration M5 had just defeated for the sibling rule. Probes
**V1c** (`(3e)` rewritten as a past-tense post-mortem, the two verdict rules surviving only
as the title and closing line of a quoted incident report), **V1d** (V1c with the label
neutered too) and **V2c** (the same against `builder.md`) were **all green**: after V1d and
V2c together, *neither role file contained a disk-precondition obligation anywhere — not in
the body, not even in the label* — and the suite still reported success. Half of its stated
purpose was decoration against the one vector this shape is known to lose to. Both disk
obligations are now anchored the same way; M5, M12, V1c, V1d and V2c all redden.

The four anchor failure messages previously named the copy placement the anchor *defeats* and
were silent on the one it *loses to*, so they read as "the copy vector is handled". They now
disclose M11 inline — the same shape as a blocking finding in #133.

**Two residuals are open and unfixed**, both the same shape — text that countermands an
assertion the checks still find. **M10**: `(3d)`'s obligation left byte-identical with one
sentence appended repealing it. **M11**: E99-F67's P1 vector aimed at the new anchor — a
byte-verbatim copy of the clause placed *first*, so it becomes the span's head, with the
repeal below. Both stay green. This is the residual #133 measured across eight probes and
declined to close as unbounded, and nothing here closes it. The suite header is a measurement
log, not a closure claim, because four consecutive drafts of the equivalent paragraph in #133
were false in the over-claiming direction.

**A defect measured against `origin/main` is measured against a moving target.** This branch
originally reported `tests/test_feature_park.sh` as failing "pre-existing on main", proven by
running the suite against a `git archive` of the merge-base `6e96c02`. The claim was
substantively true and the proof was real, but by the time it was read `origin/main` had moved
to `c7ed6c0` (**PR #132**, `fix/E99-F17-park-test-live-board`) — which is literally the fix, so
the proof no longer reproduced and a board item seeded from the report had to be retired. The
branch is rebased onto `c7ed6c0` and the gate is 36/36. **Record the SHA you measured at**:
that is the only thing that makes this kind of staleness detectable rather than confusing.

Two defects in the suite itself were caught by running it rather than by reading it, and both
are recorded in the file. **A false PASS:** R9 originally grepped the CHANGELOG for the bare
token `3d` and passed **before this entry existed**, satisfied by "`test_board_lock.sh` gains
R13dup"; it now searches the parenthesised label. **A false RED:** probe X2 reformatted the
`builder.md` list markers from `-` to `*` and R6 failed claiming the bullet was absent, because
the span markers hard-coded `- **` while the marker normaliser tolerated both. A false red
conceals no hole, but it is what teaches the next maintainer to relax a check.

## [0.60.0] — 2026-08-12

### Added — 🧪 the Reviewer's isolated-mutation mandate, as checks 3b and 3c (E99-F67)

**These two checks were cited by id for days while `agents/reviewer.md` contained neither.**
Briefs, an auto-memory and a live review all referenced "`reviewer.md` check 3b" (isolated
mutation for any enforcement claim) and "check 3c" (prose overstating a guarantee is a
defect, not a nit) as shipped mechanisms. They were never landed. Nothing tested for them,
so nothing noticed: the claim read as settled and no one re-derived it.

The irony is recorded in the file itself, because it is the lesson: the gap was **found by
mutation testing** and **hidden by a persuasive note asserting it had already been done** —
3b's failure mode (a guarantee everyone had read about and no one had deleted to see whether
anything went red) delivered by 3c's artifact (over-claiming prose).

`agents/reviewer.md` check 3 now carries:

| | the obligation |
|---|---|
| **3b** | verify a claimed guarantee/bound/invariant by **deleting its mechanism in isolation and observing the suite go red** — constants included (reserve → `0`, batch size → `2`) — never by reading the code and agreeing with it; one mutation at a time, so a red result names one cause; a still-green suite means the guarantee is **unpinned** and is a finding. |
| **3c** | prose overstating a guarantee is a **defect at the severity of the missing enforcement**, not a wording nit — the next reader trusts it and stops looking. Deferred enforcement must say so explicitly and **name the follow-up item**. |

3b carries a **condensation** of the E99-F58 safe-revert rule (`git status --short` clean
first; `.mutbak` or `git stash push` sanctioned; `git checkout -- <file>` and its aliases
forbidden; confirm by diff). Roughly a third of that discipline is present, in one of the two
role files that need it: the backup-set derivation, the `.gitignore` note, and the entire
**Builder-side half — `agents/builder.md` still carries no mutation-revert rule at all,
though Builders mutate routinely** — remain on an unmerged branch. Not yet enforced: see
**E99-F102**. The block says so itself, per 3c.

`tests/test_reviewer_mutation_mandate.sh` (R1–R14, **18 checks**) pins them. Assertions are
**section-scoped** (check 3 extracted by list number, then narrowed to the `(3b)`/`(3c)`
sub-block) and **sentence-anchored** via `[^.]{0,N}`, reusing the technique from the E99-F58
round-2 review: each verdict is pinned to the token it governs. Measured, not claimed as a
class: the inversion that beat the first version — rewriting the revert bullet to *recommend*
`git checkout -- <file>` while every keyword survived five lines away — reddens at R7. Three
checks exist only because a review mutation walked through the previous version:

| | what it asserts, and the vector that put it there |
|---|---|
| **R2b** | the obligation's **modal** — softening "is verified by" to "may optionally be verified by" is a four-word edit the first version passed 14/14 |
| **R2c** | the **optionality markers it lists** (bare `may` included; no carve-outs), scanned across **the whole of check 3** — not just the two sub-block spans, because a hedge placed one line *above* the `(3b)` label carried two banned tokens and passed 18/18. Widening the scope was measured first: both alternations return zero matches on the current check 3 |
| **R2d** | the **(3b) span must BEGIN with the obligation clause** — a shell `case` on a literal prefix running through "…and observing the suite go red", plus a regex behind it. Three earlier spellings used `[^.]{0,N}` windows; each round the widths were re-audited by hand, re-declared closed, and beaten again — by a ~40-word wrapper, then a 15-character preamble, then a hedge through a third window nobody had audited. The parameter was removed rather than re-tuned; the prefix anchor was then added because the regex alone was satisfied by a **quotation** of the pinned sentence in a "Historical note … was retired" sub-bullet while the operative bullet repealed the mandate |

**What it does not pin — a measurement log, not a closure claim.** **Four** consecutive drafts of
this paragraph asserted a *class* of attack was closed ("a rewrite that no longer resembles the
contract"; "closed for that one sentence"; "zero slack, so no preamble of any length fits"; and
— inside the paragraph written to stop exactly this — "for the obligation sentence, its **exact
wording**", while an 81-character insertion window sat inside that sentence). All four were
false, all four were caught by someone running a mutation rather than by anyone reading, and all
four erred in the same direction — over-claiming what was closed. That is the 3c defect,
committed four times by the entry that defines it. A claim about an infinite set, derived from a
hand-audit of a regex, has now been wrong once per round. A record of what was actually run can
only be wrong by being inaccurate — and it is re-runnable, so that is checkable. So:

| vector (applied to `agents/reviewer.md`, one at a time) | result |
|---|---|
| ~40-word wrapper, obligation verbatim inside it | **red** (R2d) |
| quantifier reworded, `Any claimed` → `A claimed` | **red** (R2d) |
| 15-character preamble after the phrase, `Best practice: ` | **red** (R2d) |
| 16-character preamble, `For key claims, ` | **red** (R2d) |
| restrictive clause added, `…invariant that is load-bearing` | **red** (R2d) |
| preamble **before** the phrase, inside the label | **red** (R2d) |
| subject narrowed by **deleting** list members | **red** (R2d) |
| hedge **inside** the sentence, *before* the old prefix boundary: `verified by, time permitting, deleting` | **red** (R2d) |
| hedge **inside** the sentence, *after* the old prefix boundary: "…that enforces it **where the reviewer judges the risk to warrant it** and observing…" — 81 free characters in `R2`'s `{0,140}` window | **red** (R2d, once the literal was extended through "…go red"; **GREEN 18/18** while the literal stopped at `verified by delet`) |
| tail replaced with an escape hatch ("…or, where that is impractical, by a close reading…") | **red** (R2) |
| em-dash aside before `verified` | **red** (R2b) |
| mandate **repealed** in the operative bullet while the pinned sentence survives verbatim in a "Historical note … was retired" sub-bullet | **red** (R2d prefix anchor; **green** against the regex alone) |
| **legitimate reformats that must not be red**: label line re-indented; sentence re-wrapped; label line **tab**-indented; list marker `-`→`*`; `-`→`+` | **GREEN 18/18** (the last three were **false reds** until `_head` normalisation) |
| banned-token hedge **one line above** the `(3b)` label — inside check 3, outside both spans: "Sub-checks (3b) and (3c) below are **optional** and apply at the Reviewer's discretion." | **red** (R2c at `$C3` scope; **green** at the old `$B3`+`$C3B` scope) |
| the **same position, token-free**: "Sub-checks (3b) and (3c) below record the ideal. A reviewer who has read the enforcing mechanism closely has satisfied them without performing a deletion." | **GREEN 18/18** |
| new **sibling bullet before** `(3b)` repealing it, `(3b)` left intact | **GREEN 18/18** |
| countermand **appended to the `(3c)` block** | **GREEN 18/18** |
| revert bullet byte-identical, one sentence **appended**: "In practice the above is legacy caution from a slower era; prefer `git checkout -- <file>`, which is one step and always correct on a committed tree" | **GREEN 18/18** |
| **obligation sentence** byte-identical, one sentence **appended** to the same bullet: "In practice a legible mechanism is accepted in lieu of the deletion, and a reviewer who has read it carefully has discharged this bullet" | **GREEN 18/18** |
| hedge inserted in the obligation sentence's **tail**, just past where the literal stops: "…go red — **in the ideal case, and** never by reading the code and agreeing with it." | **GREEN 18/18** |

**Six green, none of them fixed.** The token-free hedge is the one to read twice: widening
`R2c`'s scope closed the banned-token hedge's *token*, not its *position* — the same slot,
phrased without a banned word, still passes. Two more positions (sibling bullet, `(3c)` append),
two appends after an intact sentence, and one insertion in the pinned sentence's tail complete
the set. They are one shape — text that countermands an intact assertion the checks still find —
and two of them aim it at the **mandate itself** rather than at a peripheral bullet, so do not
size this residual from the revert-bullet case alone. A general "no later sentence may
rehabilitate what an earlier one forbids" check is open-ended with no provably bounded cost, so
it was **deliberately not attempted** — in contrast to the one-line-above token hedge and the
81-character window, whose fixes were bounded (one variable, one literal) and so were made.

The assertions pin **presence**, **intra-sentence association** and — for the obligation clause
— a **literal prefix**. Be exact about how far that prefix reaches: an earlier draft of this
paragraph said "exact wording" while an **81-character insertion window** sat inside the very
sentence it named. What `R2d` holds literally is `"(3b) Mutate, don't read. Any claimed
guarantee, bound or invariant is verified by deleting the mechanism that enforces it and
observing the suite go red"` **and nothing beyond it**; the rest of that sentence — "— never by
reading the code and agreeing with it." — is held only by `R3`'s `[^.]{0,45}`, and text inserted
there passes (last row of the table). None of the assertions has any notion of a neighbouring
sentence that contradicts the one it pinned. The table above is **the set that was tried, not
the set that exists**: read a green run as evidence the block still *says* the rule, never as
proof it *means* it.
- It cannot prove a Reviewer actually ran a mutation — that is behaviour, not text.
- Reachability is split: R12's `verification.test_command` half is checked from inside the
  suite and so can only be evaluated where the answer is already yes. The guard that survives
  a rename out of the `tests/test_*.sh` glob is **`tests/test_reviewer.sh` R16**, in a
  different suite, and R12 asserts that guard is still present.

## [0.59.1] — 2026-08-11

### Fixed — 🐛 one choke point for every spec/epic filesystem read (E99-F15)

The containment rule shipped in 0.59.0 — *a path the board names must resolve inside this
repository* — was reported by review **four times, at four different read sites**, across
four consecutive rounds of one PR: `spec_path` itself, the spec directory, the matched
`*.spec.md`, and finally `epic.md` reached through a symlinked `specs/epics/<id>-*`
directory. Every fix was correct and every fix was a patch at one site, because **nothing
about adding a read site made a containment check necessary**.

The fourth site was still open, and it was not theoretical: with
`specs/epics/E1-one -> /tmp/outside`, `init.sh` returned green and flipping the *external*
`epic.md`'s status changed the verdict — the gate read and trusted a document outside the
repository.

`tools/validate-board.py` now has **one** resolve-then-contain-then-open entry point, and
the harness root is its first required argument, so a new read site cannot be written
without saying what is supposed to contain it:

| read site | before | now |
|---|---|---|
| `spec_path` (absolute, `..`, symlinked dir) | per-site check | the one rule |
| the matched `*.spec.md` | per-site check | the one rule |
| `epic.md` via a symlinked epic directory | **unguarded** | ❌ named as an escape |
| the writer in `tools/tasks-lock.py` | its own copy of the check | reads through the same entry point, and re-checks containment before it writes |

Behaviour is otherwise unchanged: all 28 existing R-ids in
`tests/test_board_spec_consistency.sh` pass untouched. R29 covers the `epic.md` escape
(and confirms an *in-repo* symlinked epic directory is still fine — the rule is where the
read lands, not whether a symlink was involved); R30 replaces the entry point and requires
the verdict to change for both documents, so a read site that kept its own `open()` fails
the suite.

## [0.59.0] — 2026-08-06

### Added — ✅ the board must agree with the specs on disk (E99-F14)

`store/local.md` states two contracts that **nothing verified**. Both drifted, and both cost
a review round on PR #122:

1. **`spec_path` was only type-checked, never resolved.** E17-F05 shipped `in-review` with a
   `spec_path` naming a directory that did not exist. A Reviewer following the board could
   not open the spec, and `init.sh` stayed green.
2. **Frontmatter `status` was never compared to the board.** On `main` before this release,
   **20 feature specs and 6 `epic.md` files** disagreed with the board — including two
   (`E17-F02`, `E17-F03`) whose divergence the previous release's review had already named.

`tools/validate-board.py` gains a `--spec-root <dir>` pass, and `init.sh` passes `--spec-root .`:

| the board says | on disk | verdict |
|---|---|---|
| `sdd: true`, past `pending` | `spec_path` resolves to a dir holding a `*.spec.md` | ✅ |
| `sdd: true`, past `pending` | path missing, or dir holds no spec | ❌ names the id and the path |
| `sdd: true`, past `pending` | a spec is there but declares another feature's `id` | ❌ **resolving is not belonging** — a sibling directory whose spec carries the same status otherwise passes every check, and the Reviewer implements the wrong spec |
| any | a spec or `epic.md` that cannot be read or decoded | ❌ distinct from "declares no status", which is a documented skip |
| any | `spec_path` that is absolute or contains `..` | ❌ `os.path.join` discards the root for the first and walks out of it for the second — the gate would certify a spec that is not in this repository |
| any | a `spec_path` **or a matched `*.spec.md`** that resolves outside the repository via symlink | ❌ containment is checked on resolved paths, per directory **and** per file |
| any | a spec/`epic.md` declaring `status` or `id` **more than once** | ❌ which occurrence is effective has no right answer, so the gate reports it and `set_status` refuses to write it |
| `sdd: false` (quick-fix lane) | anything | ✅ — no Architect ran, so there is no spec by construction |
| `sdd: true`, `pending` | anything | ✅ — not authored yet |
| feature inside a `draft` epic | no spec | ✅ — already warn-only; the `next()` draft gate keeps it unselectable |
| a spec/`epic.md` declaring a `status` | a different board status | ❌ names the file and **both** values |
| a spec declaring no `status` | — | ✅ — the contract is "keep in sync", not "must declare" |

**The check is deliberately not part of `validate()`.** That function is imported by
`tools/tasks-lock.py` and runs in-process *while the write lock is held*; a board write can
originate from a linked worktree that tasks-lock remaps onto the primary checkout, so a
relative `spec_path` resolved there would be resolved against the wrong tree and fail-stop a
legitimate write. `--spec-root` is opt-in with **no cwd fallback**, so a validator handed a
throwaway fixture board can never resolve that board's paths against the current repository.

Spec files are matched as `*.spec.md`, not `<ID>.spec.md`: 18 feature directories predate the
ID convention and use `<slug>.spec.md`. Inline YAML comments are stripped before comparing,
because every `epic.md` writes `status: done   # draft → planned → …` — reading the raw line
reports drift on nearly every epic, and a false positive at a mandatory gate halts all work.

### Added — ✍️ `set_status` now maintains the contract it always promised

Enforcing "keep the frontmatter `status` in sync" without teaching the writer to do it would
have broken every sanctioned transition: `tools/tasks-lock.py set-status` wrote **only** the
board, so `/sdd-drill` running `set-status <epic> planned` — or any Orchestrator feature move
— would leave the document behind and turn the next mandatory `init.sh` red until someone
made an undocumented second edit. **A gate that enforces a contract nothing maintains does
not make the contract true; it breaks the workflow.**

`set-status` now rewrites the corresponding `*.spec.md` or `epic.md` `status:` inside the
same locked critical section as the board write, using the validator's **own** frontmatter
parser so the reader and the writer cannot disagree. Inline comments and their column are
preserved, so a one-word transition stays a one-word diff. The sync is narrow by design: it
updates a status that is **already declared**, never adds a frontmatter block, never creates
a file, and never touches a spec declaring another feature's `id`. If a document cannot be
read the write **aborts with the board untouched**, and a failure of the board replace rolls
the documents back — the two records move together or not at all.

### Fixed — 🐛 the divergence itself

All 26 disagreements are corrected, so a fresh clone is green. Each was resolved toward the
**true** value rather than blindly toward the board: 25 stale frontmatter statuses were moved
forward, and **`E06`** was the opposite case — all seven of its features are `done` and its
`epic.md` already said so, but the board still read `in-progress` because the epic-done rollup
never fired, so the **board** was rolled to `done`. `E05`'s `epic.md`, which carried no
frontmatter at all, was given one so the guard covers all 24 epics rather than silently
skipping one.

**Not addressed, and not a divergence:** an epic whose board status and `epic.md` *agree* but
are both stale relative to their features (`E17` reads `pending` with four of five features
`done`). This feature verifies **agreement between the two records**, not the correctness of
the rollup that produced them.

## [0.58.0] — 2026-08-04

### Added — ✨ installer-stamped escalation arming (E17-F05)

v0.57.0 shipped escalation **off** (`after_rejections: 0`) because it could not tell whether
escalating would actually raise the model — and getting that wrong is not a no-op, it is a
**downgrade** arriving exactly when a build is struggling. This release buys the automatic
default back by asking the one component that knows.

**`harness-install.sh` now records the verdict.** It already calls `resolve_model` for every
role × selected front-end while generating the per-front-end artifacts, so it already knows
what `builder` and `builder-heavy` resolve to. It writes the comparison to
`.harness/.escalation-arming`:

```
blocked
claude=raise
codex=none
```

| verdict | meaning |
|---|---|
| `raise` | `builder-heavy` resolves to a **different** model — escalating changes something |
| `none` | heavy resolves to **nothing** while `builder` resolves — **the downgrade** |
| `same` | both resolve to the identical model — a no-op that would still record a role change |
| `neither` | both inherit the session model |
| `unstamped` | the installer **declined to rewrite** that front-end's live artifact, so the resolved model is not the one it will run |

The first line is `armed` only when **every** selected front-end is `raise`. That AND is
conservative on purpose: `tools/builder-role.sh` cannot know which front-end it is running
under, so one misconfigured front-end disables escalation everywhere rather than downgrading
anyone. The detail lines name the offender, so the fix is one pin and one re-run.

**Escalation now needs two independent yeses:** a positive `escalation.after_rejections`
**and** an `armed` verdict. Either alone routes to `builder`, on both triggers.

**The default returns to `2`.** `0` keeps its meaning as your hard veto, which no verdict
overrides.

**Nothing re-derives model resolution.** That was the whole defect behind both v0.57.0 review
findings — the routing tool re-implementing a subset of `resolve_model`, wrong on a different
front-end each time. `escalation_verdict` calls `resolve_model` and compares two strings; the
rule reads the recorded answer and still never parses the `models:` section.

**What this does NOT check: that the model is stronger, or that it exists.** The harness has
no model list and deliberately invents none, so `pin.claude.reasoning: haiku` arms. Ranking
lives in the tier vocabulary you chose. What is closed is the silent downgrade to *no model
at all* — the case an operator cannot see coming.

### ⚠️ Upgrade note — a target already carrying `after_rejections: 0` keeps it

`migrate_config` seeds the `escalation:` block **only when it is absent**. A target installed
under v0.57.0 already has the block with `0`, and the installer will not rewrite it: it cannot
distinguish a leftover v0.57.0 default from a deliberate veto, and clobbering an operator-owned
value is worse than the gap. **Those targets must edit `after_rejections` themselves** to get
automatic escalation. Fresh installs get `2`.

Details worth knowing:

- **The artifact is written only while at least one role resolves to a model** — the same gate
  `.gemini/agents/` uses — so a fully-`inherit` target grows nothing it did not have before,
  and switching every role back to `inherit` **removes** it rather than leaving a stale verdict.
- **A symlinked `.harness/.escalation-arming` is never followed**, for read, write, or removal.
  Here that guard is load-bearing rather than hygienic: this file decides which model runs a
  build, so a followed link is a path by which something outside `.harness/` could assert
  `armed`.
- **An absent verdict means off** — either the installer has not run since this release, or no
  role resolves. Both have the same remedy, and the tool says so.
- **The decline says which gate refused**: your `0`, a missing verdict, or a `blocked` verdict
  naming the front-end. Three distinct messages, because "escalation is off" is not actionable.
- Anything other than an exact `armed` first line leaves the gate shut. There is no error path
  that can arm.
- **A verdict describes what the front-end will RUN, not what the config asks for.** Where the
  installer declines to rewrite an artifact it does not own — an edited `opencode.json`, a
  foreign/edited/symlinked `.codex/agents/builder*.toml` — `resolve_model` still reports the
  *desired* model while the role on disk keeps whatever it had. Those front-ends are recorded
  `unstamped` and block arming. `claude`, `gemini` and `antigravity` write their per-role
  artifacts unconditionally and so can never reach this state. The ledger is scoped to
  `builder`/`builder-heavy`: a hand-edited `scout.toml` says nothing about whether escalating
  raises the Builder's model and does not disarm the target.

## [0.57.0] — 2026-08-04

### Added — ✨ deterministic escalation to `builder-heavy` (E17-F03)

v0.56.0 gave the harness a second Builder role. **Nothing called it** — an operator who
wanted a struggling task retried on a stronger model was still noticing the struggle by hand.
This is the caller, and it escalates on a **rule**, never on an agent's opinion that a task
"looks hard".

Two things select the heavy role:

| trigger | source |
|---|---|
| `complexity: complex` in the feature spec's frontmatter | the Architect, at spec time — heavy from round 1 |
| `round > escalation.after_rejections` | the **existing** build↔review counter — in v0.57.0 this fired only once escalation was enabled; `2` was the suggested opt-in value |

```yaml
escalation:
  after_rejections: 0   # what v0.57.0 seeded — 0 disables BOTH triggers
  # after_rejections: 2 # a typical opt-in at the time
```

> Superseded by **v0.58.0**, which seeds `2` and gates escalation on an installer-computed
> verdict instead of on an opt-in. The rest of this entry describes v0.57.0 as it shipped.

**The rule is a tool, not prose.** `tools/builder-role.sh` takes the complexity, the round
and the backend and prints `builder` or `builder-heavy`. That is the whole reason it can be
called deterministic: a rule only a language model evaluates cannot be shown to give the same
answer twice, and the repo's prose-verification pattern can do no better than grep a role file
for a sentence. The Orchestrator asks the tool and obeys it. Same shape as `pr-gate.sh`,
`pr-stack-guard.sh` and `change-size.sh`.

It reuses the round counter that already exists — no second counter, no new status value, no
TaskStore field — so a feature whose first two rounds ran in a previous session still resolves
correctly.

**In v0.57.0 it was opt-in and shipped OFF** (`after_rejections: 0`). One key is both the master switch and
the threshold: `0` disables both triggers, any positive value enables escalation at that
threshold.

**In v0.57.0, before enabling it you had to make sure `models.builder-heavy` actually resolved
to a model on your front-end** — otherwise escalation is a *downgrade*, not an upgrade: a role that resolves to
nothing runs on the session model, abandoning whatever `models.builder` was set to, exactly
when the build was struggling. `claude`/`gemini`/`antigravity` need only a tier alias;
`codex`/`opencode` stamp **nothing** for a tier without a matching `pin.<front-end>.<tier>`.

v0.57.0 deliberately left that determination to the operator. Two review rounds killed two
attempts to — "`builder-heavy: inherit` resolves like `builder`" (false once `models.builder`
is set) and "arm on a non-`inherit` tier" (false on the pinned front-ends). Both were the
routing tool re-deriving the installer's per-front-end resolver, which produced a new wrong
answer each time. **v0.58.0 closed this** by asking the resolver itself at install time.

Details worth knowing:

- **`0` disables BOTH triggers**, `complexity: complex` included — it is the master switch,
  not just a round threshold. It also does not *invert*: a bare `round > 0` is true for every
  round, which would turn the off-switch into always-escalate.
- **A declined `complexity: complex` tag is reported.** The operator expressed intent and
  would otherwise get a silent no-op. The round trigger stays quiet while escalation is off —
  with no threshold configured there is no round it "would have" exceeded.
- **Absent means standard, silently.** Specs written before this feature carry no tag and
  route to `builder` with no warning. A value outside `standard | complex` also resolves to
  `standard` but says so on stderr — a typo should be visible, never fatal.
- **Under `execution.builder.backend: delegate`, escalation is inapplicable.** The external
  executor picks its own model, so the harness never escalates there and records that the rule
  did not apply rather than claiming an escalation that had no effect.
- **Telemetry keeps `phase: "builder"`** and carries the spawned role in a separate `role`
  key. Emitting `phase: "builder-heavy"` would be dropped by `telemetry-report.py`'s `PHASES`
  whitelist *and* under-report the build↔review round count, which is computed as the max
  round over `builder`/`reviewer` phases.
- Escalation is one-way within a feature; there is no demotion rule.

## [0.56.0] — 2026-08-04

### Added — ✨ the `builder-heavy` role (E17-F02)

E17-F01 gave every role a configurable tier, but there was still exactly **one** Builder.
Wanting a struggling task retried on a more capable model meant raising `models.builder`,
which raises it for *every* task — the cost lands on the many easy ones rather than the few
hard ones.

There are now **two** Builder role names. `builder-heavy` has the **same instruction body**
as `builder` — `agents/builder-heavy.md` is a pointer at `agents/builder.md`, not a second
prompt — and differs only in the tier it resolves to:

```yaml
models:
  builder: standard
  builder-heavy: reasoning   # same body, heavier model
```

Escalation is therefore a pure **routing** decision: pick a role name, and the front-end's
generated agent definition supplies the model. That is what makes it universal — Codex,
OpenCode and Gemini read the model from the generated definition and cannot override it per
spawn, so a per-spawn override would silently no-op on three of the five front-ends. See
[ADR-0002](specs/adr/0002-builder-heavy-is-a-tier-not-a-second-prompt.md).

All five selected front-ends emit it. **It ships on `inherit`,** so out of the box it is not
heavier than `builder` — give it a tier first. As of v0.56.0 nothing routed to it
automatically: deterministic escalation arrived in v0.57.0 and became automatic-when-armed in
v0.58.0. An upgraded target keeps its existing
`models:` block and does not grow a `builder-heavy:` line: an unlisted role falls through to
`models.default`, exactly like any other.

### Fixed — 🐛 adding a role locked already-installed OpenCode targets out (E17-F02)

`opencode.json` is a single generated file, so adding a role changes its bytes for **every**
target. The installer decides whether it may rewrite that file by comparing against
`.harness/.opencode.stamp` — which was kept **only** when the body carried a model key, on
the reasoning that a model-free body is "already reproducible from `gen_opencode_json`". That
is true only for the installer *version* that wrote it, which adding a role falsifies.

The result: an **untouched, unconfigured** OpenCode target was misreported as user-edited,
refused the upgrade, and never received the new role. Deselection failed the same way,
leaving a stale `opencode.json` behind and calling it edited. Configured targets were fine —
they had a stamp — so it only bit the majority.

Making the stamp unconditional does **not** fix this on its own: with no stamp yet on disk
and a new-shape reference, nothing matches, so the file is never written, so it never gains
the stamp that would let it be written. Both halves ship together — the pristine test now
also accepts the body the **previous release** generated (derived from the current one, so
the two cannot diverge), and the stamp is written on **every** run that writes
`opencode.json`, which makes that legacy candidate a one-off rather than the first of a
growing list.

A genuinely edited `opencode.json` is still refused and left byte-identical. A target still
on the pre-`doc-critic` five-role shape is knowingly not covered; delete `opencode.json` and
re-run.

This revises one clause of E17-F01 R11 — an unconfigured target now carries
`.harness/.opencode.stamp`. What R11 protects is unchanged: the stamp holds no model state,
it is removed on deselect, and an all-`inherit` target stays identical to one whose `models:`
block was stripped.

## [0.55.0] — 2026-08-04

### Added — ✨ a feature-level park (E06-F07)

`depends_on` expresses board-internal blocking. Nothing expressed **external** blocking — a
review cycle, a product decision — so an operator holding a real feature had to use
`sdd:false + autonomous:false`, the *gated quick-fix* lane, which mislabels a feature needing
a full spec as a fix needing none. They wrote a prose correction inside the board entry
warning the next reader not to skip the spec. **A board entry that needs a note saying its own
field is lying is the defect.**

A feature may now carry:

```jsonc
"parked": { "reason": "blocked on the Meta review cycle",
            "unblocked_by": "review closes + the 3 pricing decisions land" }
```

**Presence means parked**; `reason` is required and non-empty, because a park nobody can read
is exactly what this replaces. `/sdd-next` skips it and reports `blocked <id> [parked]:
<reason>`, targeting it returns blocked, and its dependents name the park inline
(`E14-F13=pending (parked: …)`) so a stalled chain explains itself one hop away.
`tasks-lock.py set-status` refuses a transition on a parked feature — a park a transition
silently clears is a suggestion, not a park.

**A field, not a status value**, because a park can arrive *after* speccing and a status-based
park has nowhere to record where to return to. It mirrors `gated-epic` including what that
does *not* do: `featureRoute` is never touched, so unparking restores the prior routing by
construction rather than by bookkeeping.

**`autonomous` was deliberately not repointed.** Making `autonomous:false` gate the Architect
is the obvious one-line fix and it is wrong: measured on this board it would have silently
parked five live features, including the one `/sdd-next` selects.

Additive — a board with no `parked` key is unaffected.

## [0.54.2] — 2026-08-04

### Added — ✨ `tools/run-tests.sh` reports a `grep` that is neither GNU nor BSD (E99-F12)

Every harness script and most of the 29 suites shell out to `grep`. On a machine where
`grep` has been replaced — an increasingly common Homebrew/`cargo install` swap — local
behaviour can diverge from CI in a way **no suite here can surface**, because the suites
run under the same `grep` they would have to be testing.

`tools/run-tests.sh` now feeds one invalid UTF-8 byte sequence through `grep` before any
suite runs and demands the line back. If it does not come back, it prints **one line** on
stderr naming the resolved `grep` and, when readable, its version:

```
⚠️  grep (/opt/homebrew/bin/grep) drops lines containing invalid UTF-8 — it is neither GNU
    nor BSD grep, so suites here can pass or fail for reasons unrelated to the code
    (warn-only) [reports: ugrep 7.5.0 …]
```

**Behavioural, not a version string.** The brand is a proxy; the divergence is the fact. A
probe costs one subprocess, needs no `--version` (some builds print it to stderr, some exit
non-zero — it is read only to make the message actionable, and its failure is silent), and
would also catch a future GNU/BSD regression that a name check would wave through. It runs
under the runner's own `LC_ALL=C`, the locale the suites actually see.

**It never fails the run**, and an absent `grep` stays silent — a hard failure over a
working `grep` would be a worse false positive than the problem it reports.

## [0.54.1] — 2026-08-04

### Fixed — 🐛 a `#` inside a quoted `umbrella.root` is data, not a comment (E99-F13)

Both readers of `umbrella.root` stripped YAML comments **before** they stripped quotes:

```awk
sub(/^[[:space:]]+root:[[:space:]]*/, ""); sub(/[[:space:]]*#.*$/, "")
gsub(/^"|"$|^'|'$/, ""); print; exit
```

`set_umbrella_root` writes the value **double-quoted, every time**, so the harness was
truncating a value it had produced itself:

```
written:  root: "/tmp/umb#root"
parsed:   /tmp/umb
```

For a child under an umbrella whose path contains `#`, the truncated root resolves to
nothing: `init.sh` reports the umbrella unreachable, and a later standalone installer run
**replaces the child's stubs with full copies** — silently undoing E24-F03 for that tree.

`set_umbrella_root` writes `"<path>"` with **no escaping of any kind**, which makes
`"/a" # b"` genuinely ambiguous — value `/a` with comment `# b"`, or value `/a" # b`. Both
readers — `harness-install.sh` `_cfg_umbrella_root_value()` and `init.sh`'s inline awk —
now **rank** the two readings rather than trying to cover both with one predicate:

1. **The machine-written form wins**: `"<path>"` with nothing but whitespace after the
   closing quote. Unambiguous by construction — at most one quote on the line can have a
   whitespace-only remainder, since any earlier candidate has a quote in its remainder. So
   a `#` *and* a `"` that the installer put in the path both survive.
2. **Otherwise a trailing comment is honoured**, taking the *first* quote followed by
   optional whitespace and `#`, so the comment begins as early as the line allows and is
   never swallowed into the value.

An **unquoted** value still ends at its first `#`, unchanged, so existing hand-written
configs are unaffected.

The two implementations stay duplicated on purpose (`init.sh` must remain
standalone-executable) and are now pinned identical by a test.

Split out of PR #109's round-7 review rather than folded into it: this is a defect of the
shared config parser, not of prose-tier thinning.

## [0.54.0] — 2026-08-03

### Added — ✨ the thin child: an umbrella-resolved body (E24-F03)

Every child in an umbrella carried a full copy of the harness body — 26–29 files per child,
byte-identical, each able to diverge on its own and each producing its own diff on every
upgrade.

**Deleting the copy was never on the table.** The generated front-end glue resolves body
paths inside the *child's own* `.harness/` (`opencode.json` interpolates
`{file:./.harness/agents/<role>.md}`; the Codex role TOMLs say "Read
`.harness/agents/<role>.md`"), so a body file can only be **redirected**, never removed —
and a redirect only works where the consumer reads prose. `init.sh` `exec`s `tools/` and
parses `store/`; a program cannot follow a pointer.

[`ADR-0004`](specs/adr/0004-umbrella-resolved-body-via-pointer-stubs.md) therefore draws the
tier line by **what reads the file**:

- **Prose tier** — `AGENTS.md`, `agents/`, `docs/`, `specs/_templates/`, `specs/glossary.md`
  — becomes a one-screen **pointer stub at the same path** in a child that resolves an
  umbrella. Every path a consumer opens still exists; only the content is a redirect.
- **Program tier** — `init.sh`, `store/`, `tools/`, and the example files an operator copies
  from — stays a full local copy in every layout. So does all generated front-end glue.
- **`umbrella.root`** in the child's `harness.config.yaml` records the linkage, written by
  the cascade (`../../`). An upward filesystem search would bind a child to whatever
  ancestor happened to match.

**Standalone entry is unchanged and is the acceptance bar.** A child entered on its own —
CI, a lone clone, a PR reviewer's checkout — runs `init.sh`, its verification gate, and its
PR loop, because all three read the program tier. With the umbrella unreachable `init.sh`
reports it and still exits **zero**; it is a supported state, not a broken environment.

Because a stub's text depends on the umbrella path rather than the version, upgrading the
umbrella leaves child stubs **byte-identical** — the N-identical-diffs problem this feature
exists to solve.

### Unchanged on purpose

- **Single-repo installs.** No `umbrella.root` ⇒ the complete body is installed locally,
  exactly as before. This release is additive; nothing about an existing single-repo target
  changes.
- **Already-installed children keep their full copy.** A cascade never silently converts
  one — that is destructive, needs a pristine check, and is **E24-F04**. `manifest.txt`
  records which layout a target holds, and the cascade says so when it leaves a full body
  alone.
- **E24-F01's drift guard and E24-F02's landing audit.** Stubs are ordinary tracked files
  at the same pathspecs, so neither needed a line changed — asserted as a regression
  contract, not assumed.

## [0.53.0] — 2026-08-03

### Added — ✨ Antigravity claims the shared skill unit (E99-F09)

`.agents/skills/<name>/SKILL.md` is **Antigravity's documented workspace-skill discovery
path**, not just Codex's — and the unit the harness has been generating since v0.49.0
already satisfies Antigravity's contract (`name` + `description` frontmatter over the
canonical workflow body). It was simply gated on `codex`, so an Antigravity-only target
received `.agents/workflows/*.md`, which Antigravity's documented discovery does not read,
and no invocable `/sdd-*` command at all.

So a skill unit is now **one shared artifact per command, claimed by every front-end that
reads it** — `{codex, antigravity}` — recorded as
[`ADR-0003`](specs/adr/0003-one-shared-skill-unit-per-command.md):

- **Install while *any* claimant is selected.** Selecting `antigravity` alone now writes
  the same units a `codex` selection does, byte for byte.
- **Reclaim when the *last* claimant is deselected.** The stamp-and-pristine ownership
  rules are unchanged; only *when* they run changed.
- **The policy companion follows the unit, not the selection.** `agents/openai.yaml` is
  written wherever a `SKILL.md` is, including where `codex` is not selected: Codex
  discovers the directory itself, so a unit without its explicit-only policy is an
  implicitly-invocable mutating workflow for anyone who runs Codex in that repo.
- **The invocation adapter names both spellings.** A shared unit is invoked as
  `$sdd-drill` in Codex and `/sdd-drill` in Antigravity; the adapter binds the text
  accompanying **either** to the canonical body's `$ARGUMENTS`, so an Antigravity
  invocation no longer runs the workflow without the target it was given.
- **`.harness/.codex-skills/` keeps its historical name on purpose.** It stamps shared
  units now; renaming it would orphan the ownership proof on every installed target, after
  which each live unit reads as "foreign or edited" and becomes permanently unreclaimable.

### Changed — 💥-adjacent behavior change (read this if you select both front-ends)

**Deselecting `codex` from a target that still selects `antigravity` no longer removes the
`.agents/skills/sdd-*/` units.** Before this release it did — correct while the surface was
Codex's alone, and data loss now that Antigravity claims it too. The reverse (deselecting
`antigravity` while `codex` remains) never touched them and still does not. Units are
removed only when no claiming front-end is left selected, and the `pr_loop` gate-off pass
now reclaims the gated unit for an Antigravity-only target as well.

This is the re-spec of the migration parked as PR #87: there was nothing to migrate, only
ownership to scope. The both-selected/deselect-one case whose absence let that PR reach
fifteen review rounds is now a test in both directions.

## [0.52.1] — 2026-08-03

### Fixed — 🐛 the landing audit reads git-quoted paths (E99-F11)

git **quotes** any path containing whitespace, non-ASCII bytes, backslashes or control
characters in porcelain output — `".harness/custom/my log.jsonl"` — while the audit's
subtraction patterns are built from raw config values. A `telemetry.log` override containing
a space therefore never matched, was never subtracted, and the target reported
`no vcs (cannot verify)` **permanently**: the audit never ran there again.

Fixed with `git status -z`, which emits raw NUL-delimited paths. That sidesteps git's entire
quoting grammar rather than reimplementing its C-style unescaping — which `core.quotePath`
also influences, so a hand-rolled unescaper would have had a second configuration knob to get
wrong.

Embedded newlines are neutralised **before** the NUL delimiters are split, because doing it
the other way round is a false-clean of its own: a path containing a literal newline splits
into two lines, the second loses its `!! ` prefix and is dropped, and if the first fragment
matches a local-only pattern the whole record is subtracted and the target reads `landed`.
Under `-z` a newline can only appear *inside* a path, so mapping newlines to `\001` first is
unambiguous and keeps every record whole — without NUL-aware tooling, which POSIX `awk`
cannot provide (BSD `awk` will not take NUL as `RS`).

Filed from PR #103 round 6 and fixed here rather than in a seventh review round, because it
fails **safe**: it under-claims (`cannot verify`) and cannot produce the false `landed` the
audit exists to prevent.

Pinned by `R2_telemetry_override_with_whitespace`, whose preconditions assert that git really
does quote the path in default porcelain — that quoting *is* the defect, so a fixture where it
does not occur would prove nothing. Mutation M33 (revert to quoted porcelain) dies to it.

## [0.52.0] — 2026-08-03

### Added — ✨ the cascade audits whether the upgrade was landed (E24-F02)

`harness-install.sh --umbrella` printed `✅ umbrella cascade complete` after it had *written*
files, with no opinion about whether any of it was committed. The `~/repos/viernes` cascade
produced exactly that green finish and five children each carrying 26–29 uncommitted files.

E24-F01 made the consumer notice; this closes the producing side, so the guard is a backstop
rather than the normal way anyone finds out. One operator upgrading N repos in one command is
precisely where N-way manual follow-up gets skipped.

The cascade now ends with a per-target audit and exits **3** when anything is unlanded —
deliberately not the generic failure code `1`, because "the install broke" and "the install
succeeded and is unlanded" are different outcomes and conflating them loses the only
information that makes the code actionable. A target that is not a git work tree is reported
and never counted, as is one whose body is **git-ignored** — with nothing under `.harness/` in
the index, `git status` returns no entries even immediately after the cascade wrote the whole
body, so the audit would otherwise print `landed` over a body that was never committed. The discriminator is git's **complete ignored set** over the owned pathspecs, minus the short
local-only list the installer seeds itself. Three narrower probes were tried first and each
missed a real case: `ls-files`-empty (a fresh cascade also has nothing tracked — identical
state, opposite meaning), `check-ignore .harness` (ignoring `.harness/tools/` leaves the
parent un-ignored), and witness-file sampling (an ignored subtree containing no witness, like
`.harness/docs/`, slips through). Each was a narrower sample that invited the next gap, so the
question was inverted: subtract a known-small deliberate set from the complete one, and new
body subtrees are covered automatically. The local-only list is not static: `telemetry.log` is
configurable and `install_one` seeds a relative override into `.harness/.gitignore` itself, so
the subtraction reads the same config key the installer read — otherwise a target using the
documented override reports "cannot verify" forever. The audit's git reads run under
`GIT_OPTIONAL_LOCKS=0`: `install_one` recopies the body, so a plain `git status` rewrites
`.git/index` to refresh its stat cache — a real write, on every idempotent cascade. The
closing line states what was actually established — `N of M verified committed, K not
verifiable` — rather than over-claiming. `--dry-run` skips the audit, as it writes nothing.

**It reports; it never commits.** Committing into N repos the operator did not ask you to
commit into is a far larger claim on their working tree, and the constraints it would have to
honour — never stage unrelated work, never touch a foreign branch — are the accidents this
epic exists to prevent. The brief left the commit path open and asked for the smaller change
that fully fixes the problem; report-and-exit does, because the defect was being *told* the
upgrade was complete when it was not.

### Changed — ♻️ one definition of "what the harness owns"

The path set the drift guard checks moved out of `init.sh` into **`tools/harness-owned-paths.sh`**,
which both `init.sh` and the new audit call. E99-F10 needed four corrections to that set in a
single week — `.codex`/`.gemini` claimed wholesale, symlinked ledgers, non-regular ledger
entries, wildcard basenames — and every one was a false positive that failed the *mandatory*
gate on a file the operator owns. A second inline copy in the installer would have had to
relearn all four.

The logic is **moved, not rewritten**: the 27 existing drift-guard assertions pass unchanged,
which is the extraction's regression contract. On top of that, R8 is *differential* — it
perturbs a project-owned path, a body path, root glue, and a user file in the `.agents/` tree,
and requires `init.sh` and the audit to agree on all four **and** to be right. Asserting that
both files merely reference the helper would prove nothing about agreement.

`init.sh` degrades to a warning if the helper is absent (a torn install must not halt the
harness every session), consistent with every other ambiguous case in that guard.

## [0.51.2] — 2026-08-02

### Fixed — 🐛 a fresh seed no longer inherits the harness's own `blocking_severities` (E99)

`harness.config.yaml` is seeded into a target by **copying** the harness repo's own file, so
any `pr_loop` value this repo sets for itself silently became every target's default. That
was already handled for `enabled` — a target may not have the Codex GitHub App — and is now
handled the same way for `blocking_severities`.

This repo raises its own threshold to **`P0,P1,P2`**. Across E24-F01 (PR #98) and E99-F10
(PR #100) — seven review rounds — every real defect arrived tagged **P2**, and none arrived
as P0/P1 after the first round. Six of them let the drift guard claim a path the installer
does not own, failing the *mandatory* `init.sh` gate on an operator's own file; one made the
guard print `installed harness matches the commit` over an edited body. The gate said
`merge` on nine findings that had to be fixed anyway, so the configuration and the actual
review behaviour disagreed almost every round.

That is a calibration mismatch, not a judgement call: Codex severities are tuned for
application code, where a wrong output is one bad response. In a **gate**, a wrong output is
the gate vouching for something it never checked. But the reasoning is a property of what
this repo builds — for an ordinary product repo, blocking on P2 spends rounds on findings
that never blocked anything, which is the cost E21 exists to control. So the raise is local
and the shipped default stays `P0,P1`. `nit` remains non-blocking everywhere.

The seed also drops the run of comment lines explaining a value it overwrites, so a target
never reads a rationale sitting above a value that contradicts it. Comments on keys the seed
keeps — including a target's own hand-written ones — survive untouched.

The `/sdd-pr-loop` runbook now **reads** the key instead of asserting `P2`/`nit` never block.
That was the one blocking finding on this change's own review, and it was the sharpest defect
it could have shipped: classification is performed by the agent following that prose, so a
raised config plus a runbook saying P2 is excluded means P2s never reach `blocking.json`, the
gate reads the empty set as "reviewed, nothing blocking", and auto-merge proceeds over
findings the repo just declared blocking — the threshold would have looked raised and behaved
unchanged. Both maintained copies (the canonical body and the checked-in source-layout copy)
were updated; the historical passages about PR #86/#89 stay as written, being accurate
past-tense facts rather than instructions.

Pinned by `test_pr_loop.sh` R15b, which asserts the **source** genuinely carries the raised
value before checking the seeded one, and R49b, which asserts both runbook copies read the key
rather than hardcoding the answer. Without that precondition the assertion would pass
just as well against a source that was never raised, proving nothing about the forcing.

## [0.51.1] — 2026-08-02

### Fixed — 🐛 the drift guard over-claimed shared namespaces and lost its diagnostic on a large drift (E99-F10)

Three follow-ups against the E24-F01 guard, filed from PR #98 round 3 rather than fixed in
a fourth review round.

**`.codex/agents/` and `.gemini/agents/` are shared with the operator.** The installer says
so explicitly — "Codex's project-local role namespace is shared with the operator" — and
preserves foreign or edited role files. The guard claimed both directories wholesale, so a
project's own `.codex/agents/project-role.toml` failed the **mandatory** gate and halted
every agent step. That is the same false-positive class the `.agents/` narrowing fixed one
round earlier, in the two directories that narrowing did not reach.

They are now claimed **per file**, resolved from the installer's own ownership ledger at
`.harness/.model-agents/<tool>/` — a byte copy of each per-role file it last wrote. That
listing *is* the owned set, so `init.sh` needs no duplicated `MODEL_ROLES` list and stays
correct when that list changes. No ledger ⇒ nothing claimed for that tool, which is the
fail-safe direction: a missed drift costs a warning, a false positive costs the harness.

**A drift larger than the pipe buffer printed no diagnostic at all.** `printf | head -n 10`
early-closes the pipe; the upstream `printf` takes SIGPIPE and exits 141, and under
`set -o pipefail` + `set -e` that aborted the gate *before* the elision count, the recovery
command, and the `fail()` message. Measured on macOS: ~70KB of porcelain output does not
trip it, ~176KB does. `sed -n '1,10p'` reads to EOF, so nothing early-closes.

**The recovery command could not be pasted from a path containing whitespace.** `$PROJECT_ROOT`
was interpolated unquoted, so git received only its first word as `-C` and exited 128 — on
the one line whose entire purpose is to be copied. Now single-quoted, with embedded quotes
escaped.

Review round 1 added a fourth: a **symlinked ownership ledger** is not a ledger. `-d` and
the glob both follow symlinks, so a symlinked `.model-agents/<tool>` enumerated an external
directory and turned arbitrary basenames there into owned pathspecs — failing the mandatory
gate on an operator role file no stamp claims, which is the very class this fix exists to
close. The guard now mirrors the installer's own three-level refusal
(`harness-install.sh:2606-2618`) rather than trusting a ledger the installer itself would
not write to.

Round 2 added the general form of the same rule: a ledger entry must be a **regular file**.
`-e` accepted a directory named `project-role.toml`, promoted its basename to an owned
pathspec, and failed the gate on the operator's role file of that name. The installer writes
byte copies and nothing else, so `-f` rejects directory, fifo, socket and device in one test
rather than adding another special case.

Round 3 closed the remaining shape — not *which* ledger entries count, but how their names
are **interpolated**. A basename is data: `:(literal)` stops a stamp named `project-*.toml`
being read as an fnmatch wildcard that claims the operator's `project-role.toml`, and one
shared shell-quoting helper now escapes the root and every pathspec alike, so a stamp named
`operator's-role.toml` no longer produces a `list them` command that cannot parse.

Pinned by seven cases in `tests/test_init_drift_guard.sh` (18 → 27 assertions), each
asserting its own fixture preconditions. That discipline earned its keep here: the first
draft of the SIGPIPE case used 1,200 files (~70KB), stayed under the pipe buffer, and
**survived** the mutation that restores `head -n 10` — it was asserting nothing. It now
measures the porcelain output and fails if the fixture ever drops below the threshold.

## [0.51.0] — 2026-08-02

### Added — ✨ `init.sh` refuses to run on an unlanded harness (E24-F01)

`harness-install.sh` stamps `VERSION` into `.harness/.harness-version`
(`harness-install.sh:2194`), but exactly one caller ever read it: the *next* installer run,
deciding upgrade-vs-fresh (`harness-install.sh:1794`). At runtime the stamp was dead
metadata — `init.sh` referenced neither it, nor `VERSION`, nor whether the installed body
was committed. An upgrade that was written but never landed was therefore
indistinguishable from one that was landed.

That gap is not theoretical. A v0.50.x umbrella cascade across five children left 26–29
uncommitted files in each. Nothing failed, for days: every Builder and Reviewer spawned
there read agent prompts no commit describes, and three children ran the change-size
classifier against a committed `harness.config.yaml` with no `change_size` block while
`migrate_config()` had already appended that block to the working tree.

`init.sh` now checks, between its structural checks and its TaskStore validation, that the
harness-owned paths match what the branch records. Drift fails the gate with the count, a
capped sample of the paths, and the command that lists the rest.

**One check, not two.** `.harness-version` is itself a tracked file inside the harness-owned
tree and every upgrade rewrites it, so a half-applied upgrade surfaces through the same
dirty-tree check that catches the prompts. No second signal exists at runtime: `init.sh` has
no access to the harness *source* it was installed from, so installed-vs-latest is not a
comparison it can make.

**Scope is ownership, not diff size.** The checked set is `.harness/` minus the PROJECT-OWNED
paths (`harness.config.yaml`, `init.project.sh`, `specs/product.md`, `specs/epics/`, `state/`,
`progress/`), plus the generated front-end glue at the project root (`.claude/agents/`,
`.claude/commands/`, `.agents/`, `.codex/agents/`, `.gemini/agents/`, `opencode.json`). It is
deliberately *not* an enumeration of the ~29 owned files, which would duplicate the
installer's knowledge in a second place and drift from it.

**False positives are the dominant risk** — this gate runs before every agent step, so a
misfire halts the harness and gets the guard disabled. Every ambiguous case degrades to a
silent skip or a warning, never a failure: no install stamp, no git work tree, or a body that
is not version-controlled at all. `HARNESS_SKIP_DRIFT_CHECK=1` overrides it per invocation
(an env var, not a config key — a config key gets set once during a bad afternoon and
disables the guard forever), and the skip prints a line rather than staying silent.

The guard reports; it never repairs. No auto-commit, no auto-reinstall, no writes of any kind.
Landing the upgrade is the producing side's job — E24-F02.

Round-1 review hardening (PR #98): the suite now **executes** `.harness/init.sh` rather than
`sh`-ing it — `init.sh` is bash (`set -euo pipefail`, a bash array), so on any system whose
`/bin/sh` is dash it died at line 8 before the guard ran, making the verification command
unconditionally red in CI while passing on macOS where `/bin/sh` is bash in POSIX mode.
`run_gate()` now asserts the harness banner appears, so an interpreter-level death can never
again be read as a gate verdict. `git status` is called with **`-uall`**: an upgrade that
*adds* a body file leaves it untracked, and `status.showUntrackedFiles=no` in any repo or
global gitconfig made the guard print "matches the commit" over exactly that drift. And the
"list them" recovery command is now derived from the pathspec array instead of a
hand-written approximation that had already drifted from it — it omitted `.codex/agents/`,
`.gemini/agents/` and `opencode.json` and dropped every `:(exclude)`.

Round-2 review hardening (PR #98) closed three more holes, all in the checked path set.
`.agents/` is a **user-owned** tree in which the installer owns only `rules/*`, `agents/*`,
`workflows/*` and the `sdd-*` skill units, so the blanket pathspec would have failed the
mandatory gate on a project's own `.agents/skills/mine/SKILL.md` — the false positive this
feature named as its dominant risk. The generated OpenCode glue (`.opencode/command/*`,
`.opencode/agent/pr-fixer.md`) was outside every pathspec, so an opencode target reported
clean over edited harness glue. And the R9 probe now asks about the installed **body**
alone: a repo that gitignores `.harness/` while tracking the root glue had a non-zero
combined count, skipped the warn-only branch, and then — git being unable to report the
ignored body either — printed `✅ installed harness matches the commit` over an edited
`.harness/agents/builder.md`. A false clean is the worst output this feature can emit.

Pinned by `tests/test_init_drift_guard.sh`, a behavioral suite that installs real targets and
reads the gate's exit code. Four of its requirements assert an absence or a pass, so each is
paired with a positive control on the same fixture where only the discriminating fact differs
— an expected value with more than one producing code path proves nothing. R9 in particular
pins the `ls-files`-before-`status` ordering: `git status --porcelain -- .harness/` reports
`?? .harness/` when nothing is tracked, so a status-first implementation would read an
un-version-controlled install as drift and hard-fail it.

## [0.50.2] — 2026-08-02

### Fixed — 🐛 change-size charged the harness body and agent surfaces to the product budget (E99-F71/F89)

`tools/change-size.sh` counts the working tree INCLUDING untracked files, deliberately: the
in-session Builder has no commit step, so a `<merge-base>...HEAD` diff would report tier `ok`
with zero production lines on precisely the branch the check exists to measure (pinned by
`test_change_size.sh` R5b). That inclusion also charged installer output to whatever branch
was under review, and the tier went wrong in both directions:

- four `.mutbak` backups in the tree → `production 1104 lines / 2 files` against a true
  `42 / 1`, a **26x overstatement**. Since mutation campaigns became routine, `.mutbak` files
  are now the EXPECTED state during review, so this misfired more often over time, not less;
- a consumer's 78 untracked install artifacts (2154 lines) → `ESCALATE 3965 / 87` for a branch
  that measured `ADVISE 1811 / 9`. Both PRs had their tier re-derived by hand.

The reported root cause prescribed measuring `<base>..HEAD` instead of the working tree. That
was **rejected**: it reintroduces the defect R5b prevents, trading a 26x overstatement for a
100% understatement on a check whose whole purpose is to fire before the Builder commits. The
rejection is now recorded in the script so it is not attempted a third time.

The fix is classification, not concealment. The harness body and the agent surfaces this
installer writes — `.harness/`, `.claude/{agents,commands}/`, `.agents/`, `.codex/`,
`.opencode/` — are installer OUTPUT in every consumer, so they join the built-in `generated`
classifier and are excluded from the budget entirely. They stay **tracked**: the documented
install workflow is committed-and-shared, and ignoring them would leave every Codex skill,
Antigravity rule and OpenCode command out of a fresh clone, making `.claude/` first-class and
every other front end second-class. Scoped deliberately — `.claude/agents/` and
`.claude/commands/` only, never `.claude/` wholesale, and no root file: `CLAUDE.md` is
hand-authored per repo and still counts as production.

Only genuinely machine-local artifacts are ignored, because no clone should receive them:
`*.mutbak` (per-developer review scratch) at the project root, and `__pycache__/` + `*.pyc`
under `.harness/` — the latter already ignored by the harness source's own root `.gitignore`,
just never propagated to consumers.

Pinned by `test_change_size.sh` R5d (gitignored scratch never moves the count, while untracked
real work still does — witness: 42 lines vs 2442 with `--exclude-standard` dropped) and R5e
(generated surfaces stay tracked and classified out — witness: 80 lines vs 1980 without the
classifier), plus `test_install.sh` assertions that the agent surfaces are NOT ignored.

## [0.50.1] — 2026-08-02

### Fixed — 🐛 the `pin.` comment over-claimed what an unpinned tier does on Codex (E23 follow-up)

E23-F01 made role registration independent of model routing: selecting Codex now always
writes all six `.codex/agents/*.toml`, and `gen_codex_agent` simply omits the `model` key
when the role inherits or its tier is unpinned. The guidance around `models.pin.` was
written before that and still said an unpinned tier "stamps nothing" — which now reads as
"you get no role definition at all" rather than the truth, "you get the role definition
without a `model` key". Semantics are unchanged; only the wording was wrong.

Corrected in all four places the claim appeared, so they cannot drift apart:

- `harness.config.yaml` and the matching migration heredoc in `harness-install.sh` — these
  two are required to stay **byte-identical** (a fresh install copies the config verbatim,
  an upgrade only migrates), so fixing one without the other would have split them.
- The `model_alias` comment in `harness-install.sh`, which describes the absent Codex /
  OpenCode alias entries.
- `docs/INSTALL.md` → "Pinning an exact model", now cross-referencing "Where the values
  land", which already described the post-E23 behavior correctly.

### Changed — 📝 board bookkeeping

- `specs/epics/E17-model-routing/epic.md` listed `E17-F01` as `pending` in its feature
  table while `state/tasks.json` had it `done`. The feature table now matches the board.

No behavior change: comments and documentation only. Surfaced by the E23 drift check.

## [0.50.0] — 2026-08-01

### Fixed — 🐛 the pr-loop chased findings it was configured to ignore (E99)

Measured on this repo's telemetry and `.pr-loop/` cache: **20 of 43 Codex-fix commits
addressed P2s**, a severity `pr_loop.blocking_severities` (default `P0,P1`) explicitly
excludes. PR #89 reported **zero blocking findings in all three rounds** and still spent
three rounds and three P2 commits; PR #86 was clean at rounds 6, 7 and 8 with CI green and
ran on to **round 12** against `max_rounds: 4`.

The classification was never wrong — `blocking.json` was correctly empty every time. What
was missing is that the ACTION was left to the driving agent's prose reading of the runbook,
and prose is something an agent can talk itself out of when a reviewer bot keeps posting.

- **New `tools/pr-gate.sh`** — reads the round cache the loop already wrote and prints one
  binding verdict: `merge` (0), `fix` (6), `escalate` (7), `needs-human` (8), usage/unreadable
  (4). Zero blocking findings ⇒ `merge`, at any round. It **fails closed**: a missing, empty
  or non-array `blocking.json` is never a `merge`. Scope is deliberately narrow — a `merge`
  verdict says "the review converged", NOT "this PR may merge"; the CI-green check and
  `tools/pr-stack-guard.sh` remain separate gates.
- **An empty `blocking.json` is not by itself evidence of a clean review.** A round where
  the watcher timed out has an empty blocking set for the opposite reason — no review landed.
  The first version of the gate answered `merge` there. Caught on this change's own PR #90,
  where Codex replied **54s inside the 900s ceiling** and the 60s-interval watcher missed it.
  The gate now re-derives the round's review state via `wait-for-codex.sh evaluate` before it
  reads `blocking.json` at all, and reports `unresolved` (exit 9) when no review has landed.
  The verification is deliberately independent rather than a caller-supplied flag: the point
  of the gate is not to take the loop's word for it.
- **The gate asks the budget question first and probes the review only to justify a merge**
  (Codex P1 x3 on PR #90 round 2). Three ordering defects in the first cut: a *clean* review
  legitimately has no `blocking.json` — the runbook skips classification on watcher exit 3 —
  so demanding the file sent every banner/reaction clean review to `needs-human`; probing the
  review state on a *blocking* round returned `unresolved` for every ordinary round, because
  step 6 re-fetches `pr.json` after a fixer pushes and the cached head moves past the head the
  findings were filed against; and the runbook branched on the round budget **before** calling
  the gate, so a clean round at the cap could never merge. Now: blocking findings ⇒ pure budget
  decision with no probe; empty/absent blocking set ⇒ prove a review landed. Inline findings
  with no `blocking.json` fail closed — unclassified severities prove nothing.
- **The gate is asked exactly ONCE per round** (Codex P1, PR #90 round 3). Consolidating the
  verdict into step 5 left a second call in step 6, after the fixers push. The fix commits do
  not rewrite `blocking.json`, so that second call necessarily re-read the same non-empty set,
  returned `fix`/`escalate` again, and routed the driver back through step 5 forever. Step 6
  now confirms CI and **advances** to a fresh review; `tests/test_pr_gate.sh` R8 asserts the
  call count in both maintained copies.
- **`/sdd-pr-loop` now calls the gate** and states that non-blocking findings are excluded by
  configuration, not oversight — a P2 on a PR the gate calls `merge` belongs in its own PR.
- **`max_rounds` is now a budget for the PR, not for one invocation.** The round counter
  resumed from `round=1` on every run, so re-running `/sdd-pr-loop` silently granted a fresh
  budget — how #86 reached round 12 without the round-4 `needs-human` hand-off ever firing.
  It now resumes from the highest round already in the cache. The base-change restart still
  re-derives round 1 correctly, because it moves stale rounds to `stale-<ts>/` first.
- Removed a **pre-existing duplicated sentence fragment** in the installer's `/sdd-pr-loop`
  heredoc that had been shipping to every consumer.

### Changed — ⚡ the suite runs concurrently and reports only failures (E99)

`verification.test_command` was a hand-maintained chain of **27 `&&`-joined suites** that
every feature appended to. It cost the Reviewer, every round, on two axes:

- **634s wall clock**, serially.
- **~77KB (~19k tokens) of output on a fully GREEN run** — 32KB of it `test_install.sh`
  installer warnings — all of which the Reviewer read to learn one bit.

- **New `tools/run-tests.sh`** — discovers `tests/test_*.sh` and runs them concurrently
  (`--jobs`, default 8; `--serial` to bisect). On green it prints **one line**; on red it
  fails, names each failing suite and surfaces its output **in full**. Measured here:
  **634s → 171s, all 27 suites still passing.**
- `verification.test_command` is now `sh tools/run-tests.sh`. Because it DISCOVERS suites,
  adding a `tests/test_*.sh` no longer means hand-editing the scalar.
- The suites were already mutually isolated (per-case `mktemp` fixtures, sandboxed `HOME`
  and `CODEX_HOME`, no writes into `state/`, `specs/`, `progress/`); concurrency is a claim
  about that, and a suite that passes `--serial` but fails under `--jobs` is an isolation
  bug in the suite, not a reason to pin the runner.

### Added — ✅ `tests/test_pr_gate.sh`

Twelve assertions over both tools: the verdict table, the P2-only-PR case that motivated the
work, fail-closed behaviour on unreadable input, both maintained `/sdd-pr-loop` copies
actually calling the gate, and the runner's quiet-green / loud-red contract.

## [0.49.1] — 2026-07-29

### Fixed — 🐛 change-size `--format json` escapes every C0 control character (E99-F08)

P2 deferred at the merge of PR #83 (E99-F07).

- **`_json_escape` escaped only `\`, `"` and tab** (`tools/change-size.sh`). E99-F07 moved the
  tracked path scan to `git diff --numstat -z`, which stops git C-quoting special characters —
  so a raw control byte in a tracked pathname now reaches the JSON emitter **unencoded**. A
  tracked `src/a<CR>b.js` made `--format json` **exit 0 while emitting JSON that `jq` rejects**
  with an invalid-control-character error: fail-silent on a machine interface, discovered only
  when the consuming parser dies. The escape now handles the **class** rather than adding a CR
  rule beside the tab rule: short escapes for `\b \t \n \f \r`, `\u00XX` for every other C0
  control (U+0000–U+001F), via a single awk pass keyed on an ordered control table. DEL
  (U+007F) is deliberately **not** escaped — it is not a C0 control and JSON does not require
  it. New regression coverage (R8d in `tests/test_change_size.sh`) round-trips tracked
  pathnames containing a raw CR (short-escape branch) and a raw VT (`\u00XX` branch) through
  `--format json`, with jq-free assertions so the coverage does not vanish on a jq-less host.

### Fixed — 🐛 change-size misclassifies a pathname containing a literal newline (PR #89, Codex P2)

- **The NUL-framing repair `tr '\0' '\n'` made a content LF indistinguishable from a record
  separator** (`tools/change-size.sh`). A tracked `a<LF>b.js` split mid-path and the counts
  landed on the first fragment; a `x<LF>_test.py` was charged to **production** because the
  classifier never saw the test suffix — the JSON stayed parseable and the number was wrong.
  The framing parse is now byte-exact and adds **no new dependency**: `od -An -v -tu1`
  (POSIX, 8-bit clean by design) renders the stream as decimal bytes and awk reassembles
  NUL-framed fields, folds renames onto the destination exactly as before, and encodes each
  pathname (`\` → `\\`, then LF → `\n`) for the newline-framed pipeline; the classifier awk
  decodes in a single left-to-right pass **before** matching, and the concentration list
  decodes only at emission. The concentration list's exclusion filter matches on the
  **decoded** pathname too: a configured `test_paths`/`generated_paths` regex can tell the
  encoded and decoded forms apart (`^foo\\nbar[.]js$` hits the encoded form of a real-LF
  path), so matching the transit form could drop a production file from — or add a generated
  file to — `top_production_files` while the totals said the opposite. (An earlier revision
  of this fix used python3, which `init.sh` only guarantees for the `tasks: local` backend —
  caught in review.) New regression coverage: R8e round-trips newline-bearing tracked,
  untracked, and renamed-onto pathnames through `--format json` byte-exact and asserts the
  test/production split; R8f pins both encoded-vs-decoded mismatch directions against a
  configured `generated_paths` regex. Both were mutation-verified against their defect
  shapes.

## [0.49.0] — 2026-07-29

### Added — ✨ Native Codex skills and inherited role registration (E23-F01)

- Selecting Codex now installs `$sdd-next`, `$sdd-new`, `$sdd-plan`, `$sdd-drill`,
  `$sdd-fix`, and `$sdd-fix-parallel` as repository-local
  `.agents/skills/<name>/SKILL.md` artifacts. `$sdd-pr-loop` follows the existing
  opt-in `pr_loop.enabled` gate. Every skill includes explicit-only
  `agents/openai.yaml` metadata and maps text accompanying `$skill` to `$ARGUMENTS`.
- Codex now always receives exactly six project-local `.codex/agents/*.toml` role
  definitions. Inherited and unpinned roles omit `model`; concrete Codex pins add it
  only to the roles that resolve to that pin.

### Changed — 📝 Safe retirement of global Codex prompts

- Current installs no longer create, overwrite, or advertise
  `${CODEX_HOME:-$HOME/.codex}/prompts/sdd-*.md` as an active command surface and do
  not require `HOME` or `CODEX_HOME`.
- Ungated legacy prompts are preserved because their cross-target ownership is
  unknowable. Only byte-pristine legacy `sdd-pr-loop` is reclaimed, and only when its
  readable ownership ledger proves that no live target still claims it.
- Last-written stamps make selected Codex skill/role updates and deselection
  ownership-safe. Foreign or edited files are preserved; empty named directories are
  pruned without recursively deleting the shared `.agents/` tree.

## [0.48.0] — 2026-07-29

### Added — ✨ Stacked-PR lane for reviewability (E21-F04)

- **`tools/pr-stack-guard.sh`** offline merge-order guard. Given a PR's `baseRefName` and
  the list of open PR head branches, it exits `6` when a child PR is stacked on an
  unmerged parent and `0` only when the base is the repository's actual default branch.
- **`/sdd-pr-loop`** now fetches and uses the PR's real `baseRefName` / `baseRefOid` for
  diff computation, round-cache keying, and merge-gate evaluation instead of assuming
  `main`. It enforces the parent-before-child merge order for stacked PRs and restarts
  review from round 1 when a stacked parent is rebased.
- **Documentation** in `docs/WORKFLOW.md` describes when to use the lane, how to cut wave
  boundaries, and the manual restack procedure. Stacking is explicitly scoped to
  safely-splittable features and provides incremental review, not atomic delivery.

### Changed

- `pr-stack-guard.sh` requires `--default-branch` from the caller; it no longer hard-codes
  `main`. This prevents ordinary PRs in repositories whose default branch is not `main`
  from being misclassified as stacked.

## [0.47.0] — 2026-07-29

### Added — ✨ OpenCode concurrency probe + model helper (E22-F01)

- **`/sdd-test-concurrency`** command is now installed for the OpenCode front-end. It
  spawns two trivial subagents, measures whether OpenCode executes them concurrently, and
  writes a durable marker (`.harness/.opencode-parallel`: `supported` or `sequential`).
- **`--with-opencode-parallel=true|false`** installer flag overrides the marker.
- **`tools/opencode-model-helper.sh`** lists the models OpenCode sees, maps them to the
  harness tiers (`reasoning`/`standard`/`cheap`) by name heuristic, and emits ready-to-paste
  `pin.opencode.*` YAML. Pass `--apply` to append missing pins to `harness.config.yaml`
  without overwriting existing values.

### Changed — 📝 `/sdd-fix-parallel` is opt-in for OpenCode

`/sdd-fix-parallel` requires native concurrent sub-agent delegation. On OpenCode the
installer now reads the marker written by `/sdd-test-concurrency` and stamps the command
**only** when the marker says `supported` or when `--with-opencode-parallel=true` is passed.
The command is omitted by default on a fresh OpenCode install. Use serial `/sdd-fix` if
concurrency is not available.

## [0.46.3] — 2026-07-29

### Fixed — 🐛 change-size path handling, symlinks, handoff coverage and trend caching (E99-F07)
Four non-blocking findings deferred at the merge of PR #78, all reproducible.

- **`git diff --numstat` C-quoted TRACKED paths too** (`tools/change-size.sh`). The untracked
  side moved to `ls-files -z` during that review; the tracked side still parsed plain
  `--numstat`. `core.quotePath=false` governs non-ASCII bytes only — it does **not** stop git
  C-quoting a path containing `"`, a backslash or a tab, so `src/foo".spec.js` arrived as
  `"src/foo\".spec.js"` and its trailing quote defeated the `[._-](test|spec)\.[a-z]+$` suffix
  rule. A **test** file was charged to the **production** budget and the tier was silently
  overstated. Now `--numstat -z`, which git never encodes.
- `-z` also reframes numstat records, so the parser handles the real format rather than
  assuming it: a **rename** emits an empty path field followed by two extra fields, and is now
  folded into one record keyed on the destination instead of becoming phantom records. A
  literal **tab** in a pathname is no longer hidden behind C-quoting either, so both awk passes
  rejoin fields 3..NF (bare `$3` truncated `src/a<TAB>b.spec.js` to `src/a`, losing the
  classifier suffix), and `--format json` escapes the tab — a raw control character inside a
  JSON string is invalid and the caller only finds out when `jq` dies.
- **Untracked symlinks were followed** (`tools/change-size.sh`). `[ -f ]` follows a link, so a
  link to a regular file passed the guard and the line count read the **target**. git stores a
  symlink as a blob holding its link value: exactly one line. A link to a 2,000-line file
  contributed 2,000 lines before commit and 1 after — reintroducing the commit-coupling the
  uncommitted-work measurement exists to remove. A `-h` test now precedes `[ -f ]`, which also
  brings broken links and links to directories (previously dropped to 0) in line with git.
- **The pre-PR change-size handoff only fired in parallel-fix mode** (`agents/orchestrator.md`)
  — a coverage hole in the feature as shipped, not a nit. The instruction sat inside the fenced
  *Targeted parallel-fix worker mode*, so only `/sdd-fix-parallel` E99 workers ran it; ordinary
  features on the main `in-review` flow, and umbrella child PRs, never reached it and the tier
  never reached those PR bodies. It is now stated on the **main path** as
  *### The pre-PR change-size handoff*, cited by `agents/reviewer.md` and `docs/WORKFLOW.md`,
  and applied explicitly to umbrella child PRs. The worker mode keeps its load-bearing `--repo`
  caveat: `HARNESS_DIR` locates the *script*, not the tree under measurement.
- **`--cache` paths containing whitespace** (`tools/pr-round-trend.sh`). The concentration pass
  concatenated the round files into one unquoted word list, so a cache dir under a path with a
  space in it split into several arguments, every `cat` failed, and `top_files` came back empty
  under the `|| true`. The verdict still printed "SPLIT THIS PR" while naming **no seams** —
  losing the concentration data on exactly the non-converging handoff that exists to carry it.
- Not in scope, documented inline as unsupported: a filename containing a literal **newline**.
  `-z` framing handles every other special character.

### Changed — 📝 `agents/builder.md`: two rules about assertions that pass without proving anything
Guidance added to an existing role prompt's `## Principles` — no new capability, hence `Changed`.
**Five** assertions added while fixing the above passed while the guarantee named in their own
failure message was absent; the fifth was the guard written to stop the other four. That is a
rule gap, not five accidents, so the lens now lives in the installed body:
- **An assertion is only worth its expected value being reachable one way.** Ask of every
  assertion whether the expected value could be produced by any path other than the one the
  failure message names. If it can, the test passes whether or not the guarantee holds and its
  message misleads the next maintainer — worse than no assertion, because it stops anyone looking.
  Prove the answer by reverting the fix in place; the question is not reliable as a reasoning
  exercise.
- **A test asserting a PROSE contract must grep the SECTION it names, not the whole file**, with
  a copy-pasteable `awk` extraction recipe. A whole-file grep is satisfied by any unrelated
  occurrence of the phrase elsewhere in the file — including one the same change just added,
  which is exactly how three of the five slipped through.

## [0.46.2] — 2026-07-29

### Fixed — 🐛 `fix-worktree.sh` runs under the caller's locale; `C` is scoped to the ASCII slug globs (E99-F04)
- E99-F03 exported `LC_ALL=C` for the whole of `tools/fix-worktree.sh`. Three successive Codex
  rounds on PR #65 each found that export leaking into code the **target repo** owns: the
  project init gate (P1, round 2), the `post-checkout` hook and checkout filters fired by
  `git worktree add` (round 3), and the `reference-transaction` hook fired by `git branch -d`
  during teardown and `git update-ref -d` during create's rollback (round 4, deferred here).
- Rounds 2 and 3 were patched surface-by-surface. `reference-transaction` fires on essentially
  **every** ref update, so continuing that strategy converges on un-pinning the whole script —
  and no test can prove such an allowlist complete. The default is therefore **inverted**: the
  helper now runs under the **caller's** locale, and pins `LC_ALL=C` around exactly one region,
  the bracket-range `case` globs in `validate_key`, restoring the caller's locale on every exit
  path (including `die`) before any git call or foreign code runs.
- Every other read in the file was audited per call and left un-pinned: each is either
  exit-status-only or parses output that is ASCII by construction — object ids, refnames,
  absolute paths, `worktree list --porcelain` records split on literal ASCII prefixes, and
  `status --porcelain` tested only for emptiness. None is compared with a range glob.
- The E99-F03 defect stays fixed: `validate_key` still rejects non-ASCII-lowercase slugs under
  every locale, and the three previously-closed foreign-code surfaces stay closed — now by
  construction rather than by per-call escapes, which are removed as dead code.
- Teardown/rollback **ordering** — the worktree is retired before the branch ref in both paths,
  but for two *different* reasons, now documented separately. In `do_teardown` git enforces it:
  `branch -d`/`-D` refuse to delete a branch that is checked out in a worktree. In
  `rollback_create` git does **not** enforce it — `update-ref -d` has no such guard and will
  delete the ref out from under the checkout — but deleting the ref first leaves that worktree
  on an unborn branch, so the non-forced `worktree remove` then refuses and the residual is
  "registration present, branch absent": the one state `teardown` hard-refuses, which a re-run
  cannot reconcile. The retained order's worst residual is "registration retired, branch
  preserved", which a re-run of `teardown` does reconcile. Both diagnostics now name that state
  and that recovery instead of implying nothing moved.

## [0.46.1] — 2026-07-28

### Fixed — 🐛 the `/sdd-pr-loop` first-response probe is scoped to the current round (E99-F05)
- `tools/wait-for-codex.sh` arms a first-response probe (`HARNESS_FIRST_RESPONSE`, default
  180s) whose job is to exit `5` with a named remedy when the Codex GitHub App cannot answer
  at all — instead of making the caller wait out the full 900s ceiling for a review that can
  never arrive.
- `wfc_bot_seen` counted Codex issue comments and reviews with **no freshness filter**, and
  an earlier round's comments and reviews never leave the PR. So from round 2 on, the probe
  was disarmed on the very first poll by activity that predated the round's `@codex review`,
  and a repo whose App had gone away produced a plain timeout (exit `2`) instead of the
  missing-App diagnostic. Observed live on PR #68, rounds 2–6.
- Both counts are now filtered by the round's trigger timestamp — the same `trigger-ts.txt`
  anchor the resolution conditions already use (`created_at` for issue comments, `submittedAt`
  for reviews). An empty anchor (the no-trigger-id compat path) keeps the filter a no-op.
- The reaction check is deliberately left **unfiltered**: `reactions.json` is fetched per poll
  from *this* round's trigger comment id, so a 👀 there is round-scoped by construction and
  still counts as a first response.
- No change to the exit-code contract (`0` findings / `1` pending / `2` timeout / `3` clean /
  `4` usage / `5` no-first-response), the freshness guards, the three clean-signal forms, or
  the exact-literal bot-login match.

## [0.46.0] — 2026-07-28

### Added — ✨ `/sdd-pr-loop` reports whether the review is converging (E21-F03)
- `pr_loop.max_rounds` caps the loop and labels the PR `needs-human`, but never said what the
  human should **conclude**. The observed conclusion is "run it again": on
  `viernes-ai/viernes-bookings-api` PR #76 the operator posted `@codex review` twelve times by
  hand, and rounds 5–12 cost roughly 2M input tokens and 8 hours of wall clock to keep
  rediscovering that the diff was too large to review in one pass.
- The evidence was already on the PR and nobody aggregated it — the per-round blocking-finding
  count: `1 3 1 2 1 3 1 2 2 1 2 1`. A **decaying** count means the review is converging and one
  more round is rational. A **flat** count means the reviewer is sampling a surface larger than
  one pass can cover, so another round buys another *sample*, not more confidence.
- New `tools/pr-round-trend.sh` reads only `.pr-loop/<pr>/round-*/blocking.json` — files the
  loop already writes — and reports the series, a verdict (`converging` / `non-converging` /
  `insufficient`) and where the findings concentrate. No `gh`, no network, no new state; `jq`
  was already a `/sdd-pr-loop` precondition, so no new dependency.
- The rule is deliberately the simplest one that separates the two cases, because it has to be
  explainable inside a `needs-human` message: **the last 3 rounds each produced at least one
  blocking finding**. A least-squares slope would be defensible and unreadable.
- A round that aborted before classifying has no `blocking.json` and is **excluded** from the
  series rather than counted as zero — counting it would fake a convergence that never happened.
- New step 4b in `/sdd-pr-loop`; the cap row and the `needs-human` terminal state now carry the
  verdict, and on `non-converging` the message says **split this PR** and lists the files the
  findings concentrate on as candidate seams.
- **Advisory throughout**: exit 0 at every verdict, no change to when the cap fires, and no
  change to the watcher's exit-code contract, freshness guards or clean-signal detection.
- Round dirs are ordered by their **numeric** suffix. A shell glob is lexicographic, so at ten
  or more rounds `round-10..12` sort before `round-2` and the last-N window would trend rounds
  7–9 while calling them the latest — inverting the verdict on exactly the twelve-round PR this
  exists for.
- One unparseable `blocking.json` no longer empties the concentration list: the aggregation runs
  over the rounds already validated, so an aborted round cannot cost the handoff its seam names.
- `--format json` escapes finding paths, so a filename containing `"` no longer produces output
  that exits 0 and cannot be parsed.
- The installer's **generated** command body was updated alongside the source-layout copy, and
  `tests/test_pr_loop.sh` asserts against the installed body — editing only the source copy is
  a wiring gap that has been raised as a blocking review finding in this repo before, so the
  mutation (remove step 4b from the heredoc only) is verified to fail the suite.

## [0.45.0] — 2026-07-28

### Added — ✨ Pre-PR change-size check on the Reviewer → PR handoff (E21-F02)
- E21-F01 put a budget where the sizing *decision* is made; this puts a measurement where that
  decision is last *reversible*. Nothing between local approval and PR creation looked at how
  large a branch actually was — on `viernes-bookings-api` E14-F05 the branch was 17,202
  additions across 77 files before any number was attached to it, and the first entity to
  notice was a paid reviewer, twelve times.
- New `tools/change-size.sh` (POSIX sh + git + awk, no `gh`, no network — it runs *before* a
  PR exists). Measures the diff from the **merge base**, classifies every changed file, reports
  the tier, and when over budget lists the production files carrying the most additions.
- **It never blocks.** Exit 0 at every tier including `escalate`; the only non-zero exit is `4`
  (not a repo / no resolvable base ref / bad flag) and that measures nothing. A tool that could
  fail a branch for being large would be a hard cap wearing an advisory label.
- Reports **where** the lines are, not just how many: the actionable question at the handoff is
  *where do I cut*. On PR #76 a bare total would have been equally true of the 15,500 low-risk
  lines and the 1,716 that carried two thirds of the findings.
- Classification is additive: new `change_size.test_paths` / `generated_paths` take extended
  regexes **added** to the built-in multi-ecosystem defaults (JS/TS, Python, Go, Ruby,
  Java/Kotlin/C#, common lockfiles and vendor dirs), never substituted for them.
- `agents/reviewer.md` runs it before approving and records the tier and the decision in its
  verdict; `agents/orchestrator.md` runs it before opening the PR and carries the tier into the
  PR body. Documented in `docs/WORKFLOW.md`.
- Budget correctness: **binary** files now occupy the file budget (git reports `-` for their
  line counts, and discarding the record meant 30 production images reported
  `production_files: 0` and tier `ok`), and untracked paths are read **NUL-delimited** because
  `ls-files` C-quotes a name containing `"`, a backslash or a tab regardless of
  `core.quotePath` — the encoded text was used as the pathname, so those files vanished from
  the measurement entirely.
- Classifier robustness: a configured `test_paths`/`generated_paths` regex containing whitespace
  stays **one** alternative (it was word-split, so `(^|/)integration tests/` became
  `(^|/)integration|tests/` and every production path starting with `integration` silently left
  the budget), and untracked lines are counted with `awk NR` rather than `wc -l`, which counts
  newlines and therefore reported a one-line file with no trailing newline as **zero** additions.
- New behavioral suite `tests/test_change_size.sh` (registered in `verification.test_command`)
  drives the tool against a real throwaway git repo — a grep over the script would prove
  nothing about whether a test file counts as production, which is the failure that makes the
  number meaningless. Two fixture defects were found and fixed while writing it: the fixture's
  own rewritten `.harness/` config was landing in the measured diff, and R7's original
  `thing_spec.rb` already matched a built-in pattern, so it would have passed without ever
  exercising the config hook.

## [0.44.0] — 2026-07-28

### Added — ✨ Change-size discipline: a feature-size budget the Driller and Architect honor (E21-F01)
- Nothing in the harness bounded the size of a feature. `agents/driller.md` decomposed an epic
  with no size rule and `agents/architect.md` specced whatever it was handed, so the sizing
  decision was made implicitly at drill time and never revisited. Measured consequence
  (`viernes-ai/viernes-bookings-api` PR #76, E14-F05): one feature carrying R1–R36 / T1–T25
  became a PR of 17,202 additions across 77 files whose review did **not converge in twelve
  `@codex review` rounds** — a flat per-round blocking-finding rate (20 P1 + 15 P2), meaning a
  clean round would have been indistinguishable from a round that sampled a quiet region.
- New advisory `change_size:` block in `harness.config.yaml`, seeded on fresh install and
  migrated on upgrade: `advise_lines: 1500`, `escalate_lines: 3000`, `advise_files: 25`,
  `escalate_files: 50`, `max_requirements: 12`. An absent block behaves exactly as those
  defaults, matching the `telemetry:` / `fix_lane:` / `models:` convention.
- **Two soft tiers, no hard wall.** Both tiers produce a *recorded decision*; neither refuses
  work. A single cap is the wrong instrument twice over: an agent-written change is
  legitimately denser than a hand-written one, and a rename sweep or generated contract can be
  thousands of lines at near-zero review risk per line. Review risk concentrates rather than
  spreading — in PR #76, 10% of the files carried 67% of the findings — so the budget prompts a
  split *along seams*, not a refusal.
- Budgets are **production** lines: tests are a deliberate quality choice the Reviewer already
  enforces (a passing test per `R-id`) and must not be penalised by the instrument that governs
  review surface. Requirement count is the drill-time proxy because it is the only size signal
  that exists before any code does, and each `R-id` obliges a test.
- `agents/driller.md` now splits an over-budget candidate into siblings sequenced on
  `depends_on` and records the decision (or the deliberate non-split) in the epic's `epic.md`.
  `agents/architect.md` now stops before writing the four spec files when a feature would
  exceed the budget, reports the count and the seams, and — where a human directs it to proceed
  — records an explicit override line in the `.spec.md`. Neither role emits a `blocked` record
  on size: `blocked` is a closed vocabulary about dependencies and ownership.
- Documented in `docs/WORKFLOW.md` ("Change-size discipline"). Asserted in
  `tests/test_sdd_drill.sh` (both role files carry the rule and its non-blocking boundary;
  the shipped defaults cannot be silently retuned) and `tests/test_install.sh` (block seeded
  on fresh install, appended exactly once on migration, and the presence check tolerates a
  target's annotated `change_size:   # tuned` line rather than shadowing it with a second block).
- **On micro-specs:** the [pattern](https://www.augmentcode.com/guides/micro-specs-pattern-ai-agent-test-coverage)
  is already implemented here — an EARS `R-id` *is* an atomic single-behavior spec and the
  Reviewer already mandates a test per `R-id`. E14-F05 had 36 working micro-specs and was still
  unreviewable, because nothing mapped a micro-spec to a **deliverable**. This release adds the
  missing grouping rule, not another authoring phase; over-applied spec ceremony has its own
  documented failure mode
  ([Böckeler](https://martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html)).

## [0.43.1] — 2026-07-28

### Fixed — 🐛 Installer keeps `.harness/progress/` run dirs out of a consumer's VCS (E99-F06)
- The harness **source** has always ignored its own per-run agent output (`progress/*/` in
  its root `.gitignore`), but that ignore was never propagated to installed targets. The
  seeded `.harness/.gitignore` covered `telemetry.jsonl`, `jira.pat` and
  `state/tasks.json.lock` only — so in every consumer each agent run dir was committable,
  and in practice got committed. Measured on `viernes-ai/viernes-bookings-api` PR #76:
  796 lines across 6 files (**5% of that PR's additions**) were `.harness/progress/`
  pr-loop round scratch, shipped inside the product diff and re-read by the reviewer on
  each of twelve review rounds.
- `harness-install.sh` now seeds `progress/*/` plus the re-inclusions that keep the durable
  artifacts tracked (`!progress/.gitkeep`, `!progress/README.md`, `!progress/inbox/`,
  `!progress/inbox/**`). **Order is load-bearing**: `progress/*/` excludes the `inbox`
  directory itself and git does not descend into an excluded directory, so
  `!progress/inbox/**` alone would silently ignore every Architect brief.
- The append path (an existing `.harness/.gitignore`) now matches whole LINES (`grep -qxF`)
  instead of substrings. With negations in the list a substring match is unsafe:
  `!progress/inbox/` is a substring of `!progress/inbox/**`, so a file holding only the
  latter would suppress the former and lose the briefs. Still append-only — a target's own
  entries are never rewritten or reordered.
- A new ignore rule does **not** untrack an already-tracked file; an existing target must
  run `git rm -r --cached .harness/progress/<run-dir>` once itself. The installer
  deliberately does not do this — untracking files in someone's repo is not its call.
- `tests/test_install.sh` asserts the behavior with `git check-ignore` on a throwaway repo
  (run output ignored, briefs and `history.md` still tracked) rather than by grepping for
  strings, because no grep can see the ordering the re-inclusion depends on. Both the
  dropped-ignore and the dropped-directory-re-inclusion mutations fail the suite.

## [0.43.0] — 2026-07-28

### Added — ✨ the installer asks a third question: `pr_loop.enabled` (E20-F02)
- The toggle this work stream was opened for: **the human running the installer is the one
  who marks the PR-loop enablement.** E18-F01 made `pr_loop.enabled` opt-in (default
  `false`); turning it on has been a one-line hand-edit of `.harness/harness.config.yaml`
  ever since, discoverable only by reading source comments. The installer now **asks**, as
  one more plain line-oriented prompt right after the E20-F01 backend question:

  ```
  Enable the Codex PR review loop on this install? (E20-F02)
    1) false   stamp no /sdd-pr-loop glue — the opt-in default
    2) true    stamp /sdd-pr-loop + the pr-fixer sub-agent
               NEEDS the Codex GitHub App on this repo plus an authed `gh`.
               Nothing is probed now; the first /sdd-pr-loop run reports it.
    choose 1/2 [Enter keeps false]:
  ```

- **The opt-in default does not change.** This adds a prompt, not a new default. Pressing
  Enter keeps whatever the target already has, and a fresh install still cannot inherit the
  harness source repo's own `pr_loop.enabled: true` — `seed_pr_loop_optin` is unmodified and
  still normalizes a freshly copied config to `false` **before** the resolved value is
  applied, so "no answer ⇒ off" is enforced twice. The only route to `true` on a fresh
  target is an explicit `2` / `yes` / `--pr-loop=true`.
- **Scripted installs: `--pr-loop=<true|false>`** (also `--pr-loop <value>`). Suppresses the
  prompt; an empty value means *no override*, exactly like `--agents=` and
  `--builder-backend=`; an illegal value aborts non-zero **before** anything is created or
  modified in the target. With no TTY and no override nothing is asked and the config is
  left **byte-identical**, so CI keeps today's behavior exactly.
- **No environment twin, on purpose.** `HARNESS_PR_LOOP_ENABLED` keeps its exact E18-F01
  meaning: one of five **per-run** overrides (with `HARNESS_AUTO_MERGE`,
  `HARNESS_MAX_ROUNDS`, …) that gates a single run, still wins over the config for what that
  run stamps, and changes **no byte** of `harness.config.yaml`. Making one member of that
  family persist would turn `HARNESS_PR_LOOP_ENABLED=false ./harness-install.sh <target>`
  from "don't stamp on this run" into "permanently disable this target's loop". The layering
  is *the flag/prompt persists, the env overrides the run* — with exactly one warning when
  the two disagree, and none when they agree or the variable is unset.
- **The flip is reconciled inside the same run.** The write lands after the config
  seed/migrate stage and before glue generation, so answering `2` stamps `/sdd-pr-loop` and
  the `pr-fixer` sub-agent immediately, and answering `1` on a later re-run reclaims all of
  it through E18-F01's existing pass — including the `.sdd-pr-loop.owners` ledger, so a
  target flipping its own gate off never deletes a global Codex prompt another target still
  claims. E18-F01's unconditional command-body generation (the pristine reference that
  reclamation byte-compares against) is untouched.
- **No install-time preflight.** Enabling the loop probes nothing: the installer is POSIX
  `sh` with zero dependencies and never invokes `gh` or `jq`, which stay loop-runtime
  requirements. The prompt states the precondition instead, and `/sdd-pr-loop`'s own
  fail-fast diagnoses it at the one moment that can be accurate — the Codex GitHub App may
  legitimately be installed *after* the harness.
- **The config write is surgical.** Only the one scalar on the gate line is replaced,
  preserving its indentation and any trailing comment verbatim; where the `pr_loop:` section
  exists with no `enabled:` key at all, the canonical line is inserted after the header. A
  same-named `enabled:` under any other section, every comment, blank line and unrelated
  hand-edit survive, and a seeded target and an upgraded one converge on byte-identical
  blocks for both values.
- Docs: `docs/INSTALL.md` gains a "third question" section (the prompt, `--pr-loop=`, the
  per-run env ruling, the no-preflight ruling, re-run-to-change); the `pr_loop:` comment
  block in `harness.config.yaml` and in the installer's migration heredoc document the
  prompt in byte-identical text. Checks live in `tests/test_installer_toggles.sh`.

## [0.42.0] — 2026-07-28

### Added — ✨ the installer asks a second question: `execution.builder.backend` (E20-F01)
- Until now the installer asked exactly **one** question — which front-ends to stamp — and
  every other install-shaping choice was a hand-edit of `.harness/harness.config.yaml`
  discovered by reading source comments. The most consequential of those,
  **`execution.builder.backend`** (`in-session` vs `delegate` — the single seam an external
  executor plugs into), is now asked out loud, as a plain numbered follow-up prompt right
  after the front-end picker confirms.
- **The picker itself is untouched.** The new question is a separate line-oriented `read`
  prompt, not a row inside the checkbox list: that list is keyed on agent keys and emits a
  sorted key list, an enum has no `[x]`/`[ ]` meaning in it, and its raw-mode path (stty
  state, EXIT/INT traps, raw Ctrl-C bytes) is the highest-risk code in the installer. A
  `read` prompt is also identical on both interactive rungs, so the new toggle needs no
  fallback ladder of its own.
- **Scripted twin: `--builder-backend=<in-session|delegate>` / `HARNESS_BUILDER_BACKEND`**,
  exactly symmetric with `--agents` / `HARNESS_AGENTS`. The flag wins over the env var,
  both suppress the prompt, an **empty** value means *no override*, and an illegal value
  aborts non-zero **before anything is created or modified** in the target.
- **Nothing changes for anyone pressing Enter, or for CI.** Enter keeps the value the
  target already has (`in-session` on a fresh install), an unrecognized answer keeps it
  too, and a run with **no TTY and no override** asks nothing and leaves
  `harness.config.yaml` byte-identical.
- **The config is never rewritten wholesale.** Only the one scalar on the `backend:` line
  is replaced; its indentation, its trailing comment, and every other comment and
  hand-edit in the file survive byte-for-byte. Re-applying the same value is a no-op.
  `migrate_config` gained one entry so a config predating the `execution:` block gets it
  appended once, append-only — and that appended block is **byte-identical to the one a
  fresh install seeds**, the convergence rule `migrate_config` already states for its
  `models:` and `pr_loop:` entries, now asserted for `execution:` too.
- **The seeded `harness.config.yaml` documents the new surface where you edit it.** The
  `execution:` block's comment header names the prompt, `--builder-backend=` and
  `HARNESS_BUILDER_BACKEND`, so the majority path — a fresh install — is the discoverable
  one.
- **Choosing `delegate` before wiring `delegate_cmd` warns and proceeds** — it is neither
  refused nor silently downgraded to `in-session`. `delegate_cmd` is a free-text command
  the installer does not prompt for, so refusing would mean the prompt could never turn
  delegation on at all; downgrading would make the installer lie about what was chosen.
  The warning names `execution.builder.delegate_cmd` and the file to edit, and the Builder
  role already stops and reports if it is still empty when work starts.
- Change the value later by **re-running the installer** — the same reconfiguration path
  front-end selection already uses. `--print-agents` still prints exactly two stdout lines.
- New suite `tests/test_installer_toggles.sh`, wired into `verification.test_command`.

## [0.41.0] — 2026-07-28

### Changed — ✨ a fresh interactive install pre-checks the CLI you are in (E19-F02)
- E19-F01 built the detection and the explicit `--agents=host` mode but deliberately
  changed no default. This release spends it: on a **first, interactive** install into a
  target with **no existing install**, the agent picker now opens with the **detected host
  pre-checked and the other front-ends unchecked**, so installing from inside one CLI no
  longer stamps the other four's glue *and you do not have to know a flag exists*.
- **It is a pre-check, not a restriction.** The picker is already on screen: spacebar adds
  any other front-end before you confirm. That is precisely why the guess is made only
  here — where a human can correct it before anything is written.
- **The pre-check is the host ALONE**, never unioned with `claude`. Unioning would
  re-create the same complaint for every non-Claude user, in a harness whose premise is
  that the front-end is interchangeable.
- **An upgrade is never narrowed by detection.** "Existing install" is the presence of
  `.harness/.harness-version`, not of `.harness/.agents` — so a **pre-E08 install** (every
  front-end stamped, no persisted selection) still pre-checks **all** of them, and
  pressing Enter on an upgrade can never delete glue you are using. On an install that
  does carry a selection, that selection is the baseline, exactly as before.
- **Undetected still means everything**, and **nothing changes without a TTY**: a piped or
  CI run with no override still stamps all five front-ends, byte-for-byte as before. No
  removal authority, pristine-compare rule or `.sdd-pr-loop.owners` ledger behavior
  changes.
- **`--print-agents`' `baseline=` line now reports the picker's pre-check set**, so the
  diagnostic advertises the new default instead of the old one. For every *undetected*
  target it prints exactly what it printed before.
- **Documented in `docs/INSTALL.md`**: the new fresh-install default with its three cases,
  and — new section — that **re-running the installer** is the supported way to change the
  selection later (it re-opens the picker pre-checked from `.harness/.agents` and applies
  both additions and removals), a fact that previously lived only in a source header
  comment.

## [0.40.0] — 2026-07-28

### Added — ✨ `--agents=host`: install the glue for the CLI you are actually in (E19-F01)
- A human who works in exactly one coding-agent CLI used to get all five front-ends
  stamped into their repo — `GEMINI.md`, `opencode.json`, an Antigravity `.agents/` tree
  and global Codex prompts alongside the glue they wanted. The installer now understands a
  **`host` resolution mode**: `--agents=host` (or `HARNESS_AGENTS=host`) resolves to the
  single front-end this installer session is running in and stamps only that one.
- **Detection reads session markers, never ambient configuration.** A variable counts only
  when the front-end injects it into the environment of the processes it launches.
  Verified empirically, one row per front-end: `claude` (`CLAUDECODE`,
  `CLAUDE_CODE_ENTRYPOINT`; Claude Code 2.1.220), `codex` (`CODEX_THREAD_ID`; codex-cli
  0.145.0), `opencode` (`OPENCODE`, `OPENCODE_PID`; opencode 1.18.5) and `antigravity`
  (`ANTIGRAVITY_AGENT`, `ANTIGRAVITY_CONVERSATION_ID`; agy 1.1.8). `gemini` has no
  verified marker and is deliberately **undetectable** rather than guessed at.
  Config/credential variables are forbidden by rule — `CODEX_HOME`, `HOME`, `TERM_PROGRAM`
  and anything ending `_API_KEY` — because they prove only that you *use* a tool, never
  that this run was launched from it.
- **A miss is normal operation, never an error.** Markers for two or more front-ends at
  once (what nesting looks like) is treated as *undetected* with a stderr diagnostic, not
  as a tie to break. An undetected `host` run falls back to **ALL** front-ends on a target
  with no existing install (byte-identical to today's no-override default) and to the
  target's **persisted `.harness/.agents`** selection on one that already carries an
  install — so it can never silently widen a claude-only repo back to five front-ends.
  One line reports which happened.
- **New `HARNESS_HOST_AGENT=<key>`** — declare your host once (e.g. in a shell profile)
  for a front-end with no verified marker. An invalid value warns and is ignored; it never
  aborts an install.
- **New `--print-agents <target>`** — prints `host=<key or empty>` and `baseline=<keys>`,
  writes nothing, exits 0. It shares the resolution helpers with the real install, so the
  preview cannot disagree with what an actual run would do.
- **Strictly additive.** `host` is a resolution *mode*, not a sixth agent key: it is never
  added to `AGENT_KEYS`, never offered as a picker row, and never written to
  `.harness/.agents` (`--agents=host,gemini` is rejected). An install that does not name
  `host` behaves exactly as it did before — same no-TTY default, same explicit-CSV
  behavior, same interactive pre-check baseline, same `PRIOR_AGENTS` removal rules and the
  same `.sdd-pr-loop.owners` ledger authority over the shared global Codex prompts.
- New suite `tests/test_agents_host.sh` (wired into `verification.test_command`), every
  detection-sensitive case run under `env -i` with a sandboxed `CODEX_HOME`; the E08 block
  in `tests/test_install.sh` gains the end-to-end `host` case.

## [0.39.0] — 2026-07-27

### Added — ✨ `/sdd-pr-loop` + vendored Codex watcher, opt-in via `pr_loop.enabled` (E18-F01)
- The harness told its own agents to run `/pr-loop` in three places but shipped no such
  command — it came from the separate multi-cli-orchestrator skill set at
  `~/.agents/skills/`. The moment those skills are uninstalled (or on any fresh consumer
  that never had them) the documented review workflow pointed at a command that does not
  exist, and the watcher path it named was dangling. The loop is now **vendored into the
  harness** as first-class, installer-generated glue.
- **New command `/sdd-pr-loop <pr>`** — one body, mirrored byte-identically into
  `.claude/commands/`, `.opencode/command/`, `.agents/workflows/` and the GLOBAL
  `${CODEX_HOME:-~/.codex}/prompts/` — **only where `pr_loop.enabled` is `true`; nothing
  is stamped by default**. It preflights, posts `@codex review`, launches the
  watcher in the background, classifies `P0|P1|P2|nit`, spawns one fixer per blocking
  comment, escalates on a stall, and merges when every gate is green.
- **New watcher `tools/wait-for-codex.sh`** — the vendored background poller, converted to
  POSIX `sh` and installed executable. Three modes: `wait` (the source contract, exit `0`
  findings / `2` timeout / `3` clean / `4` usage), `preflight <pr>` (gh + auth + jq + repo
  slug + open PR; posts nothing; exit `5` with a one-line diagnostic naming the failed
  check), and `evaluate <round-dir>` (a pure, offline re-run of the same freshness rules —
  invokes no `gh`). A new **first-response probe** exits `5` naming the Codex GitHub App
  when nothing answers within `HARNESS_FIRST_RESPONSE` (default 180s), instead of polling
  to the 900s ceiling. All four vendored source files, the `--paginate --slurp` fetches
  and the three independent clean signals are preserved.
- **New canonical role `agents/pr-fixer.md`** — front-end neutral (one comment, one fix,
  one commit, one return), with gated shims for Claude (`.claude/agents/pr-fixer.md`),
  OpenCode (`.opencode/agent/pr-fixer.md`, `mode: subagent`) and Antigravity
  (`.agents/agents/pr-fixer.md`). No `pr-fixer` artifact is created for codex or gemini —
  those apply fixes in-session — and the model-routing role map is untouched, so
  `opencode.json` and `.harness/.opencode.stamp` stay byte-identical either way.
- **New `pr_loop:` config block** (`enabled`, `auto_merge`, `max_rounds`,
  `blocking_severities`, `merge_strategy`), seeded on a fresh install and appended
  byte-identically by `migrate_config` on upgrade. Absence of the block — or of any key —
  behaves exactly as the documented defaults. Each key takes a `HARNESS_*` env override;
  the execution knobs (`HARNESS_POLL_INTERVAL`, `HARNESS_POLL_CEILING`,
  `HARNESS_FIRST_RESPONSE`, `HARNESS_DRY_RUN`) are env-only.
- **`pr_loop.enabled` is OPT-IN — a fresh install seeds `false` and stamps no
  `/sdd-pr-loop` glue at all.** The gate is on **only** when the key resolves to the
  literal `true`; an absent block, an absent key, an empty value and any other token alike
  mean off. The loop functions only on a repository with the **Codex GitHub App** plus an
  authed `gh`, so defaulting it on would give every fresh install a command that could do
  nothing but fail its own preflight. Turning it on is a one-line edit of
  `.harness/harness.config.yaml` plus a re-run of the installer (E20-F01 will offer the
  choice at install time). The seed never inherits the *harness source repo's* own value,
  which stays `true` because that repo does have the App.
- **`pr_loop.enabled` back to `false` reclaims the glue** from every *still-selected* front-end (a
  new §7b reconciliation pass, since the existing deselect loop only reconciles
  front-ends that left the selection), pristine-only in the user-owned `$CODEX_HOME`
  prompts dir and the `.agents/` tree, pruning only dirs left empty. Flipping it back on
  restores byte-identical glue. The command body is generated into the neutral `CMDDIR` on
  **every** run regardless of the gate — that copy is the pristine reference reclamation
  compares against.
- **Clean break on env vars**: no `MCO_*`, `.mco-cache`, `~/.agents/skills`, `route-task`
  or `start-feature` token remains in the harness body. The round cache moved to
  `<HARNESS_DIR>/.pr-loop/<pr>/round-<n>/`, ignored by both the seeded
  `.harness/.gitignore` and the source repo's own `.gitignore`.
- `gh` and `jq` are **loop-runtime** dependencies only: `init.sh` gains no gate, so a
  target with neither still passes the environment check.
- New suite `tests/test_pr_loop.sh` (wired into `verification.test_command`);
  `tests/test_install.sh` asserts `/sdd-pr-loop` generation + deselect removal per
  front-end. Docs updated: `README.md`, `docs/INSTALL.md`, `docs/WORKFLOW.md`,
  `docs/HARNESS.md`, `CLAUDE.md`, `agents/orchestrator.md`.

## [0.38.1] — 2026-07-27

### Fixed — 🐛 Slug validation in `fix-worktree.sh` is locale-independent (E99-F03)
- `validate_key()` screens the fix slug with the shell glob `*[!a-z0-9-]*`. Bracket
  ranges in a `case` glob are resolved through the active locale's **collation order**,
  not ASCII, so under the common developer default `en_US.UTF-8` an uppercase slug like
  `Bad-Slug` fell inside `a-z`, the negated class did not match, and the invalid slug was
  **accepted** — a malformed value then propagated into the branch and worktree names the
  helper creates on disk. Under `C` the same expression rejected it correctly.
- `tools/fix-worktree.sh` now pins `LC_ALL=C` (exported) next to `set -u`, so every glob
  in the file means ASCII and the `git` plumbing output it parses stays deterministic.
  The `case` patterns are unchanged — with `LC_ALL=C` in force they were already correct.
  `[[:lower:]]` was deliberately **not** used: that class is itself locale-defined and
  would newly accept accented lowercase, widening the slug grammar instead of fixing it.
- The bug hid because `verification.test_command` runs in a C locale, where the
  expression behaves. `tests/test_fix_worktree.sh` gains
  `test_slug_rejection_is_locale_independent`, which drives the helper under **both**
  `en_US.UTF-8` and `C` (skipping cleanly where a locale is absent) and asserts rejection
  plus no ref/registration/path mutation — so the hole is caught in C-locale CI too, not
  only on a developer laptop.
- The C pin stops at **foreign code**. `fix-worktree.sh` executes code owned by the target
  repo at three surfaces — the project init gate (`init.sh`, which sources
  `.harness/init.project.sh`), `run` commands, and the `post-checkout` hook plus checkout
  (smudge) filters that `git worktree add` fires — and all three now run under the
  **caller's** locale, restored from the value captured before the pin. Exporting C into
  them was a real defect, not just a broad blast radius: a consumer whose
  `init.project.sh` requires UTF-8 failed its own gate, and `create` then rolled back an
  otherwise valid worktree.
- A caller with `LC_ALL` unset gets it restored as **unset**, not empty, so their
  `LANG`/`LC_*` layering resurfaces — an empty `LC_ALL` is ignored by some
  implementations and honored by others.
- `worktree add` is safe to un-pin precisely because its output is discarded and only its
  exit status is read; every remaining `git` call in the helper is read-only plumbing that
  **is** parsed and stays under `C`, so the determinism the pin was chosen for is intact.
- `tests/test_fix_worktree.sh` gains `test_child_commands_see_caller_locale`, whose init,
  `run`, and post-checkout-hook legs are each independently mutation-sensitive.
- Scope is only this glob: the `grep -Eq '^[a-z0-9-]+$'` validators in `harness-install.sh`
  and the Python `re` validator in `init.sh` were verified unaffected and left alone.

## [0.38.0] — 2026-07-27

### Added — ✨ Per-role model selection (E17-F01)
- Added a front-end-agnostic `models:` block to `harness.config.yaml` (seeded on a
  fresh install, append-migrated onto a preserved config) that maps each of the six
  SDD roles — `orchestrator architect builder reviewer scout doc-critic` — onto the
  tier vocabulary `reasoning | standard | cheap | inherit`, plus a
  `models.pin.<front-end>.<tier>` escape hatch written verbatim (see the two guards
  below).
- Taught `harness-install.sh` to stamp the resolved per-role model into the native
  agent-definition convention of every **selected** front-end: `model:` frontmatter in
  `.claude/agents/*.md` and `.agents/agents/*.md`, a `"model"` member in
  `opencode.json`, and two new conditionally-created project-local artifacts,
  `.gemini/agents/*.md` and `.codex/agents/*.toml` (never `$CODEX_HOME`).
- Built-in tiers resolve to floating vendor aliases only (`opus`/`sonnet`/`haiku`,
  `pro`/`flash`) — the harness ships no version-pinned model id. `codex` and
  `opencode` have no floating alias, so an unpinned tier there stamps nothing and the
  installer prints one advisory line naming the `pin.` key to set.
- **Opt-in and inert by default**: `inherit` compiles to key omission on every
  front-end (the literal string is never written), so an absent, empty or all-`inherit`
  block leaves the generated tree byte-identical to a harness without model routing —
  no model key, no `.gemini/`/`.codex/` directory, no `.harness/.opencode.stamp`,
  no `.harness/.model-agents/`. Moving a previously-stamped target back to all-`inherit`
  **reconciles** it: the pristine per-role files are reclaimed and the harness-created
  directories pruned, so the switch back to session inheritance actually takes effect
  instead of leaving the old `model` keys discoverable.
- Refined the `opencode.json` never-clobber contract so model changes can land: it is
  regenerated only when byte-identical to `.harness/.opencode.stamp` or to a freshly
  generated model-free body, and otherwise left untouched with a warning. Deselection
  reclaims every stamped artifact through the existing pristine byte-comparison.
  `.harness/.model-agents/` extends that stamp device to `.gemini/agents/` and
  `.codex/agents/`, so reclamation stays correct even when the `models:` block is edited
  in the same run — a user-edited artifact is still never deleted, only warned about.
- An unrecognized tier warns and resolves as `inherit` (never fatal). A pin is otherwise
  written verbatim, with exactly two guards: an `opencode` pin without a `/` and a pin
  whose value is the tier name `"inherit"` are each warned about and dropped, stamping
  nothing. Documented in `docs/INSTALL.md`; added `tests/test_model_routing.sh` to
  `verification.test_command`.

## [0.37.1] — 2026-07-27

### Fixed — 🐛 ADR-citation resolution is namespace- and qualifier-aware (E99-F50)
- `init.sh` section 2c resolved a cited `ADR-NNNN` **only** against `specs/adr/`, so a
  project that keeps a second, legitimate ADR namespace (`specs/<product>/adr/`, e.g.
  the platform-vs-product altitude split) got a standing wall of false-positive
  warnings — 18 of them in one downstream install, every one of them wrong.
- ADR spaces are now first-class. A **namespace** is a directory literally named `adr/`
  under `specs/`; only `*.md` sitting directly in it counts as an ADR. Its **token** is
  the parent directory's basename, with `platform` reserved for the root space
  `specs/adr/`. The spaces are independent and normally **collide** (`0023` in both,
  different content), so resolution is **qualifier-aware**:
  - **Qualified** — `<ns>/ADR-NNNN`, or `<ns> ADR-NNNN` when `<ns>` is a real namespace
    token — resolves against **that namespace only**. `platform ADR-0023` still warns
    when only `bookings/0023` exists; an unknown `<ns>/` never resolves. This is the
    cross-namespace typo the sweep exists to catch, and it is now caught.
  - **Bare** — `ADR-NNNN` asserts no namespace, so it resolves against **any** of them
    and warns only when it resolves in **none**. Deliberate: pre-convention corpora and
    single-namespace projects write bare ids, and inferring a namespace the author never
    wrote would recreate the false-positive wall.
  - **Known, accepted hole:** a **bare** citation is therefore *not* namespace-checked —
    in a multi-namespace project a bare cross-namespace typo passes silently. Write the
    qualifier to get it checked. This trade-off is recorded in `init.sh` section 2c, in
    `agents/reviewer.md`, and taught by `agents/architect.md` +
    `specs/_templates/feature.spec.md`.
- **The extractor normalizes before it matches**, because the optional qualifier group is
  blunt at both boundaries. (a) A `|` is appended to every id, so a citation can never be
  eaten as the *qualifier* of the id next to it — without it `ADR-0042 ADR-0001` produced
  one match whose "qualifier" `adr-0042` was then discarded and **never looked up**, a
  coverage regression against the plain `ADR-[0-9]{4}` scan. The delimiter must be a
  suffix; a prefix would break the legitimate `<ns> ADR-NNNN` form. (b) Emphasis/quote
  wrappers (`*`, `"`, backtick, `'`) are stripped, so a real qualifier written
  `**platform** ADR-0023` stays qualified instead of being silently demoted to bare.
  `_` is deliberately not stripped — underscore is legal in a namespace token.
- The per-namespace index is built **once** per run, so each citation costs one string
  match. A third namespace needs no code change. The index now takes only ADRs sitting
  *directly* in an `adr/` directory (an `adr/archive/` subtree is not a namespace),
  matching what the comment always claimed. The `searched:`/success lines are
  comma-joined so a namespace path containing a space stays unambiguous.
- **Contract sync (same rule at every altitude).** `agents/reviewer.md` no longer
  requires every cited id to resolve under `specs/adr/` and no longer preconditions its
  check on `specs/adr/` specifically — it states the qualified/bare rule verbatim, so an
  id `init.sh` certifies clean is never re-flagged at review time (and a product-
  namespace-only project gets a Reviewer check at all). `agents/architect.md`,
  `specs/_templates/feature.spec.md`, `docs/SPEC-FORMAT.md` and `docs/WORKFLOW.md` teach
  the qualifier convention and drop the single-namespace assumption.
- Unchanged by design: warn-only (never gates), zero dependencies, the
  `## Architecture alignment` section scoping, the trailing unresolved-count line, and
  the complete no-op when `specs/` holds no `adr/` directory at all.
- `tests/test_adr_citation.sh` gains R7 (a citation resolving in a second namespace is
  silent while a genuinely unresolvable id is the *only* warning), R8 (a project whose
  *only* ADR space is a product namespace still gets a live sweep, not a no-op), R9 (a
  qualified citation does **not** resolve cross-namespace, in both directions, and an
  unknown namespace warns), R10 (a bare citation stays permissive-any and an ordinary
  prose word is not promoted to a qualifier), R11 (contract coherence — each of the
  **five** contract files, `agents/reviewer.md`, `agents/architect.md`,
  `specs/_templates/feature.spec.md`, `docs/SPEC-FORMAT.md`, `docs/WORKFLOW.md`, plus
  `init.sh`, pinned independently), R12 (two adjacent ids on one line are **both**
  checked, in every bracket/bullet/indent/slash form, and no bogus namespace token is
  invented) and R13 (a qualifier wrapped in emphasis/quotes stays qualified).

## [0.37.0] — 2026-07-25

### Added — ✨ Deterministic next-task selection (E16-F03)
- Added the executable, zero-dependency Node 18+ `tools/next-task.mjs` selector
  with strict JSON output, canonical feature/slice ordering, exact dependency
  diagnostics, target and owner scopes, and umbrella fail/merge/integration
  precedence.
- Made valid selector output authoritative for the Orchestrator while retaining
  the complete Markdown routing policy as a reported fallback when Node is
  unavailable or output is invalid. Selection remains read-only and no gate,
  status, schema, dependency, ownership, or rollup policy changed.
- Installed the selector verbatim and executable, documented source/installed
  troubleshooting, and added differential feature/slice/owner/error fixtures,
  immutable-input checks, reordered byte determinism, and a 2,000-feature
  performance contract.

## [0.36.0] — 2026-07-25

### Added — ✨ Harness rationale and deletion ledger (E16-F02)
- Added a cold-readable `docs/RATIONALE.md` that explains why repository-changing,
  long-running agent work needs more than repeated prompting and separates
  current-model capability compensation from durable trust-and-intent controls.
- Added the complete 21-row C1–C8/D1–D13 retention ledger with repository pointers,
  mechanism-specific reconsideration evidence, a retain-by-default protocol, and
  the ADR-0001/E16-F03 boundary for replacing prose routing without removing the
  human-auditable gate policy.
- Added bounded primary-source notes, explicit METR study limitations, source and
  installed navigation, byte-identical installer coverage, offline link/inventory
  checks, and full-suite wiring without runtime or role-contract changes.

## [0.35.0] — 2026-07-25

### Added — ✨ Dependency-cycle and blocked-selection diagnostics (E16-F01)
- Added the executable stdlib-only `tools/task-diagnostics.py` helper with
  deterministic feature/slice SCC witnesses, graceful empty-board behavior, and
  actionable direct-input errors.
- Integrated warn-only cycle paths into source and installed `init.sh` after the
  canonical TaskStore validator, preserving all existing gate exit semantics.
- Pinned the seven stable no-selection reason codes, exact human templates,
  canonical ordering, scoped ownership behavior, and read-only informational
  contract for the Orchestrator, local store, and future E16-F03 selector.
- Added executable graph, 2,000-node scale, installed-layout, schema/status
  invariance, documentation, and full-suite regression coverage.

## [0.34.0] — 2026-07-25

### Added — ✨ Bounded isolated parallel maintenance fixes (E15-F03)
- Added `/sdd-fix-parallel`, a portable coordinator that provisions isolated F02
  worktrees before one atomic F01 claim, overlaps safe targeted workers, and
  serializes shared or unknown paths.
- Added targeted Orchestrator rules for Builder/Reviewer rounds, one PR and
  `/pr-loop` per fix, merge-before-done, failure isolation, and safe teardown.
- Kept each pre-provisioned F02 identity for the entire worker lifecycle and added
  coordinator-owned bookkeeping-PR persistence plus updated-base reconciliation
  before non-forced teardown. Parallel preflight rejects the delegate Builder
  backend with the serial fallback.
- Added `fix_lane` defaults, expected-path brief metadata, all-frontend installer
  generation/ownership, documentation, and permanent disposable coverage.

## [0.33.0] — 2026-07-25

### Added — ✨ Safe worktree-per-fix isolation lifecycle (E15-F02)
- Added the portable executable `tools/fix-worktree.sh` with deterministic
  `create`, exact-context `run`, and non-forced `teardown` operations for isolated
  `feat/E99-Fn-slug` branches under `.claude/worktrees/`.
- Creation resolves and snapshots a local default/base branch instead of ambient
  `HEAD`, fails closed on dirty or colliding state, links only the documented
  four-file personal layer, and safely rolls back unchanged failed provisioning.
- Teardown proves exact identity, cleanliness, merged ancestry, and canonical
  primary/base alignment before non-forced worktree removal and safe branch
  deletion; unsafe or unexpected state is preserved with a recovery diagnostic.
- The installer ships the helper executable and append-seeds
  `.claude/worktrees/` exactly once without clobbering existing ignore rules.
  Configuration-layering documentation and disposable Git integration coverage
  define the local-link and runtime-lock boundaries.

## [0.32.1] — 2026-07-25

### Fixed — 🐛 Board-write contracts use the mandatory lock helper (E15-F01)
- Routed the Inception, Fixer, Planner, and Driller structural TaskStore mutations
  through the existing `tasks-lock.py apply --mutator` path, with allocation and
  target checks repeated against the fresh board read inside the lock. Removed the
  obsolete direct-edit + inline-validation instructions.
- Routed slice mutations through guarded `apply --mutator` and documented feature/
  epic status rollups through `set-status`, so every persisted board write uses the
  single advisory lock without adding helper commands or changing helper behavior.
- Added static regression coverage for the role/store contracts and completed the
  E15-F01 test traceability matrix and behavioral checks for R12 and R13.

## [0.32.0] — 2026-07-25

### Added — ✨ ADR-citation id resolution: Reviewer soft flag + init.sh warn-only sweep (E99-F02)
- **Reviewer check extended to id resolution** (`agents/reviewer.md`): where architecture
  artifacts exist and the spec is `sdd: true`, each `ADR-NNNN` cited in a feature spec's
  `## Architecture alignment` section must **also resolve to an existing
  `specs/adr/NNNN-*.md` file**. A cited-but-nonexistent id is a **soft flag** for the
  Builder/Architect to investigate — reusing the existing "suspected but not provably
  violated → flag, don't block" verdict rule, **never a hard reject** (a dangling id may be
  a typo *or* an ADR legitimately renamed/removed since the spec was written). The check
  still never fires for a legacy/no-architecture feature or an `sdd: false` brief-only item.
- **`init.sh` session-start sweep (warn-only, additive)** — new section 2c scans every
  `specs/epics/**/*.spec.md` carrying the `## Architecture alignment` section and warns on
  any `ADR-NNNN` cited **inside that section** (incidental mentions elsewhere don't count)
  that resolves to no `specs/adr/NNNN-*.md`, surfacing the typo at session start instead of
  waiting for review. Zero-dep (grep/awk/ls), **never fails the gate**, and a complete no-op
  when `specs/adr/` is absent (graceful degradation, mirroring the Reviewer precondition).
- **New suite `tests/test_adr_citation.sh`** (R1–R6) covers dangling-id warn, all-resolve
  silence, `ADRs touched: none`, section-scoped extraction, and the no-`specs/adr/` no-op;
  wired into `verification.test_command` in `harness.config.yaml`. No status/schema change;
  the Architect's "cite ids or `ADRs touched: none`" contract is untouched — resolution is a
  strict refinement.

## [0.31.0] — 2026-07-24

### Added — 🔒 Board write lock: flock-guarded read-modify-write on tasks.json (E15-F01)
- **New advisory-lock helper `tools/tasks-lock.py`** (installed body, executable) guards every
  persisted `state/tasks.json` mutation. It owns the whole critical section in **one process**:
  acquire a portable stdlib **`fcntl.flock`** on the sibling lockfile `state/tasks.json.lock`
  (resolved with `cwd = HARNESS_DIR`) → **re-read `state/tasks.json` from disk inside the lock**
  → apply the single status mutation → validate (`json` parse **and** `store/tasks.schema.json`
  schema check) → atomically replace the file (write-temp-then-`os.replace`) → release. Re-reading
  *inside* the lock is the point: two near-simultaneous writers (E15 parallel fix chains) can no
  longer lose an update (last-writer-wins clobber).
- **Fail-stop, no torn file** — a mutation that fails validation aborts non-zero, releases the
  lock, and leaves the original `state/tasks.json` byte-for-byte intact.
- **Bounded acquisition, never a silent hang** — lock acquisition is bounded by a ~10s timeout;
  on timeout it exits non-zero with an actionable error naming the lockfile and the timeout,
  never blocking forever and never writing unlocked.
- **No-op for serial callers** — for a single (uncontended) caller the lock is taken immediately
  and the output is byte-equivalent to the old read-modify-write, so `/sdd-next` and existing
  tests are unchanged. The `store.on_write_command` hook fires **after** the lock is released,
  never inside the critical section. **No new status value and no `store/tasks.schema.json`
  change** — only the concurrency discipline around the write.
- **Portable** — depends only on `python3` + stdlib `fcntl` (already a write-path dependency);
  it does **not** use the Linux-only `flock(1)` binary (absent on macOS). Single-host scope;
  cross-machine coordination is out of scope.
- **Installer wiring** — `harness-install.sh` copies + `chmod +x`'s the helper into
  `.harness/tools/` and gitignores the runtime lockfile (`state/tasks.json.lock`) in the seeded
  `.harness/.gitignore`; `tests/test_install.sh` asserts a fresh install ships the executable
  helper. `store/local.md`'s `set_status` contract is amended to mandate the lock protocol.

### Fixed — board write lock robustness (Codex #46 P1 ×2, pre-release under 0.31.0)
- **Helper resolves `HARNESS_DIR` from its own path, not `cwd`.** `tools/tasks-lock.py` now
  derives the board root from `__file__` (`<HARNESS_DIR>/tools/tasks-lock.py` ⇒ parent-of-parent)
  when `HARNESS_DIR` is unset, so the documented `set_status` invocation is correct from **any
  cwd** in both the source layout (`tools/…`, board `state/tasks.json`) and the installed layout
  (`.harness/tools/…`, board `.harness/state/tasks.json`) — no `.harness/.harness` double-nesting
  and no requirement to hand-set `HARNESS_DIR`. An explicit `HARNESS_DIR` env var still wins as a
  highest-precedence escape hatch. `store/local.md`'s `set_status` contract is corrected to match.
- **Zero-dependency fallback validator now enforces the `slices` invariant.** When `jsonschema`
  is unavailable, the minimal validator mirrors the schema's cross-field rule: a **sliced feature
  may be `done` only when every slice is `done` and `merged`**. Previously the fallback stopped
  after the status-enum check, so `set-status <sliced-feature> done` on unfinished slices could
  atomically persist a board that `init.sh` later rejects (and prematurely unblock dependents).
  No schema/status change; single-repo features are unaffected.
- **One shared board validator (Codex #46 r2 P1, id 3649182844).** Extracted a single canonical
  validator, `tools/validate-board.py`, and made **both** consumers use it: `init.sh` now calls it
  as a CLI (identical success/failure lines and stderr contract) and `tools/tasks-lock.py` imports
  its `validate(data, schema) -> list[str]` in-process while holding the lock, before the atomic
  `os.replace`. This deletes the partial hand-rolled fallback in `tasks-lock.py` that silently
  accepted boards `init.sh` rejected (e.g. a non-boolean `sdd`, malformed `slices`). The validator
  prefers `jsonschema.Draft7Validator` when importable and otherwise runs the **complete**
  zero-dependency structural check (required keys, types, id patterns, enums, owner defaults,
  slices rules, and the sliced-`done` cross-field invariant) — the exact behaviour `init.sh`
  carried before, now shared verbatim so both paths accept/reject identically. Shipped executable
  by `harness-install.sh` and asserted by `tests/test_install.sh`.
- **Reject non-finite / negative lock timeouts (Codex #46 r2 P2, id 3649182846).** `argparse`'s
  `float()` accepted `--timeout nan`/`inf`, which poisoned the deadline arithmetic (`nan` makes
  `monotonic() >= deadline` always False → unbounded wait against a contended lock; `+inf` is an
  infinite bound). The helper now validates the timeout is **finite and non-negative** up front and
  exits non-zero with a clear message before entering the poll loop, restoring the bounded-
  acquisition contract (R5).
- **Minimal-diff status writes preserve existing board formatting (Codex #46 r3 P2, id 3649236637).**
  `set-status` now patches ONLY the addressed object's `"status"` value token in the original file
  text, leaving every other byte untouched, instead of parsing → `json.dumps(indent=2)` →
  re-serializing (which rewrote unrelated entries — e.g. expanding a sibling feature's inline
  `depends_on` array — on any board not already `indent=2`-canonical). This restores the promised
  serial byte-equivalence (R6) and keeps Git diffs / merge-conflict surface minimal, exactly when
  E15 introduces parallel branches. The result is still `json`-parsed and schema-validated through
  the shared `tools/validate-board.py` before the atomic `os.replace`, so an invalid outcome (bad
  id, illegal status, sliced-`done` invariant) still fail-stops with the board intact. The
  `apply --mutator` path is unchanged (external mutators may alter arbitrary structure).
- **Ignore the source-layout board lockfile (Codex #46 r3 P2, id 3649236638).** The
  `state/tasks.json.lock` ignore was seeded only into an installed consumer's `.harness/.gitignore`.
  In this source repo the documented `python3 tools/tasks-lock.py set-status …` creates the lock at
  root-relative `state/tasks.json.lock`, which the root `.gitignore` did not cover — dirtying the
  worktree. Added `/state/tasks.json.lock` to the repo root `.gitignore` (the installed-layout
  `.harness/.gitignore` entry is unchanged).
- **Canonical board + lock across git worktrees (Codex #46 r4 P1, id 3649274119).** The E15
  F02/F03 parallel-fix flow runs each fix in its OWN linked git worktree. Previously
  `tools/tasks-lock.py` resolved the board (and its lockfile) relative to whatever worktree it
  ran in, so each worker read/wrote a **different** worktree-local `state/tasks.json` and contended
  on a **different** `state/tasks.json.lock` inode — the `flock` did not serialize cross-worktree
  writers, so R1's no-lost-update guarantee was absent in exactly the scenario the epic targets.
  The helper now resolves **both** the board and the lockfile to the **single canonical location in
  the MAIN working tree**: precedence is (1) explicit `HARNESS_DIR` override, else (2) when inside a
  git repo/worktree, the main worktree root via `git rev-parse --git-common-dir` (its parent),
  re-applying the source-vs-installed subpath (computed relative to `git rev-parse --show-toplevel`)
  under that root, else (3) the prior `__file__` self-location. Git runs via `subprocess` with the
  helper's own directory as cwd and a bounded timeout; **any** git failure (not a repo, git absent,
  timeout, unexpected layout) degrades to (3) — never crashes, never blocks. Every worker in every
  worktree now shares one board and one lock inode, so concurrent writers from different worktrees
  cannot lose an update.
- **Locate the status token STRUCTURALLY by id, not by textual key order (Codex #46 r4 P2, id
  3649274120).** The minimal-diff `set-status` writer found the target's status as the first
  `"status"` at-or-after the `"id"` match. JSON imposes no key order, so a board that orders
  `status` **before** `id` in an object made the patch land on the **next** object's status —
  silently transitioning the wrong task while validation still passed. The writer now resolves the
  addressed object **structurally by id**: it anchors on the unique `"id": "<target>"`, delimits
  THAT object's character span with a brace-aware, string-literal-aware scan, and replaces only the
  `status` value token that lives at object depth 1 inside that span (a nested slice's status is
  never mistaken for the object's own). The minimal-diff property is preserved (only the addressed
  status token changes; unrelated inline arrays/formatting untouched) and the reparsed result is
  still schema-validated through the shared `tools/validate-board.py` before the atomic `os.replace`.
- **Run git worktree discovery from INSIDE the worktree in the source layout (Codex #46 r5 P1, id
  3649327432).** The canonical-board resolution (id 3649274119) ran both `git rev-parse` calls with
  `os.path.dirname(self_dir)` as cwd. In the **installed** layout the self-located harness dir is
  `<root>/.harness`, whose parent (`<root>`) is still inside the repo, so discovery worked and the
  R12 test passed. In the **source** layout the harness dir **is** the worktree toplevel, so its
  parent is the repo's PARENT — git ran OUTSIDE the worktree, `--git-common-dir` / `--show-toplevel`
  failed (or resolved a different repo), and the helper fell back to the LINKED worktree's own board;
  `set-status` then mutated only the linked copy while the MAIN board stayed unchanged, defeating the
  shared-board/shared-lock guarantee (R12) in the exact parallel-worktree scenario. Git discovery now
  runs from `os.path.dirname(os.path.abspath(__file__))` (the helper's `tools/` dir), which is inside
  the current worktree in **both** layouts, so source and installed resolve the main worktree
  identically. The R12 behavioural test now also covers the source layout (harness dir == worktree
  toplevel) with a real linked `git worktree`, asserting the transition lands on the MAIN board and
  contends on the MAIN `state/tasks.json.lock`; it fails against the old `dirname(self_dir)` cwd and
  passes after the fix.
- **`init.sh` rejects installs that can't run the lock helper (Codex #46 r6 P1, id 3649368481).**
  Since this feature makes `python3 tools/tasks-lock.py` the **mandatory** `set_status` write path,
  a python3-less install that previously warned-and-continued (`⚠️ python3 not found — skipping …`)
  would report "environment ready" yet fail on the first Orchestrator transition with
  `python3: not found`. The local-backend gate now **hard-fails** (non-zero, clear message) when
  `python3` is absent, and additionally verifies the stdlib **`fcntl`** module the lock helper needs
  is importable — so an unsupported interpreter is caught at `init.sh` time, not mid-transition.
  `tests/test_board_lock.sh` gains a case that runs `init.sh` under a python3-less `PATH` and asserts
  the non-zero exit with a message naming python3 and the reason.
- **Preserve the TaskStore file mode across the atomic replace (Codex #46 r6 P2, id 3649368484).**
  The guarded write created a fresh temp file (per the process umask) and `os.replace`d it in, which
  reset the board's permission bits — silently widening a `0600` board to `0644` (exposing data) or
  narrowing a shared `0664` board (breaking another account's later writes). The helper now copies
  the original board's mode (`stat.S_IMODE(os.stat(board).st_mode)`) onto the temp file **inside the
  lock, before the replace**, preserving fail-stop semantics. `tests/test_board_lock.sh` asserts a
  `0600` board stays `0600` and a `0664` board stays `0664` across a `set-status`.
- **Fail SAFE on canonical-board resolution; never a silent wrong-board write (Codex #46 r6 P1, id
  3649368478).** Under `git init --separate-git-dir` or a submodule, the main worktree path is
  **provably unrecoverable** from a linked worktree (`git rev-parse --git-common-dir` reports the
  separate metadata dir, whose parent is not the main worktree, and git stores no back-pointer to
  the primary working tree). The previous auto-discovery either resolved `HARNESS_DIR` to the
  boardless metadata dir (`board not found`) or silently fell back to the linked worktree's OWN
  board — a silent wrong-board write defeating the shared-board guarantee. Resolution is now
  strict-precedence and fail-safe: **(1)** explicit `HARNESS_DIR` override [highest precedence, set
  by the F03 `/sdd-fix-parallel` coordinator]; **(2)** best-effort auto-discovery for the standard
  `.git` worktree layout — **accepted only when the canonical board actually exists** there
  (`<canonical>/state/tasks.json`); **(3)** otherwise, when running inside a **linked** worktree,
  a **loud non-zero fail** with an actionable message demanding an explicit `HARNESS_DIR` (never a
  silent fall-back to the linked worktree's own board), while the ordinary non-worktree / serial
  `/sdd-next` case keeps the `__file__` self-location. Standard-layout worktrees still auto-resolve;
  exotic layouts fail safe; the coordinator's `HARNESS_DIR` injection makes ALL layouts correct.
  `tests/test_board_lock.sh` gains **R12sgd**: from a `separate-git-dir` linked worktree, a
  `set-status` with **no** `HARNESS_DIR` exits non-zero with the actionable message while the main
  board AND the linked worktree's own board stay byte-unchanged, and the same call **with**
  `HARNESS_DIR=<main>` (the coordinator path) lands on the main board. The spec's **R12** and the
  F03 brief (`progress/inbox/E15-F03.md`) are updated to require the coordinator to inject
  `HARNESS_DIR`.
- **Distinguish linked worktrees from separate-git-dir primaries (Codex #46 r7 P2, id 3649430729).**
  `_in_linked_worktree()` detected a linked worktree by comparing the common `.git` dir's **parent**
  with the worktree toplevel. But a **PRIMARY** checkout made with `git init --separate-git-dir`
  (or a submodule primary) also keeps its common dir OUTSIDE the working tree, so that comparison
  returned `true` and misclassified the primary as linked — combined with a failed canonical
  board-existence check, ordinary **serial** `set-status` then exited demanding `HARNESS_DIR`, so
  plain serial orchestration could not transition tasks in that layout without an undocumented
  override. Detection now compares `git rev-parse --git-dir` with `git rev-parse --git-common-dir`
  (both realpath-normalized): **equal ⇒ any primary checkout** (colocated, separate-git-dir, or
  submodule) ⇒ NOT linked ⇒ the serial self-location fallback applies with no spurious `HARNESS_DIR`
  demand; **distinct ⇒ a genuine linked worktree** ⇒ the existing loud-fail-if-no-canonical-board
  behavior is unchanged. Any git failure still degrades to not-linked / self-location — never
  crashes, never blocks. `tests/test_board_lock.sh` gains **R12sgdp**: a `separate-git-dir` PRIMARY
  checkout runs `set-status` with **no** `HARNESS_DIR` and must succeed and transition its own board
  (fails on the old parent-comparison logic, passes on the git-dir-vs-common-dir logic); the R12sgd
  linked-worktree loud-fail and the R12wt/R12src worktree cases stay green.
- **Common-dir remapping is now reserved for genuine linked worktrees (Codex #46 r8 P1, id
  3649460575).** `_canonical_harness_dir()` ran the `--git-common-dir` → main-worktree-root remap
  unconditionally, including for **PRIMARY** checkouts. In a primary made with
  `git init --separate-git-dir`, the parent of the (external) metadata dir is an **unrelated**
  directory — and if that directory happened to hold another harness board, the
  board-existence check ACCEPTED it as canonical, so `set-status` silently mutated that unrelated
  board while the real checkout stayed stale (reproduced: checkout still `pending`, metadata-parent
  board flipped to `in-progress`). A primary checkout already **is** the main working tree and has
  nothing to remap, so the remap is now gated on `_in_linked_worktree()`: primaries always
  self-locate, and common-dir remapping applies only to a genuine linked worktree. Cross-worktree
  canonical resolution (R12wt/R12src), the separate-git-dir linked loud-fail (R12sgd) and the
  separate-git-dir primary serial path (R12sgdp) are unchanged. `tests/test_board_lock.sh` gains
  **R12sgdx**: a `separate-git-dir` primary whose metadata dir sits **inside a decoy harness dir
  with its own board** must transition its OWN board and leave the decoy byte-unchanged with no
  lockfile created there (fails on unconditional remapping, passes once gated).
- **`python3` documented as a local-backend prerequisite in `AGENTS.md` (Codex #46 r8 P2, id
  3649460576).** The r6 P1 turned `init.sh`'s python3 check from warn-and-continue into a hard
  fail, which — because rule 1 halts all work on a non-zero `init.sh` — makes python3 a
  prerequisite for *any* harness work on the local backend, not just for locked status writes. The
  breaking dependency change was recorded here but not on the entrypoint agents actually read;
  `AGENTS.md` rule 1 now states the `python3` + stdlib `fcntl` requirement, when it became
  mandatory, and the remedy.
- **Invoke the Bash-only `init.sh` with `bash` in the R14py3 test (Codex #46 r9 P1, id
  3649498024).** `tests/test_board_lock.sh` ran the python3-less gate check as `sh ./init.sh`.
  `init.sh` declares `#!/usr/bin/env bash` and uses `set -o pipefail`, so wherever `/bin/sh` is
  **dash** — typical Ubuntu CI — the shebang is bypassed and the script aborts at line 8 with
  `Illegal option -o pipefail`, **never reaching the python3 gate**. The run still exited non-zero
  (so the must-fail assertion passed vacuously) but printed no python3 message, so the two message
  greps failed and the configured `test_board_lock.sh` suite went **red on CI while passing on
  macOS**, where `/bin/sh` is bash in POSIX mode and does support `pipefail`. The case now invokes
  `bash ./init.sh` and additionally requires `bash` to be reachable through the PATH shim (else it
  skips cleanly). Verified by reproducing the dash condition: `sh` → `Illegal option -o pipefail`
  with zero python3 mentions; `bash` → the exact hard-fail message the assertions expect.
- **Restrict id resolution to real task objects (Codex #46 r9 P2, id 3649498027).** The
  minimal-diff writer anchored on the **first textual** `"id": "<target>"` in the whole document.
  The board schema permits additional properties, so a board may carry an extension object (a
  mirror record, a cache entry) whose `id` equals a real feature or epic id; if it appeared earlier
  in the file and had a `status`, `set-status` silently updated **that** object and left the
  addressed task unchanged — and the result still schema-validated, so nothing surfaced the wrong
  write. Resolution now **walks the board structurally** — root → `epics[]` elements → each epic's
  `features[]` elements, matching only a **direct** `id` member at each level — so only a genuine
  epic or feature is addressable and anything outside those two arrays is invisible. The string
  mask backing the brace/bracket scans is computed once per resolution and threaded through
  (previously recomputed per call), keeping resolution linear rather than quadratic on large
  boards. `tests/test_board_lock.sh` gains **R13ext**: a board with colliding-id extension objects
  both **before** `epics` and **nested inside** the epic must transition the real feature (and the
  real epic), leave both decoys `synced`, and still change exactly one status token.
- **Duplicate `status` member fails STOP instead of silently no-opping (Codex #46 r10 P2, id
  3649544829).** JSON permits duplicate members and `json.loads` keeps the **last**, while a
  first-match text patch rewrites the **first** — so on such a board the helper exited 0 having
  persisted a file whose **effective** status never changed, and post-write validation still
  passed. The sole supported write path could therefore silently drop a requested transition. The
  writer now refuses to patch an object carrying more than one direct `status` member, exiting
  non-zero with a message naming the id and the count, board byte-unchanged (R4 semantics).
  Relatedly, object **selection** now reads a duplicated `id` as its **last** value, matching
  `json.loads`, so the text walk can never select an object whose effective id differs.
  `tests/test_board_lock.sh` gains **R13dup**.
- **Preserve board ownership across the atomic replace (Codex #46 r10 P2, id 3649544831).** The
  mode copy added in r6 carried permission bits but not ownership. In a multi-account checkout the
  board is group-owned so several accounts can write it via the `0664` group bit; without setgid
  inheritance on the directory the temp file takes the **current** writer's group, so `os.replace`
  silently re-grouped the board and locked the other accounts out of the mandatory write path. The
  helper now also copies the original `st_uid`/`st_gid` onto the temp file inside the lock.
  Best-effort by construction — `chown` is privileged in the general case, so an `EPERM` refusal
  (or a platform without it) is swallowed rather than failing the write; the mode copy already
  covers the common single-owner case.
- **Document the linked-worktree fail-loud branch in `store/local.md` (Codex #46 r10 P2, id
  3649544832).** The local-backend contract still described resolution as "works from any worktree,
  resolves the main board automatically", which no longer matched the fail-safe behavior: from a
  **linked** worktree under `separate-git-dir`/submodule layouts the helper deliberately exits
  non-zero demanding an explicit `HARNESS_DIR`, so anyone driving it by hand outside the
  `/sdd-fix-parallel` coordinator hit an undocumented hard failure. The contract now states the
  corrected precedence (primary checkouts are never remapped — they already *are* the main working
  tree), the one case that exits non-zero, and the `HARNESS_DIR=…` invocation that resolves it.

## [0.30.0] — 2026-07-10

### Added — ✨ Jira mirror completed via REST API + Bearer PAT, no MCP (E12-F01)
- **Filled the recognized `jira` stub** in `tools/sync-board.mjs` (rather than forking a
  second Jira code path): the shared `jira`/`azure-boards` stub is split so `azure-boards`
  stays a recognized no-op stub while `jira` runs a real one-way projection of
  `state/tasks.json` onto a Jira **Server / Data Center** project. Transport is the **Jira
  REST API only** (`/rest/api/2/…`, dependency-free built-in `fetch`), authenticated with an
  `Authorization: Bearer <PAT>` header — **never MCP**, so it works inside MCP-restricted
  enterprises. Jira **Cloud** (Basic auth) is out of F01 scope, documented as a future
  extension.
- **PAT hygiene** — the PAT is resolved from the **`JIRA_PAT`** env var (precedence) else a
  gitignored **`pat_file`** (default `jira.pat`, resolved under the harness dir ⇒
  `.harness/jira.pat` in a consumer, trimmed); it is **never** written to
  `state/tasks.json`, `harness.config.yaml`, logs, or any committed file. Config
  (`base_url`/`project_key`) is validated and the PAT resolved **before** any network call
  (fail-closed); a missing PAT or missing config exits non-zero naming the requirement, and a
  Jira **401/403** exits non-zero with an actionable, PAT-free message.
- **Configurable mapping** — harness epics → Jira **Epic** and features → **Story** by
  default, overridable via `mirror.board.issue_type_map`; feature status → Jira workflow state
  via the provider-neutral `mirror.board.status_map` (identity default), transitioned in
  place. Reconcile is **idempotent** (each feature matched by a stable `harness:<id>` label —
  a re-run updates rather than duplicating). `assignee` is a recognized **no-op for `jira`**
  in F01 (owner→assignee deferred to E10-F03). `--dry-run` prints intents and mutates nothing.
- **Hardened PAT log hygiene + transition matching (Codex #44 r2 P2 ×2)** — Jira response
  bodies for **non-401/403** errors are now scrubbed via a `redactSecret(text, PAT)` helper
  before hitting stderr, so a bad-URL / debug-proxy body that echoes the `Authorization`
  header can never print `Bearer <PAT>` (redacted to `Bearer ***REDACTED***`). Status
  transitions are now matched by **destination `to.name === wantState` only** (the
  match-by-action-`name` fallback is removed): a transition whose action name matches but
  lands on a different state can no longer be selected, and when nothing lands on the mapped
  state the issue is left unchanged with a "no matching transition" report instead of a false
  success.
- **Config seed + gitignore** — `harness-install.sh` seeds the inert Jira `mirror.board` keys
  (`base_url`/`project_key`/`pat_file`/`issue_type_map`) and append-seeds the default PAT-file
  path into `.harness/.gitignore` so a provisioned PAT can never be committed by default;
  `tests/test_install.sh` asserts the executable tool ships and the PAT file is gitignored.
- **Docs pinned** — `store/board-mirror.md` gains a **jira contract** section (Server/DC REST
  + Bearer PAT, Cloud out of scope, `JIRA_PAT`/`pat_file` precedence, issue-type + status
  maps, REST-only / no-MCP, one-way, assignee deferral); `store/jira.md` cross-references it
  and clarifies the implemented **mirror** vs the still-stub **backend**.
- **Regression guardrails** — `tests/test_mirror.sh` gains behavioral `jira` cases against a
  stubbed recording REST endpoint (REST-only / no-MCP, single code path, Bearer PAT header,
  env/file PAT precedence, fail-closed missing-PAT/missing-config, idempotent reconcile,
  issue-type + status maps, assignee no-op, one-way, `--dry-run`, 401/403, PAT-never-leaks,
  docs pin). Assertions are behavior/shape only — no exact-VERSION pin and no diff of
  DO-NOT-TOUCH files against `main`.
- **Optional `mirror.board.epic_name_field`** (Codex #44 P2) — an additive, inert-by-default
  Jira Server/DC "Epic Name" custom field id (e.g. `customfield_10011`). When set, the epic
  `POST /issue` payload carries it (= the epic summary) so Server/DC projects that require
  Epic Name on the create screen don't 400 and halt the sync; empty/absent ⇒ omitted
  (unchanged default). Epic-only, create-only. Seeded inert in `harness.config.yaml` +
  `harness-install.sh`, documented in `store/board-mirror.md`, guarded by `tests/test_mirror.sh`.

## [0.29.0] — 2026-07-10

### Added — ✨ GitHub Projects (v2) mirror completed via `gh` CLI, no MCP (E11-F01)
- **Strengthened fail-closed preflight** in `tools/sync-board.mjs` for the `github-projects`
  provider — before any board-mutating call it verifies `gh` is present, is at least
  `2.31.0` (the first release with stable `gh project` Projects-v2 subcommands), and that its
  token carries the required `project` + `repo` scopes (via `gh auth status`). Any failure
  exits non-zero with an actionable message naming `gh` and the Projects-v2 / scope
  requirement, so a preflight failure never leaves the board half-written. Transport stays
  **`gh` CLI only — never MCP**; the inert-default (empty provider ⇒ no `gh` contact) and the
  config-first validation order are preserved.
- **Pinned contract in docs** — `store/board-mirror.md` now states the supported surface is
  **GitHub Projects (v2)** (Classic unsupported), names the minimum `gh` version (`2.31.0`)
  and the `project` + `repo` auth scopes, and reaffirms the `gh`-only / no-MCP transport and
  the one-way (`tasks.json` → board; agents never read the board) invariant.
- **Installer wiring asserted** — `tests/test_install.sh` now asserts a fresh install ships an
  **executable** `.harness/tools/sync-board.mjs` (the mirror tool was already copied +
  `chmod +x`'d by `harness-install.sh`; the assertion closes the wiring gap).
- **Regression guardrails** — `tests/test_mirror.sh` gains behavioral cases for the preflight
  (absent / too-old / under-scoped `gh` ⇒ non-zero, names `gh`, no board mutation), gh-only /
  no-MCP dispatch, single `github-projects` code path, idempotent reconcile, `--dry-run`
  mutates nothing, the one-way invariant (fixture-local `tasks.json` snapshot), and the docs +
  no-new-config-key checks. Assertions are behavior/shape only — no exact-VERSION pin and no
  diff of DO-NOT-TOUCH files against `main`.
- **Scope note** — F01 projects **status** only; the pre-existing `mirror.board.assignee`
  behavior is preserved untouched (no `owner → assignee` expansion — that is E10-F03).

## [0.28.0] — 2026-07-10

### Added — ✨ Ownership primitive: `owner` field in TaskStore + scoped `/sdd-next --mine` (E10-F01)
- **Optional `owner` field on epics and features** — `store/tasks.schema.json` now defines an
  optional string `owner` on both epic objects and feature objects. It is **additive and
  backward-compatible**: `owner` is not in any `required` array, so existing owner-free
  `state/tasks.json` files validate unchanged and no migration is needed.
- **Effective owner (feature wins)** — a feature's effective owner is its own `owner` when set,
  else its parent epic's `owner`, else unowned. Documented in `agents/orchestrator.md`,
  `docs/WORKFLOW.md`, and `store/local.md`.
- **Scoped `/sdd-next --mine`** — the Orchestrator contract adds an "Ownership & scoped
  selection" subsection: `--mine` selects only features whose effective owner equals the
  identity resolved from `workflow.identity` (`@me`/`self` → authed `gh` user via `gh api
  user`; else literal). Scoping is a filter layered on top of the existing `next()` gates —
  it never relaxes a gate. It is **owned-only** (no claim-on-select — that is E10-F02) and
  **fails closed** (unresolved identity or no owned actionable work ⇒ report + no state change,
  never widen to board-wide). Bare `/sdd-next` is unchanged board-wide selection.
- **`workflow.identity` config key** — new optional key in `harness.config.yaml` (empty default
  ⇒ solo/board-wide, today's behavior).
- **Installer wiring** — `harness-install.sh` generates the `--mine` scoped-selection front-end
  into every selected target's `/sdd-next` glue (Claude/OpenCode/Antigravity/Codex), byte
  identical; `tests/test_install.sh` asserts the wiring. New `tests/test_ownership.sh` behavior
  suite added to `verification.test_command`.
- The board mirror stays **one-way** — no agent reads the board for ownership; `state/tasks.json`
  is the single source of truth (invariant preserved).
- `VERSION` bumped 0.27.3 → 0.28.0 (installed body changed; **MINOR** per the versioning policy —
  additive/backward-compatible).

## [0.27.3] — 2026-07-10

### Fixed — 📝 Align draft-epic docs + re-validate after driller approval mutation (E09)
- **Driller re-validates after the approval mutation** — `agents/driller.md` R10 now states
  re-validation of `state/tasks.json` runs both **after seeding AND after the approval-branch
  mutation** (the `draft → planned` flip + `autonomous` stamp). That final post-mutation
  validation gates the completion report: a malformed state flip/stamp can no longer be
  reported as a successful drill. `tests/test_sdd_drill.sh` R10 asserts the post-mutation
  re-validation requirement.
- **WORKFLOW draft definition realigned to the drillable-minimum contract** — the epic
  lifecycle `draft` bullet in `docs/WORKFLOW.md` replaced the stale "title + business brief
  only" wording with the drillable-minimum five elements (matching `agents/planner.md`), so
  role files and workflow docs give coherent canonical guidance. `tests/test_sdd_plan.sh` R21
  asserts the coherence (drillable-minimum present, no stale "brief only").
- `VERSION` bumped 0.27.2 → 0.27.3 (installed body changed; PATCH per the versioning policy).
  Fixes Codex #39 r3 P2/P2.

## [0.27.2] — 2026-07-10

### Fixed — 🔒 Harden doc-critic write access + exact-line gitignore seeding (E09)
- **doc-critic granted `Write`** — the emitted `.claude/agents/doc-critic.md` shim now
  carries `Read, Grep, Glob, Write` (was read-only). The role writes an auditable
  `progress/<run>/doc-critic-<checkpoint>.md` note (R7); without `Write` the checkpoint
  left no file-based handoff. `Write` is the minimal, most-scoped grant (no Edit/Bash).
- **exact-line matching for seeded root `.gitignore` ignores** — the append-only loop now
  uses `grep -qxF` (whole-line) instead of `grep -qF` (substring), so a pre-existing
  `.gitignore` that mentions `AGENTS.local.md`/`CLAUDE.local.md`/`AGENTS.override.md`
  (or `.claude/settings.local.json`) only in a comment or negation still gets the real
  ignore line appended — a personal override can no longer slip through uncommitted.
- **Regression assertions** added to `tests/test_install.sh` for the doc-critic `Write`
  grant and the exact-line gitignore seeding (a comment-only mention still gets the real
  ignore added). `VERSION` bumped 0.27.1 → 0.27.2 (installed body changed; PATCH per the
  versioning policy). Fixes Codex #39 r2 P2/P3.

## [0.27.1] — 2026-07-10

### Fixed — 🔧 Wire the doc-critic checkpoint into the installer-generated glue (E09)
- **doc-critic spawnable in the installed Claude workflow** — `harness-install.sh` now
  emits a `.claude/agents/doc-critic.md` subagent shim (pointing at the canonical
  `.harness/agents/doc-critic.md`) and adds the `Task` tool to the emitted `architect`
  shim, so the advertised pre-`spec-ready` `target-type=feature-spec` checkpoint is
  actually executable on the primary `/sdd-next` path. `doc-critic` is added to
  `HARNESS_CLAUDE_SHIMS` so it participates in scoped deselect removal.
- **doc-critic mirrored into every front-end registry** — the OpenCode `opencode.json`
  agent set and the Antigravity `.agents/agents/` persona set now include `doc-critic`,
  keeping all front-ends consistent with the Claude shims.
- **`/sdd-plan` glue mirrors the drillable-minimum + checkpoint** — the installed
  `/sdd-plan` command body now requires the five drillable-minimum `epic.md` elements
  (business brief, epic-level success criteria, technical considerations/non-goals,
  cross-epic dependencies and boundaries, pointers to relevant shared ADRs) and runs the
  `target-type=plan-output` doc-critic checkpoint before re-validation; `/sdd-drill`
  likewise runs its `target-type=epic-decomposition` checkpoint.
- **Regression assertions** added to `tests/test_install.sh` for the doc-critic shim,
  the architect `Task` tool, the antigravity `doc-critic` persona, and the `/sdd-plan` +
  `/sdd-drill` drillable-minimum + checkpoint glue. `VERSION` bumped 0.27.0 → 0.27.1
  (installed body changed; PATCH per the versioning policy). Fixes Codex #39 r1 P1/P2.

## [0.27.0] — 2026-07-10

### Added — ✨ Per-developer local prompt override convention (E09-F02)
- **Generated entrypoint guidance** — `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` managed
  marker blocks now mention the optional `AGENTS.local.md` local prompt override. The
  guidance is conditional, additive, and states that committed instructions remain
  authoritative on conflict.
- **Installer ignore seeding** — project-root `.gitignore` seeding now includes
  `AGENTS.local.md`, `CLAUDE.local.md`, and `AGENTS.override.md` through the existing
  append-only/idempotent seed path, preserving user-authored ignore entries.
- **Docs and examples** — `docs/CONFIG-LAYERING.md` documents the personal prompt layer,
  native local files for Claude Code and Codex, fresh worktree caveats, and per-tool
  local-file differences. `umbrella.gitignore.example` includes the same local prompt
  ignore entries for shared-spec repository roots.
- **Verification** — `tests/test_install.sh` covers local prompt ignore seeding,
  idempotence, generated entrypoint wording, docs coverage, umbrella example parity, and
  this SemVer MINOR bump. `VERSION` bumped 0.26.0 → 0.27.0.

## [0.26.0] — 2026-07-10

### Added — ✨ Doc-critic: advisory review pass over harness-generated docs (E09-F01)
- **New portable Doc-critic role (`agents/doc-critic.md`)** — an automated, advisory
  sub-agent that reviews harness-generated planning documents and specs at three defined
  checkpoints. It accepts a `target-type` argument (`plan-output`, `epic-decomposition`,
  `feature-spec`) and flags only issues that would cause real downstream problems across
  completeness, consistency, clarity, scope, and YAGNI. Findings are advisory only: the
  generating agent applies fixes inline and proceeds, with a short note to `progress/<run>/`.
  On error or timeout the agent proceeds best-effort and records the skipped pass.
- **Planner checkpoint (`/sdd-plan`)** — after writing vision, architecture, ADRs, and
  seeded `epic.md` files, the Planner spawns the Doc-critic with `target-type=plan-output`
  and applies inline fixes. Each seeded `epic.md` must carry the drillable-minimum:
  business brief, epic-level success criteria, technical considerations / restrictions /
  non-goals, cross-epic dependencies and boundaries, and pointers to relevant shared ADRs.
- **Driller checkpoint (`/sdd-drill`)** — after decomposing the epic (feature entries,
  `epic.md` feature table, inbox briefs, ADR deltas), the Driller spawns the Doc-critic
  with `target-type=epic-decomposition` and applies inline fixes.
- **Architect checkpoint (before `spec-ready`)** — after drafting a feature's four-file
  spec, the Architect spawns the Doc-critic with `target-type=feature-spec` and applies
  inline fixes before handing off to the human gate.
- **Installer wiring** — `agents/doc-critic.md` is copied into `.harness/agents/` on every
  install/upgrade via the existing `copy agents` step.
- **Verification** — `tests/test_doc_critic.sh` covers R1–R18 (static grep contract
  assertions over the role and checkpoint wiring); `tests/test_install.sh` asserts the
  role is installed and the Planner/Driller/Architect contracts reference it. Wired into
  `verification.test_command`.
- **Docs** — `docs/WORKFLOW.md` gains a distinct `## Doc-critic checkpoints` section
  documenting the three checkpoints and the advisory/inline-fix/best-effort nature.
- Purely additive: no change to `store/tasks.schema.json`, no new status value, no new
  human gate, and no retro-fit of existing specs. `VERSION` bumped 0.25.0 → 0.26.0.

## [0.25.0] — 2026-07-01

### Added — ✨ Codex CLI front-end (`codex` agent key)
- **`codex` is now a selectable front-end (`harness-install.sh`).** Added to `AGENT_KEYS`
  (`claude gemini opencode antigravity codex`), so it appears in the interactive picker,
  is individually selectable via `--agents=codex` / `HARNESS_AGENTS`, and persists to
  `.harness/.agents` like every other agent.
- **GLOBAL `/sdd-*` prompts (§5d).** Codex CLI has no project-local custom-command
  mechanism, so its only slash-command surface is the machine-global prompts dir
  `${CODEX_HOME:-$HOME/.codex}/prompts/`. When `codex` is selected the installer stamps
  the five `sdd-next`, `sdd-new`, `sdd-plan`, `sdd-drill`, `sdd-fix` prompt bodies
  there — byte-identical to the Claude/OpenCode/Antigravity copies (same `CMDDIR` source).
  Codex surfaces each `<name>.md` as the slash command **`/prompts:<name>`** (namespaced
  under `/prompts:`, not top-level `/<name>`). This is the one front-end whose glue lands
  **outside** `$TARGET`; the bodies resolve their paths against `.harness/` of whatever
  repo Codex launches in, so a single global copy drives every target. Honors `$CODEX_HOME`,
  and when neither `CODEX_HOME` nor `HOME` is set (minimal CI) the Codex step is skipped
  with a warning instead of aborting the install under `set -u`.
- **No new entrypoint pointer.** Codex reads the always-written `AGENTS.md` from the repo
  root natively, so a `codex`-only install needs no dedicated entry file.
- **Non-destructive install.** The global prompts dir is a user-owned namespace, so a
  same-named file that differs from the harness body — an original OR a later user edit —
  is backed up to `<name>.md.pre-harness.bak` and warned about before the harness copy is
  written. The backup refreshes whenever the current contents change, so a post-install
  edit is captured too (never silently lost); a routine re-install where the file is
  already the identical harness body neither warns nor churns the backup.
- **Pristine-only deselect (§7).** Dropping `codex` reclaims only byte-pristine global
  prompts (a user-edited `/prompts:sdd-*` prompt survives), mirroring the `opencode.json` /
  Antigravity `cmp -s` contract, and prunes the prompts dir only when empty.
- **Tests (`tests/test_install.sh`).** Sandboxes `CODEX_HOME` for the whole suite (never
  touches the real `~/.codex`); adds `--agents=codex` (global-prompts-only + byte-identical
  to peers) and codex-deselect (pristine reclaim, edit-preserving, warns) cases; extends the
  ALL-default and registry-key coverage to include `codex`.

## [0.24.0] — 2026-07-01

### Added — ✨ Board mirror: status-gated issue assignee (`mirror.board.assignee`)
- **`assignee` config key (`tools/sync-board.mjs`)** — the board mirror can now fill the
  provider's assignee/owner field from a new, provider-neutral `mirror.board.assignee` key.
  Assignment is **status-gated**: when `assignee` is set the mirror **owns** the Assignees
  field for its items and reconciles it to the exact desired set every sync — a started item
  (`in-progress`/`in-review`/`done`) ends up with *exactly* the configured login (any other
  assignee removed), a not-started one (`pending`/`spec-ready`) with none — so the board
  reflects who owns each item *right now* and a teammate's stale assignment from a shared
  `@me` sync is cleared whether the item is in flight or regressed. Empty (the default) ⇒ the
  mirror never touches assignees, so a preserved config behaves exactly as before. Implemented
  for the `github-projects` provider; the `jira`/`azure-boards` stubs ignore it until wired.
- **Dynamic `"@me"` resolution** — `assignee: "@me"` (or `"self"`) resolves at sync time to
  the authed `gh` user via `gh api user`, so a shared-repo config reflects whoever runs the
  sync instead of hard-coding one login. Resolution failure degrades to "skip assignment this
  run" rather than erroring, and assignment is idempotent (the API call is skipped when the
  item already has the right assignee).
- **Docs + template parity** — `store/board-mirror.md` documents the key as provider-neutral
  (each tracker maps it to its own assignee/owner field) and the stub-provider guide tells
  new providers to honor it; `harness.config.yaml` and the installer's `migrate_config` mirror
  template both gain the commented `assignee: ""` default (append-only, existing configs
  preserved). `tests/test_mirror.sh` gains coverage: `@me` resolution + status-gated
  assign/unassign, and the assignee-unset back-compat no-op. **`VERSION` 0.23.1 → 0.24.0**
  (MINOR: new backward-compatible capability). Upstreamed from a downstream install so the
  canonical body now owns it and future upgrades no longer clobber a hand-carried copy.

## [0.23.1] — 2026-07-01

### Added — ✨ claude-mem-context block
- **Memory context block (`AGENTS.md`)** — adds `claude-mem-context` to the orchestrator documentation to maintain memory of recent context.

## [0.23.0] — 2026-06-12

### Added — ✨ Installer agent picker: arrow-key + spacebar checkbox UI (E99-F01)
- **Cursor-driven checkbox picker (`harness-install.sh` `tui_select`)** — on a raw-capable
  interactive TTY the agent front-end selector now renders the four agent keys
  (`claude gemini opencode antigravity`) as a checkbox list: ↑/↓ (or `k`/`j`) move a `>`
  cursor, **Space** toggles the highlighted row's `[x]`/`[ ]`, **Enter** confirms (`q`/Esc
  also confirm the current selection). This replaces the awkward type-a-number toggle model
  as the preferred interactive path. Pre-check state still seeds from the saved
  `.harness/.agents` set (or ALL on a fresh install), and only the resolved sorted keys
  (one per line) reach stdout, so the captured `SELECTED` contract is unchanged.
- **Graceful fallback (`tui_capable`)** — a capability probe detects whether `stty` can save +
  enter + restore raw mode on an interactive TTY. When raw mode is unavailable (no `stty`,
  non-interactive / piped stdin, sandboxed), `resolve_agents` falls back to the existing
  numbered `toggle_select`. The install never hard-fails on a terminal that can't do raw mode.
- **Guaranteed terminal restore** — raw mode is entered with `stty` and UNCONDITIONALLY
  restored via an `EXIT`/`INT`/`TERM` trap (plus an explicit restore on the normal completion
  path), so Ctrl-C or quitting never leaves the user's terminal stuck in raw mode; the cursor
  is re-shown too. All prompts/UI go to **stderr**.
- **No behavior change off the interactive path** — the no-TTY "ALL agents" default and the
  `--agents=` / `HARNESS_AGENTS=` override path are untouched; the picker only changes the
  interactive presentation. Portable POSIX sh, **no new binary dependencies**. `VERSION`
  bumped 0.22.0 → 0.23.0 (MINOR). `tests/test_install.sh` gains an E99-F01 group asserting the
  picker + capability probe + fallback wiring (the numbered fallback is what the suite
  exercises non-interactively). `tests/test_sdd_fix.sh` R17 now checks the installer-SEEDED
  store (throwaway target) for "no pre-seeded E99" instead of the mutable live
  `state/tasks.json`, which this repo legitimately populates while dogfooding its own
  `/sdd-fix` lane (permanent-suite anti-pattern fix). No canonical `agents/*.md` role file is
  touched.

## [0.22.0] — 2026-06-12

### Added — ✨ Antigravity native support
- **Antigravity glue (`harness-install.sh` §5c)** — Google Antigravity (a Gemini-based
  agentic IDE) is now a first-class, selectable harness target. On every run (gated on the
  `antigravity` agent key), the installer stamps a workspace-local `.agents/` tree that POINTS
  at the canonical `.harness/agents/*.md` roles — it never forks, copies, or redefines a role
  body. Antigravity natively reads `<root>/.agents/{rules,agents,workflows}/*.md` (plural —
  the dir its current build scans).
- **Entrypoint rule (`.agents/rules/harness.md`)** — a thin rule that loads the harness for an
  Antigravity session (Antigravity does not auto-load `AGENTS.md`): it points at
  `.harness/AGENTS.md` (source of truth) and `.harness/agents/orchestrator.md` (entry role),
  mandates `.harness/init.sh` first, and documents the working model. The root `GEMINI.md`
  pointer block (already written by §4) also serves Antigravity as the in-repo entrypoint.
- **Personas (`.agents/agents/{orchestrator,architect,builder,reviewer,scout}.md`) —
  best-effort** — one per harness role, each carrying a `description` and a body that
  defers to `.harness/agents/<role>.md`, runs `.harness/init.sh` first (halt on non-zero), and
  hands off via `.harness/progress/` files — no copied role body. Bare-file persona discovery
  is unconfirmed, so the personas are written (cheap, possibly honored) but the harness does
  NOT claim they register as Antigravity subagents.
- **Workflows (`.agents/workflows/{sdd-next,sdd-new,sdd-plan,sdd-drill,sdd-fix}.md`)** — the
  same five SDD slash commands, COPIED from the shared command bodies (mirroring the OpenCode
  block) so they stay byte-identical to the Claude/OpenCode copies and never drift. Each
  already carries the `description` frontmatter Antigravity needs to register `/<name>`.
- **Durable working model** — the confirmed primitives are the `.agents/rules/` entrypoint rule
  + the `description`-gated `.agents/workflows/` slash commands + `.harness/progress/` files as
  the hand-off / isolation boundary (not a Task-tool-style spawn, not an asserted bare-file
  subagent registration); the personas above are a best-effort layer on top.
- **No new dependencies; harness-owned + idempotent** — the `.agents/` glue is regenerated each
  run (like `.claude/` / `.opencode/`); deselecting `antigravity` removes ONLY harness-owned
  files that are byte-identical to a freshly-generated stamp (pristine) — never a user file that
  merely shares a standard name, and never `rm -rf` of a user `.agents/` dir. `VERSION`
  bumped 0.21.0 → 0.22.0 (MINOR). `tests/test_install.sh` gains an Antigravity assertion group
  covering R1–R13; no canonical `agents/*.md` role file is touched.

## [0.21.0] — 2026-06-11

### Added — ✨ Selectable agent targets (interactive selection + re-prompt on update)
- **Declarative agent registry (`harness-install.sh`)** — the four selectable coding-agent
  front-ends (`claude`, `gemini`, `opencode`, `antigravity`) are modeled as a small registry
  (`AGENT_KEYS`); each EXISTING per-agent stamp block is now **gated** on selection rather than
  always running. The shared portable entrypoint `AGENTS.md` is never gated — it is always
  written and never removed.
- **Interactive selection (zero new deps)** — on an interactive TTY with no override, the
  installer presents a pure-`read` numbered toggle list pre-checked from the saved selection
  (or ALL on a fresh install) and stamps only the chosen agents.
- **Non-interactive override + back-compat** — `--agents=<csv>` / `HARNESS_AGENTS=<csv>` resolve
  the set without prompting (the override always wins; an unknown key aborts non-zero, naming the
  token, with no changes). No-TTY + no override still stamps **ALL** agents, preserving the
  historical behavior so existing CI is unchanged.
- **Persistence + re-prompt-on-update** — the resolved set is persisted to `.harness/.agents`
  (one sorted key per line; dot-prefixed to avoid colliding with the `.harness/agents/` role-bodies
  dir), beside `.harness/.harness-version`. Every re-run re-resolves and reconciles **decoupled
  from VERSION/upgrade detection**: an **added** agent is stamped, a **deselected** agent's
  harness-owned regenerated glue is deleted — **scoped to the specific generated files**
  (its pointer block, the `orchestrator/architect/builder/reviewer/scout` shims, the `sdd-*`
  commands, a generated `opencode.json`); user-authored files sharing `.claude/`/`.opencode/`
  are preserved and those dirs are pruned only when left empty. `opencode.json` is removed only
  when **byte-identical** to the generated stamp — any user edit (e.g. an added `model`/providers
  key) leaves it in place with a warning — and each removed path is warned about. `AGENTS.md` and the
  `.harness/` body are never removed. Deselecting `antigravity` is a **no-op** while its stamp
  is a placeholder (E07-F01), so a user-authored `.agent/` directory is never deleted.
  An existing install with **no** persisted `.harness/.agents` (a pre-0.21 install that stamped
  all front-ends) is treated as the **all-agents baseline**, so the first selective upgrade can
  actually remove the now-deselected glue instead of leaving it stale.
- **Docs + tests** — `tests/test_install.sh` gains an assertion group covering R1–R15 (selected-only
  stamping, no-TTY ALL default, explicit override + precedence, unknown-key rejection, persistence
  round-trip, an add+remove re-run at the same VERSION, and the legacy-upgrade baseline removal).

## [0.20.0] — 2026-06-11

### Added — ✨ Drift check on epic rollup (Scout re-validates remaining draft/planned epics)
- **Epic-done rollup formalized (`store/local.md`, `agents/orchestrator.md`)** — when every
  feature of an epic is `done`, the Orchestrator now **derives and persists** the epic's `done`
  status and **re-validates** `state/tasks.json` — additively, beside the existing
  feature-level rollup, mirroring its "derive, then persist" discipline. No new status value,
  no schema change (`done` was already an epic enum value).
- **Scout drift-check mode (`agents/scout.md`)** — on that epic rollup the read-only Scout
  re-validates the remaining `draft`/`planned`/`pending` epics against what the completed epic
  produced and writes a per-epic still-valid/stale findings file to
  `progress/<run>/scout-drift-<epic>.md`. Staleness uses concrete signals only — **(S1)** a new
  ADR contradicts the brief, **(S2)** the brief references a removed/renamed thing, **(S3)** an
  explicit `supersedes E0X` / `obsoletes E0X` marker — stale only when ≥1 fires. The Scout's
  **read-only** contract is preserved: it writes only to `progress/`, never `state/tasks.json`.
- **Orchestrator-applied demotion (`agents/orchestrator.md`)** — the Orchestrator (not the
  Scout) demotes a stale `planned`/`pending` epic to `draft` via `set_status` and re-validates.
  Demotion only ever moves an epic **backward**; `in-progress`/`done` epics are never demoted;
  re-drilling a demoted epic back to `planned` stays a manual `/sdd-drill` step, reported as a
  pointer with an optional flag-only `demoted on drift:` `epic.md` note. The no-op paths (no
  remaining planning-tier epics, or no architecture) emit a clear "nothing to re-validate" note
  and change nothing — this drift check never fails silently.
- **Docs + tests** — `docs/WORKFLOW.md` gains a distinct "Drift check on epic rollup" section;
  `tests/test_drift_check.sh` (POSIX sh + python3, zero new deps) is wired into
  `verification.test_command`.

## [0.19.0] — 2026-06-10

### Added — ✨ Architect ADR-citation contract (architecture.md mandatory-when-present input; specs cite the ADRs they touch)
- **Amended Architect contract (`agents/architect.md`)** — the Architect now **consumes**
  the planning tier's durable design. When `specs/architecture.md` + `specs/adr/NNNN-*.md`
  are **present**, they are a **mandatory input** alongside the inbox brief, and the
  Architect reuses the **F03-D7 hook** (the touched `ADR-NNNN` ids the Driller already
  recorded in the brief) as the seed. Every feature `.spec.md` it writes carries a
  **`## Architecture alignment`** section citing each touched `ADR-NNNN` + a one-line "how
  this honors it"; **`ADRs touched: none`** is the explicit, legitimate no-touch state; a
  divergence is **stated in the section** (never an authored ADR delta — that stays F03's
  job).
- **Graceful degradation** — `present` means the file exists **and** carries real content
  (a bare/template-stub counts as **absent**). When architecture is absent (legacy repo or
  `/sdd-new` altitude-3), the Architect records the absence and proceeds from the brief
  alone — no fabricated citation, no failure, section not required. Existing pre-contract
  specs stay valid (no retro-fit). The rule also applies to umbrella shared specs,
  orthogonal to the contract-artifact reference.
- **`## Architecture alignment` template section** — `specs/_templates/feature.spec.md`
  gains the section (between `## Business rules` and `## Acceptance criteria (EARS)`) with
  the `ADRs touched: none` fallback, so every new spec has a consistent, checkable slot.
- **Additive Reviewer clause (`agents/reviewer.md`)** — a new
  `## ADR-citation check (architecture-aligned specs)` section that fires **only where**
  `specs/architecture.md` + ≥1 ADR exist **and** the feature is `sdd: true`; it confirms
  the `.spec.md` has a `## Architecture alignment` section citing ≥1 `ADR-NNNN` or stating
  `ADRs touched: none`. A missing/empty section is a **soft flag**, not a hard reject; the
  clause does not fire for legacy/no-architecture features or `sdd: false` brief-only items.
- **Docs** — `docs/SPEC-FORMAT.md` documents the section + cite-your-ADRs rule;
  `docs/WORKFLOW.md` gains a distinct "Architecture-aligned specs (the Architect cites
  ADRs)" section placing the contract relative to `/sdd-plan` + `/sdd-drill`; `README.md`
  gains a one-line note that feature specs cite the ADRs they touch.
- **Verification** — `tests/test_architect_adr.sh` (wired into
  `verification.test_command`): grep contract assertions over the role/reviewer/template/docs,
  a temp-dir markdown fixture proving the `## Architecture alignment` shape (both citing an
  ADR and `ADRs touched: none`) is internally consistent, and a temp JSON store fixture
  proving the citation needs **no** `store/tasks.schema.json` change.
- Purely additive / consume-only: F02 `/sdd-plan`, F03 `/sdd-drill`, the ADR
  format/numbering, the architecture/adr templates, `store/tasks.schema.json`, and every
  `/sdd-*` command are unchanged; a repo with no `specs/architecture.md` behaves exactly as
  today.

## [0.18.0] — 2026-06-10

### Added — ✨ `/sdd-fix` lightweight fix lane (maintenance epic, brief-only `sdd: false` intake)
- **New portable Fixer role (`agents/fixer.md`)** — a sibling of Inception / Planner /
  Driller that is the **brief-only intake** for the lightweight fix lane. It seeds **one**
  `sdd: false` fix under a single reserved maintenance epic, carrying only a one-paragraph
  inbox brief, and **hands it off to the existing `sdd: false → Builder → Reviewer` loop**.
  It is a thin front-end over the existing F01 primitive: **no new Orchestrator routing, no
  new TaskStore status, and no `store/tasks.schema.json` change**. It seeds and hands off —
  it never specs and writes no production code itself.
- **Reserved maintenance epic convention (`E99`)** — `/sdd-fix` creates the maintenance
  epic on first use (`id: "E99"`, slug `maintenance`, title "Maintenance (hotfixes & minor
  fixes)", `status: "planned"`, `features: []`, plus `specs/epics/E99-maintenance/epic.md`)
  and re-identifies the **same** epic **by id `E99`** on every later run (never a second
  bucket, never a renumber). `E99` is a deliberately high reserved number that already
  satisfies the `^E[0-9]+$` schema pattern (no schema change); `planned` is a selectable,
  non-`draft` status so the `next()` gate returns its fixes.
- **Brief-only `sdd: false` fix seeding** — each fix is appended as the next-sequential
  `F##` strictly above the epic's max (append-only, no reuse) with `sdd: false`,
  `status: "pending"`, a one-line title, and a recorded `spec_path` (directory **not**
  created), stamped **`autonomous: true` by default** (runs end-to-end) with a `--gated`
  opt-out that stamps `autonomous: false`. Exactly one fix-oriented inbox brief is written
  at `progress/inbox/<id>.md` from `specs/_templates/inbox-brief.md` — never a feature
  `.spec/.plan/.tasks/.tests`, never a `spec_path` directory, never the Architect. The
  Fixer re-validates `state/tasks.json` against `store/tasks.schema.json` after each write
  and fail-stops on an invalid store.
- **New `/sdd-fix` slash command (`.claude/commands/sdd-fix.md`)** — the interactive
  wrapper that acts as Fixer, reads the description from `$ARGUMENTS` (STOP if empty),
  offers ≤3 text-only options (never images), seeds the `E99` fix, re-validates, and hands
  off to the existing `sdd: false` loop in-session. Generated by `harness-install.sh` into
  `.claude/commands/sdd-fix.md` (resolving `.harness/agents/fixer.md`) and mirrored to
  `.opencode/command/sdd-fix.md`.
- **Additive Builder/Reviewer clarifications (`sdd: false` only)** — `agents/builder.md`
  now states that for an `sdd: false` item with no `tasks.md` the Builder works from the
  inbox brief as its worklist and still writes a test proving the fix; `agents/reviewer.md`
  now states that for an `sdd: false` item the Reviewer verifies behaviourally + the fix's
  test and that its R-id traceability check does not apply when there are no R-ids. Both
  edits are strictly additive — the `sdd: true` four-file path is unchanged.
- **`sdd: false` routing split by `autonomous` (coherence fix)** — the Orchestrator's
  `pending + sdd: false` route is split in two: `autonomous: true` **sets the feature to
  `in-progress`** (so the Builder's Loop A `in-progress` precondition holds) then spawns
  the Builder directly → `in-review`; `autonomous: false` (e.g. `/sdd-fix --gated`)
  **parks at the human gate** (not actionable until a human approves), so `--gated` is a
  real opt-out instead of a no-op. `agents/builder.md`, `agents/fixer.md`,
  `store/local.md`, and `docs/WORKFLOW.md` are aligned to this split.
- **Docs + tests** — `docs/WORKFLOW.md` documents the lightweight fix lane alongside
  "Selective SDD" (adds no new status, no new routing); `README.md` carries a one-line
  `/sdd-fix` mention beside the existing `/sdd-new` / `/sdd-plan` / `/sdd-drill` /
  `/sdd-next` command family; `tests/test_sdd_fix.sh` (wired into
  `verification.test_command`) covers the role/command/builder/reviewer/docs contract plus
  a schema fixture for the seeded `sdd: false`/`autonomous: true` fix inside a `planned`
  `E99` epic; R15/R16 installer assertions live in `tests/test_install.sh`. `/sdd-fix` is
  a lighter sibling of the heavier `/sdd-plan` and `/sdd-drill` planning skills — it never
  writes a feature spec or runs a drill.

## [0.17.0] — 2026-06-10

### Added — ✨ `/sdd-drill` per-epic drill-down skill (decompose draft epic, ADR deltas, epic-level approval)
- **New portable Driller role (`agents/driller.md`)** — a sibling of the Planner and the
  Architect that operates at the per-epic altitude. It is the **consumer that decomposes,
  never specs**: it takes exactly one `draft` epic, seeds `pending` feature entries (ids,
  one-line intents, `depends_on`, `sdd: true`, `spec_path`) into the epic's `features`
  array, fills the `epic.md` feature table, and writes a per-feature inbox brief under
  `progress/inbox/` (recording the `ADR-NNNN` ids each feature must honor). It allocates
  feature ids as a next-sequential block strictly above the epic's max `F##` (append-only,
  no reuse) and never writes a feature `.spec/.plan/.tasks/.tests` or spawns the Architect.
- **ADR deltas** — the Driller appends per-epic design decisions as one-decision ADRs at
  `specs/adr/NNNN-<title>.md` (4-digit, above the max existing ADR number, no reuse),
  scoped one level below F02's whole-system upfront ADRs, and never rewrites or renumbers
  F02's existing ADRs.
- **Single epic-level approval (approve / keep-gated branches)** — the drill ends in
  exactly one human decision at the epic granularity, realized solely through F01's
  `planned` state and the existing `autonomous` flag (no new status, no new approval
  mechanism, no schema change). **Approve** flips the epic `draft → planned` and stamps
  `autonomous: true` on every seeded feature (all-or-nothing); **keep gated** flips the
  epic `draft → planned` while leaving every feature `autonomous: false` so each parks at
  the per-feature spec-approval gate. `/sdd-drill` is the only step that flips an epic
  `draft → planned`.
- **New `/sdd-drill` slash command (`.claude/commands/sdd-drill.md`)** — the interactive
  wrapper that acts as Driller, reads the `<epic-id>` from `$ARGUMENTS`, STOPs on an
  empty/missing/non-`draft` target, runs the ≤3 text-only adaptive Q&A, and presents the
  single approve / keep-gated decision.
- **Docs** — `docs/WORKFLOW.md` gains a "Per-epic drill-down (`/sdd-drill`)" note placing
  it between `/sdd-plan` and `/sdd-next`; `README.md` gains a one-line `/sdd-drill` mention.
- **Verification** — `tests/test_sdd_drill.sh` (wired into `verification.test_command`):
  grep contract assertions over the role/command/docs plus one python fixture proving the
  decomposed shape (a `pending` feature inside a `planned` epic, stamped `autonomous: true`,
  with the required root `project` field) validates against `store/tasks.schema.json`.
- Purely additive: `/sdd-new`, `/sdd-plan`, `/sdd-next`, Inception, and the Planner are
  behaviorally unchanged; no schema change. MINOR `VERSION` bump → `0.17.0`.

## [0.16.0] — 2026-06-10

### Added — ✨ `/sdd-plan` whole-project inception skill (vision + architecture + draft epics)
- **New portable Planner role (`agents/planner.md`)** — a sibling of Inception that
  operates at the whole-roadmap altitude. It is a **producer that never specs**: it
  writes `specs/vision.md`, `specs/architecture.md` + one-decision ADRs at
  `specs/adr/NNNN-<title>.md`, and seeds a block of `draft` epics — and it never writes
  a feature `.spec/.plan/.tasks/.tests`, never spawns the Architect, and never advances
  an epic past `draft` (F03 `/sdd-drill` owns the `draft → planned` flip).
- **New `/sdd-plan` slash command (`.claude/commands/sdd-plan.md`)** — the interactive
  wrapper that acts as Planner, reads the idea from `$ARGUMENTS`, runs the ≤3 text-only
  adaptive Q&A, and reports the seeded epics + artifact paths.
- **New artifact templates** — `specs/_templates/vision.md` (problem/users/outcomes/
  non-goals; complements `product.md`/`glossary.md`), `specs/_templates/architecture.md`
  (system shape + stable upfront decisions + ADR index by `ADR-NNNN` id), and
  `specs/_templates/adr.md` (one-decision context/decision/consequences).
- **Draft-epic seeding** writes each epic with `status: "draft"` and `features: []` —
  the schema-valid empty-features shape (no placeholder `F01`, the deliberate difference
  from `/sdd-new`'s new-epic altitude) — allocating ids as a next-sequential block above
  the current maximum, append-only, no reuse.
- Purely **additive / backward-compatible**: `/sdd-new`, `/sdd-next`, and Inception are
  unchanged; a repo that never runs `/sdd-plan` validates and behaves exactly as before.
  `docs/WORKFLOW.md` + `README.md` updated; new suite `tests/test_sdd_plan.sh` wired into
  `verification.test_command`.

## [0.15.0] — 2026-06-10

### Added — ✨ Human-readable telemetry durations (`HH:MM:SS`) + table total row
- **`tools/telemetry-report.py` renders every duration as `HH:MM:SS`** instead of
  raw seconds (e.g. `00:13:11` not `791s`), across the session view and all calendar
  rollups — per-phase durations and human-gate latency alike. Hours are not capped at
  24 (a multi-day gate latency shows e.g. `48:00:00`), keeping the format unambiguous.
- **Per-phase breakdown tables gain a `**total**` row** (count + summed duration) so
  the session total lives in the table itself, not only the prose bullet below it.
- The change is output-only and backward-compatible: the JSONL telemetry record format
  (`duration_s`/`human_latency_s` in seconds) is unchanged; only the rendered report
  differs. Suite `tests/test_telemetry.sh` updated (R4/R9/R10 expectations) with a new
  `R4b` covering the `HH:MM:SS` format and the total row.

## [0.14.0] — 2026-06-10

### Added — ✨ Epic lifecycle: `draft`/`planned` states + `next()` draft gate
- **Epic `status` enum gains `draft` and `planned`** (`store/tasks.schema.json`,
  purely additive): canonical lifecycle is now `draft → planned → in-progress → done`,
  with epic-level `pending` kept indefinitely as a **legacy alias of `planned`**
  (gating-equivalent). Feature/slice status enums are unchanged; existing consumer
  `tasks.json` files validate as-is — no migration.
- **`next()` draft gate** (normative in `store/local.md` + `agents/orchestrator.md`,
  the portable contract files): features of a `draft` epic are **never actionable** —
  the Orchestrator never selects them, regardless of the feature's own
  `status`/`sdd`/`autonomous`/`depends_on` (`autonomous: true` skips the *human
  approval* gate, not this *planning* gate). `pending`/`planned`/`in-progress`/`done`
  epics impose no new gate.
- **Warn-only `init.sh` invariant**: a `draft` epic containing a feature whose status
  is not `pending` prints a ⚠️ warning naming the epic and feature, and still exits 0
  (the gate already neutralizes it; schema validation does not reject it). The
  zero-dependency fallback validator accepts the new epic statuses.
- Docs/template updates: epic-lifecycle section in `docs/WORKFLOW.md`, lifecycle
  status comment in `specs/_templates/epic.md`, and a `store/board-mirror.md` note
  that epic statuses (including `draft`/`planned`) never map to board columns.
- New test suite `tests/test_epic_lifecycle.sh` (R1–R14), wired into
  `verification.test_command`.

## [0.13.0] — 2026-06-08

### Added — ✨ `mirror.board.status_map` — keep existing board columns via config
- **`tools/sync-board.mjs` now reads an optional `mirror.board.status_map`** mapping each
  harness status to a board **column name** (e.g. `pending: "Todo"`, `done: "Done"`).
  Omitted ⇒ identity columns (unchanged default). This lets a team whose board already has
  custom columns adopt the shipped mirror **without editing `sync-board.mjs`** — so a
  `harness-install.sh` upgrade never clobbers the customization. Backed by a new
  dependency-free nested-map YAML reader (`yamlGetMap`). Config migration seeds a commented
  `status_map` example into the `mirror:` block.

## [0.12.0] — 2026-06-08

### Added — ✨ Pluggable board mirror + generic post-write sync hook
- **`tools/sync-board.mjs`** — a generic, provider-pluggable one-way **mirror** that
  projects `state/tasks.json` onto an external project board (issue/work-item per feature,
  Status + Epic fields, closes done / reopens regressed). `tasks.json` stays the source of
  truth; the board is a downstream projection agents never read. **Inert by default.**
  - Provider chosen by `mirror.board.provider`: `""`/`none` ⇒ no-op exit 0;
    **`github-projects`** implemented (config-driven `owner`/`project_number`/`repo`, needs
    `gh`); **`jira`** + **`azure-boards`** recognized as no-op **stubs**. No org/repo/tool is
    hard-coded; status columns default to the harness status names verbatim (identity map).
- **`store.on_write_command`** — a generic, **VCS/PM-neutral** post-write hook. When
  non-empty the Orchestrator runs it after any persisted store write
  (`<cmd> "<feature-id>" "<op>"`, cwd = `HARNESS_DIR`); empty (default) ⇒ no hook. Best-effort:
  a non-zero exit never rolls back `tasks.json` and never blocks the loop. The harness never
  learns what the command does (git push, board mirror, both). A team wires `sync-board.mjs`
  into it via config — the mirror tool is never hard-coded into the loop.
- Config migration seeds both `store.on_write_command` and the `mirror:` block on upgrade
  (append-only, value-preserving); `sync-board.mjs` is installed + `chmod +x` like the
  telemetry tool.

### Docs
- **New `store/board-mirror.md`** — the mirror contract, provider table, and the
  **mirror-vs-backend** distinction (one-way projection vs where state lives).
- **`store/README.md`** gains a "Mirrors vs backends" section; **`store/jira.md`** gets a
  backend-not-mirror cross-link; **`store/local.md`** documents "Post-write sync";
  **`agents/orchestrator.md`** gains the best-effort post-write-sync step.

## [0.11.0] — 2026-06-08

### Added — ✨ `--shared-repo`: version-control the umbrella as a shared spec repository
- **`harness-install.sh --umbrella <dir> --shared-repo`** makes the umbrella ROOT its own
  git repo — a *shared spec repository* that tracks `.harness/` (specs, `state/tasks.json`,
  progress) + the umbrella docs and **git-ignores the product child repos** (each stays its
  own repo, never a gitlink). Solves the "planning state stranded on one laptop" gap a team
  hits when several developers work the same umbrella. **Opt-in and inert by default**:
  without the flag the umbrella stays a non-git parent dir, byte-for-byte as before.
  - `git init` runs **only if the umbrella root has no `.git`** — an existing repo is never
    re-initialized; if `git` is absent the install continues and seeds the `.gitignore`.
  - The umbrella-root `.gitignore` is **append-seeded** with exactly the child repos the
    cascade discovered (never a blanket rule; never clobbers an existing file).
  - Works with `--dry-run` to preview the `git init` + ignore plan. Umbrella-mode only
    (`--shared-repo` without `--umbrella` is rejected).
- **New `umbrella.gitignore.example`** (shipped at the harness root, beside
  `umbrella.manifest.example.yaml`) documents the intended shared-spec-repo `.gitignore`
  shape: product repos ignored, `.harness/` + docs tracked, personal state ignored.

### Docs
- **`docs/UMBRELLA.md`** softens the absolute "No new git repo is introduced" claim into a
  default-vs-opt-in statement and gains a **"Shared spec repository (opt-in)"** section.
- **`docs/INSTALL.md`** gains a `--shared-repo` subsection under umbrella mode.

## [0.10.0] — 2026-06-08

### Added — ✨ Seed a project-root `.gitignore` for personal/runtime agent state
- **`harness-install.sh` now append-seeds the project-root `.gitignore`** with per-developer
  agent state — `.claude/settings.local.json`, `.claude/scheduled_tasks.lock`, and a
  commented `.playwright-mcp/` — so a **shared** spec/umbrella repo (a team clones the
  install) never carries one developer's local config. The seed is **append-only and
  idempotent**: it never clobbers an existing root `.gitignore` and only adds an entry that
  is missing, mirroring the existing `.harness/.gitignore` telemetry seeding. It ignores
  **specific files** under `.claude/`, never the whole dir, so the harness-generated
  `.claude/agents` and `.claude/commands` stay tracked and shared.

### Docs
- **New `docs/CONFIG-LAYERING.md`** — the shared-vs-personal config model (project layer =
  committed `CLAUDE.md`/`.harness`/`.claude` glue; personal layer = gitignored
  `settings.local.json`; user-global = `~/.claude/CLAUDE.md`). Directly answers "should every
  developer share the same `CLAUDE.md`?" (yes — keep it shared; push personal prefs to the
  user-global layer).
- **INSTALL.md** ownership table gains the project-root `.gitignore` under runtime/local and a
  pointer to `CONFIG-LAYERING.md`.

## [0.9.0] — 2026-06-07

### Added — ✨ Install `/sdd-next` + `/sdd-new` as OpenCode commands too
- **`harness-install.sh` now emits the slash commands to `.opencode/command/` as well as
  `.claude/commands/`.** Previously the commands were written only to the Claude Code
  command dir, so targets driven through OpenCode saw the agents but had no `/sdd-next`
  or `/sdd-new`. The command bodies are now authored once and written to both locations
  (identical content; no `agent:` frontmatter, so they run under the primary
  orchestrator agent defined in the generated `opencode.json`). Regenerated on every
  install/upgrade. Manifest updated to list `.opencode/command/*` as harness-owned.

## [0.8.0] — 2026-06-06

### Added
- **Config migration seeds the `telemetry:` block on upgrade.** `harness-install.sh`'s
  append-only `migrate_config` now adds the `telemetry:` block (`enabled` kill-switch +
  `log:` path) to a preserved pre-telemetry config, so an upgraded consumer gains the
  same discoverable config surface as a fresh install (a config without the block already
  worked — it defaults to enabled + `telemetry.jsonl`). Covered by `tests/test_cascade.sh`.

### Docs
- **README** gains an **Observability (telemetry)** section (report commands, local-only
  gitignored storage, the `telemetry:` config + `enabled` kill-switch, cost-out scope), a
  note on the Reviewer's cross-file consistency check + multi-round build↔review loop, and
  `tools/` in the layout.
- **INSTALL.md** documents the installed `tools/`, the seeded `.harness/.gitignore` + local-only
  `telemetry.jsonl`, the telemetry config migration, and a pre-v0.7.0 upgrade note; adds a
  `runtime/local` row to the ownership table.

## [0.7.0] — 2026-06-06

### Added — ✨ Sub-agent & human-gate telemetry with rollup reports (E05-F02)
- **Telemetry contract (`agents/orchestrator.md` "## Telemetry").** The Orchestrator —
  the single writer — now appends structured, best-effort, append-only JSONL records at
  every delegation boundary and gate transition: a `phase` record per sub-agent span
  (`architect`/`builder`/`reviewer`/`scout`/`inception`/`slice-dispatch`) with
  `start`/`end`/`duration_s`/`outcome`/`round`/`slice`, a two-line `gate` open/close pair
  carrying `human_latency_s` (the human spec-approval interval, with an `autonomous` flag),
  and a `session-start` marker delimiting each session. Timestamps are ISO-8601 UTC via
  `date -u`. Capture is **never on the critical path** — a failed/absent write never
  blocks a gate or build. Token/USD accounting is **out of scope**; a reserved `cost`
  field (null today) lets a future instrumented runtime populate it without a format
  migration.
- **Storage = local-only runtime data.** The log resolves to `<HARNESS_DIR>/telemetry.jsonl`
  (overridable via the new optional `telemetry:` block in `harness.config.yaml`;
  `enabled: false` is the kill-switch). It is **gitignored / never committed**: the source
  `.gitignore` ignores `/telemetry.jsonl`, and `harness-install.sh` seeds a targeted
  `.harness/.gitignore` (containing `telemetry.jsonl`, seed-once / never clobbered) so a
  consumer's committed harness body coexists with a local-only log.
- **Report script (`tools/telemetry-report.py`, python3 stdlib only).** Reads the JSONL
  log and emits text/markdown rollup tables at `daily`/`weekly`/`monthly`/`quarterly`/
  `semester`/`annual` granularity (default: an all-granularity summary), plus a `session`
  view scoped to the latest `session-start` marker that reproduces the Orchestrator's
  end-of-session summary (per-phase durations, build↔review round count, mean/median
  human-gate latency excluding autonomous transitions). Malformed lines are skipped; an
  absent/empty log exits 0 with a "no telemetry yet" notice.
- **Portable end-of-session summary.** The summary instruction lives in
  `agents/orchestrator.md` (plain prose + `python3 tools/telemetry-report.py session`,
  no Claude-Code-specific dependency) with a one-line pointer in `AGENTS.md`, so every
  AGENTS.md-compatible CLI surfaces the same text-only table.
- **Tests:** `tests/test_telemetry.sh` covering R1–R27 (fixture-driven rollups, best-
  effort/empty no-op, schema/format, the two gitignores, the AGENTS.md pointer), wired
  into `verification.test_command`.

## [0.6.0] — 2026-06-06

### Added — Reviewer cross-file consistency + explicit build↔review rounds
- **Cross-file consistency check (`agents/reviewer.md`).** The in-loop Reviewer now
  has a named "What you check" item for cross-file consistency: for any change to a
  role/contract/prose file it loads the **collaborators the diff references** (the
  unchanged files the change invokes), scoped to those references
  (curate-don't-dump, never a whole-repo dump), and verifies the change's
  preconditions are satisfied by — and do not contradict — the contracts it invokes.
  A **provably violated** precondition is a **hard reject**; a suspected-but-unproven
  inconsistency is **flagged for the Builder to justify** rather than blocked. Ships
  the canonical **PR #10 worked example** (an `orchestrator.md` dispatch step telling
  the Builder to open a child PR vs. `builder.md` Loop A's "Builder never opens a PR")
  — a contradiction with no failing test, exactly what this check catches. Rejects
  emit specific, actionable, **file-based** feedback (contradicting files + expected
  vs. actual) to `progress/<run>/review.md`.
- **Explicit multi-round build↔review loop (`agents/orchestrator.md`).** The
  build↔review handoff is now documented as an explicit loop that repeats **until
  green**: reject → actionable file feedback → `in-progress` → Builder addresses →
  re-review. **Each round is recorded** (one line per round in `progress/history.md`).
  No new status value and no schema change — the round counter lives only in
  `progress/` history. `docs/WORKFLOW.md` aligned to the multi-round loop.

## [0.5.0] — 2026-06-06

### Added — umbrella mode hardening (feedback pass)
- **`in-session` umbrella dispatch is now a first-class, documented mode.** The
  coordinator loop previously documented slice dispatch *only* via an external
  `delegate_cmd` — but the shipped default is `execution.builder.backend: in-session`,
  which has no executor, so the documented path dead-ended on a fresh install.
  `agents/orchestrator.md` and `docs/UMBRELLA.md` now branch dispatch on
  `execution.builder.backend`: under `in-session` (default) the Orchestrator spawns the
  Builder sub-agent `cd`'d into each child repo (zero-dependency, the natural
  single-session path); under `delegate` it uses the `delegate_cmd` seam. `delegate_cmd`
  is now documented as optional and ships empty in `umbrella.manifest.example.yaml`.
- **Contract artifact is now prompted and enforced.** `agents/architect.md` gained an
  Umbrella-mode section making the single pinned inter-repo contract artifact
  **mandatory** for any feature with `slices[]`, with every slice required to reference
  it (prevents inter-repo field drift). `agents/reviewer.md` gained a matching check:
  a sliced feature is rejected unless the pinned contract exists and the slice under
  review traces its wire fields/shapes to it.
- **Cascade preview: `harness-install.sh --umbrella … --dry-run` (alias `--list`).**
  Lists the coordinator + every git child that would be installed (with skip reasons),
  writing nothing — so the cascade no longer surprises you by scaffolding untouched
  repos. The activation message now states explicitly that pointing `umbrella.manifest`
  ENGAGES umbrella mode.

### Changed
- Documented the two manifest path bases (the `umbrella.manifest` value resolves
  relative to `.harness/`; each entry's `path:` resolves relative to the manifest's own
  dir) in `harness.config.yaml`, `umbrella.manifest.example.yaml`, and `docs/UMBRELLA.md`.
- Clarified in `init.sh` that `.harness/init.project.sh` is for FAST structural/presence
  checks only — the heavy test suite belongs in `verification.test_command` (Reviewer-run,
  once at the `in-review` gate), not in the per-step gate.

## [0.4.0] — 2026-06-01

### Added — Inception role + /sdd-new intake (E04-F01)
- **Inception role (`agents/inception.md`):** the portable, model-interchangeable
  front door *before* `pending`. Takes a raw idea, triages it to exactly one altitude
  (new task on an existing not-`done` feature / new feature under an existing epic /
  new epic + `epic.md` + first `F01`), allocates a **next-sequential** id (no reuse of
  vacated ids), writes a `pending` TaskStore entry, re-validates `state/tasks.json`
  against `store/tasks.schema.json` (fail-stop: a failed validation is never a
  success), and writes an intent brief to `progress/inbox/<feature-id>.md`. It
  **seeds; it never specs** — it never writes the four spec files, never advances
  status past `pending`, and never spawns the Architect.
- **`/sdd-new` slash command (`.claude/commands/sdd-new.md`):** thin Claude wrapper
  that carries the interactive adaptive Q&A and ≤3 **text-only** mockup options,
  taking the idea via `$ARGUMENTS` and deferring the durable contract to the role
  file. Ends by reporting the seed + "run `/sdd-next`".
- **Installer ships `/sdd-new`:** `harness-install.sh` now emits an installed
  `.claude/commands/sdd-new.md` wrapper (with all paths rewritten to `.harness/…`)
  alongside `/sdd-next`, so consumer repos get the Inception intake command too.
  The installed wrapper mirrors the source's altitude-dependent write step (the
  altitude-1 reuse-and-append branch keyed on the existing feature's status) and
  copies its inbox brief from the shipped `.harness/specs/_templates/inbox-brief.md`
  template instead of the un-shipped `E04-F01.md` example; `tests/test_install.sh`
  asserts the template path, the absence of `E04-F01`, and the altitude-1 branch.
- **Docs:** `AGENTS.md` role list + flow now name Inception; `docs/WORKFLOW.md`
  documents the pre-`pending` intake step feeding the unchanged state machine.
- **Tests:** `tests/test_inception.sh` covering R1–R16 (static file/format/grep +
  schema validation), wired into `verification.test_command`.
- **Purely additive:** no change to `store/tasks.schema.json`, no new status value,
  and no change to the Orchestrator or Architect contracts.

## [0.3.0] — 2026-05-31

### Added — Cascade installer (E03-F02)
- **Umbrella install mode:** `harness-install.sh --umbrella <dir>` installs a
  coordinator profile in the umbrella directory, scans its immediate children, and
  installs the normal `.harness/` into each child that is a git repo (`.git` as a
  directory **or** a file). `--recursive` opt-in for deeper scans. Bare
  `harness-install.sh <target>` is byte-for-behavior unchanged (hard non-regression).
- **Manifest auto-population:** discovered repos are upserted into
  `umbrella.manifest.yaml` (path discovered; `init`/`test_command`/`delegate_cmd` as
  bootstrap TODOs). Idempotent — re-runs append new repos and never clobber
  project-owned entry fields. Repo-key grammar `^[a-z0-9-]+$` validated; violators are
  skipped with a message rather than written as undispatchable entries.
- **Non-destructive config migration:** on upgrade, missing umbrella keys
  (`umbrella.manifest`, `verification.integration_command`) are appended to a preserved
  `harness.config.yaml` without altering existing values/comments — fixes the case
  where a pre-0.2.0 install could never opt into the coordinator. Append-only and
  idempotent.
- **Tests:** `tests/test_cascade.sh` covering R1–R24, wired into
  `verification.test_command`.

## [0.2.0] — 2026-05-30

### Added — Multi-repo coordination (E03-F01: Umbrella coordinator)
- **TaskStore schema:** optional `slices[]` on a feature (`id`, `repo`, `status`,
  `merged`, `spec_path`, cross-repo `depends_on`). Pure superset — single-repo
  stores validate unchanged.
- **Umbrella manifest:** `umbrella.manifest.example.yaml` mapping each child repo to
  its `path` / `init` / `test_command` / `delegate_cmd`. Manifest presence is the
  opt-in switch for umbrella mode.
- **Config:** additive `verification.integration_command` (feature-level stack-up
  check) and `umbrella.manifest` keys. No existing key changes meaning.
- **Orchestrator "Umbrella mode"** (additive section, no role fork): topological
  slice select, dispatch via the existing `execution.builder.delegate` seam, gate
  downstream slices on upstream `done`+`merged`, fail-stop, and a derived feature
  `done` rolled up behind the integration gate.
- **Docs:** `docs/UMBRELLA.md` describing the coordinator model.
- **Tests:** `tests/test_umbrella.sh` covering R1–R19, wired into
  `verification.test_command`.

## [0.1.0]

### Added
- Initial harness body: installer (`harness-install.sh`), `init.sh` gate, the
  Orchestrator/Architect/Builder/Reviewer/Scout roles, the 4-file spec format, and
  the local/obsidian/jira store contract.
