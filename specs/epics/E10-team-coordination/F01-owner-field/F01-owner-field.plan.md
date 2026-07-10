# Ownership primitive: `owner` field + scoped `/sdd-next` — Technical Plan

> Translates the .spec.md intent into design. Every decision cites the R-id(s) it
> serves. Start high-level; don't over-specify internals that might be wrong.

## Stack & dependencies
- Language/framework: this is a **prompt-and-shell harness**, not an app. The
  "implementation" is (a) a JSON-Schema edit, (b) a markdown role-contract edit,
  (c) a shell-generated markdown command body, (d) doc edits, (e) a `VERSION` bump,
  and (f) a shell test. No runtime service.
- New dependencies: **none.** Identity resolution reuses the already-present `gh`
  CLI dependency exactly as the board mirror does; when `gh` is absent or a `@me`
  lookup fails, scoped mode fails closed (R9) rather than adding a hard dependency to
  the default (unscoped) path.

## Resolved open questions (design decisions)
| Brief open question | Decision | Serves |
|---|---|---|
| Owner identity format | Configured `workflow.identity` in `harness.config.yaml`; `"@me"`/`"self"` → resolve to authed `gh` login via `gh api user` (board-mirror pattern); any other value = literal string; compared literally. | R3, R8, R9 |
| Epic-level, feature-level, or both | **Both**, optional. **Effective owner = feature `owner` else parent epic `owner` else unowned.** | R1, R6 |
| How is scoping invoked | `/sdd-next --mine` flag; it reads `workflow.identity` as the identity to match. Minimal cut: one flag, one config key. Bare `/sdd-next` stays board-wide. | R4, R5, R13 |
| Claimable-vs-owned | **Owned-only.** Scoped select picks only features I already own; **no** claim-on-select. Claiming unassigned work is E10-F02. | R5, R7 |
| Release / reassign | **Deferred to E10-F02.** No unassign/hand-over path here. | (out of scope) |

## Data model  (serves: R1, R2, R3)
The only persistent schema change: an optional string `owner` on epics and features.
No new required keys; no enum change; the existing `slices[]` cross-field rule is
untouched.

| Entity | Field | Type | Notes |
|---|---|---|---|
| epic (`epics[]`) | `owner` | `string` (optional) | Coarse ownership; not in `required`. Absent ⇒ epic unowned. |
| feature (`epics[].features[]`) | `owner` | `string` (optional) | Fine ownership; not in `required`. Absent ⇒ falls back to epic owner (R6). |

Schema edit sketch (in `store/tasks.schema.json`), additive only:
- Under the epic object `properties`, add `"owner": { "type": "string" }`.
- Under the feature object `properties`, add `"owner": { "type": "string" }`.
- Do **not** touch `required`, the `status` enums, the `slices` subschema, or the
  `allOf` cross-field rule. The `{ "type": "string" }` constraint alone gives R3
  (present-but-non-string ⇒ invalid) while absence stays valid (R2).

## Config  (serves: R4, R5, R8, R9)
New optional key in `harness.config.yaml` under the existing `workflow:` block:

```yaml
workflow:
  # Current developer's identity for scoped `/sdd-next --mine` selection.
  # Empty (default) ⇒ solo/board-wide, exactly today's behavior.
  # "@me" or "self" ⇒ resolve dynamically to the authed `gh` user (gh api user),
  #   so a SHARED config reflects whoever runs it (board-mirror `assignee` pattern).
  # Any other value ⇒ used verbatim as the literal identity string.
  identity: ""
```

- Absent/empty `identity` + no `--mine` ⇒ unchanged board-wide path (R4).
- `--mine` with empty/unresolvable `identity` ⇒ fail closed (R9), never widen (R10).

## Interface — `/sdd-next` scope argument  (serves: R5, R11, R12, R13)
`/sdd-next` already forwards `$ARGUMENTS` (a specific feature id today). Extend the
command contract so `$ARGUMENTS` may carry the **`--mine`** scope token:

