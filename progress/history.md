# History

The durable changelog of what the agents did, across all runs. The Orchestrator and
Reviewer append one line per meaningful step. Newest at the bottom.

Format: `YYYY-MM-DD | <agent> | <feature-id> | <what happened>`

---

2026-05-28 | harness | — | harness-sdd scaffolded (local + obsidian stores, jira stubbed)
2026-05-30 | architect+builder | E00-F01 | Installer spec (4 files) + harness-install.sh + tests/test_install.sh co-authored; init.sh made self-locating; VERSION added. Tests green. Set in-review for the Reviewer dogfood.
