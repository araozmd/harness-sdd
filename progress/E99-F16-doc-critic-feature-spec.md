# E99-F16 — Doc-critic note (`target-type=feature-spec`)

**Spawned:** as a Claude Code sub-agent from `.claude/agents/doc-critic.md` in the harness
**source** checkout, on branch `fix/E99-F16-source-doc-critic-shim`. This is the first
executed run of the R12 checkpoint in this repo — every prior claim that it was spawnable
here was structural (file present, frontmatter parses, caller carries `Task`). The fix works
end to end.

**Scope note.** `agents/doc-critic.md` says "you **never** review production source code,
tests, build scripts, or configuration files". E99-F16 is `sdd: false` and has no four-file
spec, so the invoking agent directed this pass at the brief plus the suite, the shims and
`opencode.json`. Reviewed as directed; recorded here so this run is not read as precedent
for the Doc-critic reviewing test code at a normal `feature-spec` checkpoint.

**Files reviewed**

- `progress/inbox/E99-F16.md` (the contract, in place of a spec)
- `tests/test_source_shims.sh`
- `.claude/agents/doc-critic.md`, `.claude/agents/architect.md`, `opencode.json`
- `progress/E99-F16-builder.md`

**Not re-raised** (settled before this pass): the absent `VERSION` bump / `CHANGELOG.md`
entry; the deferral of `builder-heavy` and `pr-fixer`; the unscoped `^tools:` grep idiom
carried over from `tests/test_install.sh:584-590`.

---

## Findings

### 1. Consistency (with a clarity component) — `tests/test_source_shims.sh:93-95`, vs `:143` and `:78`

The front-end enumeration asserts `.opencode` is absent from the source. `register_ok()`'s
`opencode` branch accepts `.opencode/agent/<role>.md` as a valid registration, and
`KNOWN_GAPS` carries `pr-fixer:opencode` whose **only** correct fix is creating exactly that
file (`tests/test_pr_loop.sh:482-483` asserts `opencode.json` must never gain a `pr-fixer`
entry). The two assertions cannot both hold once that gap is closed.

Why it matters downstream. The whole justification for `KNOWN_GAPS` (`:69-73`) is that an
entry asserted still-broken "fails the moment someone fixes it, and the failure message says
to delete the line". For `pr-fixer:opencode` that signal never fires: the enumeration loop
fails first, ~70 lines earlier, with a message that tells the author to "extend
`register_ok()` and this enumeration" — and `register_ok()` already handles the case and
needs no change. So the one entry whose fix is least obvious is the one the suite misdirects.
The same assertion also makes the `.opencode/agent/` fallback at `:143` unreachable today:
it is the only machinery in the suite that cannot execute.

Yes, worth a fix, and the cheap one is enough. Either:

- keep the loop but name the real remedy in the message — "if you added
  `.opencode/agent/<role>.md` to close a `KNOWN_GAPS` entry, remove `.opencode` from this
  list; `register_ok()` already covers it" — or
- drop `.opencode` from the absent-list and instead assert that, if present, it contains only
  `agent/<role>.md` files for roles in `SPAWNED`, which preserves the "a new front-end must
  not silently escape the loop" guarantee without contradicting the deferred fix.

### 2. Completeness — `tests/test_source_shims.sh:132-135` (`register_ok`, `claude` branch)

The Claude branch is `[ -f "$SRC/.claude/agents/$1.md" ]` — existence only. The OpenCode side
asserts the map key, `mode: subagent`, and the exact source-rooted prompt string. Two failure
modes pass the general rule while leaving the role unspawnable:

- a shim body pointing at `.harness/agents/<role>.md`. `.harness/` does not exist in this
  checkout, so the sub-agent is handed a path to nothing. This is precisely the mistake the
  brief anticipated (`progress/inbox/E99-F16.md:54-56`: "check the existing shims rather than
  copying the installer's heredoc verbatim"), and section 4 guards it — **for `doc-critic`
  only**.
- frontmatter `name:` not matching the filename. Claude Code addresses a sub-agent by `name`,
  not by path, so `spawn the doc-critic sub-agent` fails while the file sits there.

Why it matters downstream. No live defect — all seven source shims currently point at
`agents/` and carry a matching `name:`. It bites at the next `KNOWN_GAPS` retirement: someone
adds `builder-heavy` by lifting the installer heredoc, the xfail flips to a real pass, the
general rule waves it through, and `agents/architect.md`'s `complexity: complex` escalation
silently spawns a role pointed at a nonexistent file — the same class of silent-green bug
this feature exists to end.

Fix: move the three checks out of section 4 into the `claude` branch so they apply to every
`SPAWNED` role — `grep -qE "^name: $1\$"`, `grep -qF "agents/$1.md"`, and `! grep -qF
'.harness/'`. Roughly four lines in a function that already exists; section 4 then keeps only
what is doc-critic-specific (`Write`, and the caller's `Task`).

### 3. Consistency — `progress/inbox/E99-F16.md:85` and `:133-135`

The brief carries two factual errors that the implementation diverges from, both corrected in
`progress/E99-F16-builder.md` but neither corrected in place:

- the enumeration table classifies `pr-fixer` as missing from `opencode.json`, implying the
  fix is a JSON key. The installer deliberately never registers it there; the real site is
  `.opencode/agent/pr-fixer.md` (`harness-install.sh:4679`), and `tests/test_pr_loop.sh:482-483`
  asserts the JSON must not gain the entry.
- the Open question states "no other source shim carries `Task` today".
  `.claude/agents/orchestrator.md` carries `tools: Read, Bash, Edit, Grep, Glob, Task` and
  always has.

Why it matters downstream. For an `sdd: false` feature the brief **is** the durable contract —
there is no spec to supersede it. The table's stated purpose is "Recorded here so the next
reader does not have to rediscover them" (`:97-98`), and that purpose fails when the row sends
the reader at the wrong file; the `KNOWN_GAPS` entry `pr-fixer:opencode` reads the same way,
which is how this compounds with finding 1. Fix: correct the table row to name
`.opencode/agent/pr-fixer.md`, and strike or annotate the `Task` premise — in the brief, not
only in the Builder note. A one-line correction footnote per row is enough; the reasoning is
already written up in `progress/E99-F16-builder.md:169-178`.

---

## Dimensions with nothing to report

- **Clarity** — clean. Every assertion carries a failure message that names the real symptom
  rather than the broken predicate; the "why this suite exists at all" header and the
  maintained-list rationale answer the two questions a future reader would otherwise ask. The
  single exception is the misdirecting message in finding 1.
- **Scope** — clean. Three registrations plus one suite; nothing outside the brief's In-scope
  list was touched, and the two deferrals are recorded as executable xfails rather than prose.
- **YAGNI** — clean, with one cross-reference: the only piece of machinery that does not earn
  its place today is `register_ok()`'s `.opencode/agent/` fallback, and that is a symptom of
  finding 1 rather than a separate item. Deleting it would be the wrong fix — it models a real
  installer mechanism.

## Brief vs implementation

They agree on everything load-bearing. All three registrations the success outcome names are
present; the test asserts each precondition separately, as the brief required; both Open
questions are answered with reasoning rather than closed silently; the no-`VERSION`-bump
constraint is honored and re-verified rather than assumed. The divergences are the two factual
errors in finding 3, which the implementation was right to depart from.
