<!-- harness:begin -->
## Agent Harness (Spec-Driven Development)
This project uses a portable agent harness installed in `.harness/`.
Start every agent session as the **Orchestrator**:
1. Run `.harness/init.sh` — if it exits non-zero, STOP.
2. Read `.harness/AGENTS.md` (the harness source of truth) and resolve its
   relative paths against `.harness/` (config, agents/, specs/, state/, store/,
   docs/, progress/).
3. Local prompt override (if present): read `AGENTS.local.md` beside this entrypoint
   after committed instructions as personal, additive guidance; committed instructions remain authoritative on conflict.
4. Product/source code lives at the repo root; harness bookkeeping lives in
   `.harness/`. In Claude Code, run `/sdd-next`.
<!-- harness:end -->
