# ADR-0002 — `builder-heavy` is a model tier, not a second Builder prompt

- **Status:** accepted (E17 drill amend, 2026-08-02)
- **Context:** E17's epic brief calls for "two Builder variants (standard + heavy)" so the
  Orchestrator can escalate a struggling task deterministically. How the *heavy* variant
  differs is the decision this ADR settles, because it decides whether escalation is a
  **routing** change or a **behavioral** one, and the two have very different maintenance
  costs. Three options were on the table:

  1. **A pointer at the same body, differing only by resolved model tier.** The installer
     already anticipates exactly this shape — `harness-install.sh` calls a future
     `builder-heavy` "ONE new name here + one `models:` line", because `MODEL_ROLES` is a
     flat list keyed off role names and needs no config migration to grow.
  2. **Its own prompt body**, e.g. carrying a heavier verification discipline such as the
     mandatory mutation-proof lesson from E99-F07.
  3. **No new role at all** — the Orchestrator re-spawns the *same* `builder` with a
     per-spawn model override.

  Option 3 fails the harness's universality invariant outright. Only Claude Code and
  Antigravity can override a model per spawn; Codex, OpenCode and Gemini resolve the model
  from the *generated agent definition*, so escalation would silently no-op on three of the
  five supported front-ends — the worst failure mode available, since the Orchestrator would
  report an escalation that never happened.

  Option 2's cost is drift. Two Builder prompts maintained independently means every future
  Builder change must be made twice, and the harness has already recorded what happens when
  a body and its guard diverge (E99-F07, five instances of one defect class in a single
  feature).

- **Decision:** `builder-heavy` is a **distinct role name with the same instruction body**.
  `agents/builder-heavy.md` is a thin pointer at `agents/builder.md` — the mechanism the
  `.claude/agents/` mirrors already use — so the two variants differ **only** by the model
  tier `resolve_model` returns for them. Escalation is therefore a pure routing decision:
  the Orchestrator picks a role name, and the front-end's generated agent definition
  supplies the model. No front-end needs a per-spawn override capability.

- **Consequences:**
  - **Easier.** Adding the role is additive plumbing: one `MODEL_ROLES` entry, one
    `ag_personas` row, one `models:` key, and the existing per-front-end generators and
    reclaim-on-deselect paths handle it unchanged. Escalation can be specified and tested
    without reasoning about two different Builder behaviors.
  - **Easier.** A target that configures nothing still gets today's harness: with
    `builder-heavy: inherit` the model key is omitted everywhere, exactly as for every other
    role (see the `inherit` contract in `harness.config.yaml`).
  - **Harder.** The heavy variant cannot be made *behaviorally* more careful — only more
    capable. If a future feature wants a genuinely different Builder discipline, it must
    revisit this ADR rather than quietly forking the body.
  - **Breaking-ish, and load-bearing for E17-F02.** The role count stops being six.
    `MODEL_ROLES`, `ag_personas`, and every assertion that fixes the set at "exactly the six
    standard roles" — notably in `tests/test_model_routing.sh` after E23-F01 R6 — must be
    updated together. An assertion left at six does not fail loudly; it fails by pinning the
    old set while the installer emits seven, so E17-F02 must treat those assertions as part
    of the change, not as collateral.
