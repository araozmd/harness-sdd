---
feature: E23-F01
role: reviewer
round: 2
verdict: rejected
date: 2026-07-29
---

# E23-F01 review round 2

Focused spec re-review found one blocking R2/R3 gap in partial skill-unit cleanup.

After a gate-on Codex install, deleting only
`.agents/skills/sdd-pr-loop/agents/openai.yaml` and rerunning with the gate off leaves
the byte-pristine, stamp-owned `SKILL.md` discoverable. Reclamation currently requires
both live files and both stamps to match before deleting either.

Required fix:

- reclaim `SKILL.md` independently whenever it matches its last-written stamp, even
  when companion metadata is missing or edited;
- preserve paths without ownership proof;
- when an edited skill survives, retain its explicit-only policy companion rather than
  making the surviving mutating skill implicitly invocable;
- prune directories only when empty;
- add gate-off and deselection regression cases for missing/edited companion metadata.

All other round-1 corrections remain spec-compliant.
