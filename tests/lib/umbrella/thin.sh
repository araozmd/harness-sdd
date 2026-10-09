SENTINEL='<!-- harness:umbrella-stub -->'
# specs/glossary.md is deliberately ABSENT from this sample (E30-F01): it left the prose
# tier entirely and is project-owned in every layout, so it is never a stub — see
# glossary_never_stubbed_in_any_layout below.
PROSE_TIER='AGENTS.md agents/builder.md agents/orchestrator.md docs/WORKFLOW.md specs/_templates/feature.spec.md'
LOCAL_TIER='init.sh store/tasks.schema.json tools/tasks-lock.py tools/harness-owned-paths.sh'

is_stub() { head -n 1 "$1" 2>/dev/null | grep -qxF "$SENTINEL"; }