| Invocation | Behavior | R-id |
|---|---|---|
| `/sdd-next` | Board-wide selection (today's behavior). | R4 |
| `/sdd-next --mine` | Scoped: only features whose effective owner == resolved identity. | R5 |
| `/sdd-next E10-F01` | Operate on the named feature (today's behavior, unchanged). | R4 |

The scoping logic lives in the **Orchestrator contract** (`agents/orchestrator.md`),
not in any one CLI's glue, so it is portable (R11). The command body is just the thin,
identical front-end that forwards the token.

## Selection algorithm (orchestrator contract change)  (serves: R5–R10)
Scoped selection is a **filter applied on top of** the existing `next()` — it never
loosens a gate:

1. Resolve identity (R8): read `workflow.identity`. `"@me"`/`"self"` → `gh api user`
   login; else literal. If unresolved and `--mine` was requested → **fail closed**
   (R9): select nothing, report "identity unresolved", change no state.
2. Run the existing `next()` candidate rules unchanged (epic gate, `depends_on` all
   `done`, actionable status, human gate).
3. **If `--mine`:** keep only candidates whose **effective owner** (R6) equals the
   resolved identity; drop unowned candidates (R7). Never write/claim an owner (R7).
4. Select the first surviving candidate by the existing lower-epic/lower-feature
   ordering. If none survive → report "no owned actionable work", change no state,
   do **not** widen to board-wide (R10).
5. **If not `--mine`:** behave exactly as today (R4) — `owner` values are ignored for
   selection.

## Files to change  (serves: R#)
| File | Change | R-id |
|---|---|---|
| `store/tasks.schema.json` | Add optional `"owner": {"type":"string"}` to the epic object `properties` and the feature object `properties`; leave `required`/enums/`slices`/`allOf` untouched. | R1, R2, R3 |
| `agents/orchestrator.md` | Add an "Ownership & scoped selection" subsection to the loop: define effective owner (R6), the `--mine` filter over `next()` (R5, R7), identity resolution (R8), fail-closed (R9), no-widen (R10). Portable wording (R11). Preserve the board-mirror-one-way note. | R5, R6, R7, R8, R9, R10, R11 |
| `harness.config.yaml` | Add `workflow.identity: ""` with the documented resolution semantics. | R8, R9 |
| `harness-install.sh` | Edit the single `CMDDIR/sdd-next.md` heredoc (≈ line 1023) so the generated command documents/forwards `--mine` scoped selection via `$ARGUMENTS`, pointing at the Orchestrator contract. This one edit propagates to Claude/OpenCode/Antigravity/Codex via the existing copy loops. | R11, R12, R13 |
| `.claude/commands/sdd-next.md` | Update the **source repo's** committed `/sdd-next` body to mirror the new generated body (this repo ships it directly, not only via the installer). Keep it byte-consistent with the generated CMDDIR body. | R11, R13 |
| `tests/test_install.sh` | Add assertions: the generated `/sdd-next` body (in each selected target) carries the `--mine` scoped-selection wiring and forwards `$ARGUMENTS`. | R12, R13 |
| `tests/test_ownership.sh` | **New** behavior suite: schema accepts owner-free + owner-present docs, rejects non-string owner; effective-owner + scoped-selection contract wording present in `agents/orchestrator.md`; config carries `workflow.identity`; docs describe owner + `--mine`; board-mirror one-way note intact. | R1–R10, R14 |
| `harness.config.yaml` (`verification.test_command`) | Append `&& sh tests/test_ownership.sh` so the new suite runs in the Reviewer's gate. | R13 (wiring) |
| `docs/WORKFLOW.md` | Document ownership: optional `owner` (epic + feature), effective-owner rule, `workflow.identity`, `/sdd-next --mine`, and "no owner anywhere ⇒ today's behavior". | R14 |
| `store/local.md` | Extend the `next()` / TaskStore description with the optional `owner` field, effective-owner resolution, and the scoped-selection filter (owned-only, no claim, fail-closed). | R14 |
| `VERSION` | Bump one **MINOR** step (e.g. `0.27.3` → `0.28.0`). Additive/backward-compatible. | R15 |

## DO NOT TOUCH
- `store/tasks.schema.json` `required` arrays, `status` enums, the `slices` subschema,
  and the `allOf` sliced-`done` cross-field rule — the change is purely additive
  (adding a property), and altering any of these would break existing stores (R2).
- `tools/sync-board.mjs` and `store/board-mirror.md`'s one-way invariant — the mirror
  stays one-way; agents never read the board for ownership (a rejected direction).
- The existing `next()` gates (epic gate, `depends_on`-done, actionable status, human
  gate) — scoping is a filter **layered on top**, never a relaxation (R5 preamble).
- `state/tasks.json` epic/feature entries' existing keys — do not retro-add `owner` to
  historical entries; the field is optional and absence must keep validating (R2).

## Approach notes
- **Backward-compat is the headline requirement.** The cheapest correct schema change
  is adding one optional property in two places; do not restructure. R2/R4 are the
  regression guardrails — prove them with behavior tests, never by pinning an exact
  VERSION string or diffing DO-NOT-TOUCH files against `main` (known permanent-suite
  anti-pattern).
- **One command body, four targets.** Because `harness-install.sh` generates every
  `/sdd-*` body once into `CMDDIR` and copies it to Claude (`.claude/commands/`),
  OpenCode (`.opencode/command/`), Antigravity (`.agents/workflows/`), and Codex
  (global prompts), a single heredoc edit satisfies R11/R12. The repo also commits its
  own `.claude/commands/sdd-next.md`; keep the two consistent.
- **Fail closed, don't widen (R9/R10).** The subtle correctness point: a scoped request
  that resolves to nothing must NOT silently behave board-wide — that would defeat the
  anti-collision purpose. Both the "unresolved identity" and "no owned work" cases stop
  and report; neither mutates state.
- **Effective owner is read-only here.** F01 only *reads* ownership to filter. Writing
  an owner (claim-on-select, reassignment) is all F02 — keep that boundary crisp so the
  Reviewer can reject any accidental owner-write.
- **Identity resolution mirrors the mirror.** Reuse the documented board-mirror `@me`
  behavior verbatim (`gh api user`, degrade rather than error), so operators learn one
  identity idiom across the mirror and scoped selection.
