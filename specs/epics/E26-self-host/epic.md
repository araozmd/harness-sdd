---
id: E26
title: Self-host — the repo's own glue is installer-generated
status: done
---

# E26 — Self-host the harness

Drilled 2026-09-06. The defect class this kills: the repo's `.claude/agents` shims and
command copies are HAND-MAINTAINED mirrors of what the installer generates — every
divergence (multiple this campaign) is discovered by review instead of by construction.

**Deliberately NOT a whole-tree restructure**: moving the body under `.harness/` would
churn every path, test and doc for cosmetic parity. The value is generated-not-hand-
maintained glue, so the drill scopes to exactly that.

## Features

- **E26-F01 — `--self` mode.** `harness-install.sh --self` regenerates the SOURCE
  repo's own front-end glue (`.claude/agents/*` incl. builder-heavy, `.claude/commands/*`)
  from the same emitters used for targets, with paths resolved to the source layout (no
  `.harness/` prefix) and repo-local pins (builder=sonnet, builder-heavy=opus) applied
  from the shims' recorded models. Writes `.escalation-arming` from the real verdict.
- **E26-F02 — drift-by-construction gate.** A suite regenerates the glue into a temp
  dir and asserts byte-equality with the committed copies; init.sh gains a warn-only
  line when the source glue is stale. CI-equivalent: the suite fails when an emitter
  changes without regenerating.

Sequenced AFTER E27-F01 and the in-flight #149 (all touch harness-install.sh).
