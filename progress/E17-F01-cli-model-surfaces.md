# E17-F01 — Per-CLI model-selection surfaces (external research)

Researched 2026-07-26/27 against official docs, and verified empirically against the
locally installed CLIs where possible (Codex 0.145.0, OpenCode 1.18.5, Antigravity
`agy` 1.1.3). **Confidence is marked per row — do not silently promote "unconfirmed"
to fact.**

## Comparison

| | Claude Code | Codex CLI | OpenCode | Antigravity (`agy`) | Gemini CLI |
|---|---|---|---|---|---|
| Per-agent model? | Yes | Yes | Yes | Yes (**needs `agy` ≥ 1.1.5**) | Yes |
| Key / format | `model:` (md frontmatter) | `model = "…"` (TOML) | `model:` (md frontmatter) | `model:` (md frontmatter) | `model:` (md frontmatter) |
| Agent file location | `.claude/agents/<role>.md` | `~/.codex/agents/*.toml`, `.codex/agents/` | `~/.config/opencode/agents/*.md` **or** `opencode.json` → `agent.<role>` | `~/.gemini/config/agents/`, workspace `.agents/agents/<role>.md` | `~/.gemini/agents/*.md`, `.gemini/agents/` |
| Value format | alias (`sonnet`/`opus`/`haiku`/`fable`), full id (`claude-opus-5`), or `inherit` | **bare** id (`gpt-5.4`); provider set separately via `model_provider` | **`provider/model` mandatory** | tier alias (`inherit`/`flash`/`pro`) | bare id or alias (`auto`/`pro`/`flash`) |
| Default when absent | `inherit` | inherit (omit the key) | inherit (omit the key) | `inherit` | `inherit` |
| Inherit sentinel | `inherit` ✅ | **none — omit the key** | **none — `inherit` is a hard error** ✅verified | `inherit` ✅ | `inherit` ✅ |
| Unknown value | silent fallback to inherited ✅docs | **soft warn + fallback**, no client-side gate ✅verified | **hard error, run aborts** ✅verified | unconfirmed | unconfirmed |
| Extra knob | `effort:` (`low`…`max`) | `model_reasoning_effort` (`minimal`…`xhigh`) | `temperature`, `variant` | — | `temperature`, `max_turns` |

## Consequences that must shape the spec

1. **No single value vocabulary exists.** Claude takes aliases *or* full ids, OpenCode
   demands `provider/model`, Codex demands a bare id, Antigravity takes only tier
   aliases. A generic tier in `harness.config.yaml` therefore **must be resolved
   per-front-end through a mapping table** — a single literal model string cannot be
   written verbatim into all five.

2. **Failure modes are asymmetric — OpenCode is the dangerous one.** Claude and Codex
   degrade silently on a bad value; OpenCode *aborts the run*, and its user-facing error
   is useless (`Unexpected server error`) unless run with `--print-logs --log-level
   ERROR`. Emitting an unresolvable model into `opencode.json` breaks the user's
   OpenCode entirely. Prefer **omitting the key** over writing a guessed value.

3. **`inherit` is not portable.** It is valid for Claude/Antigravity/Gemini, absent for
   Codex, and an error for OpenCode. "Use the session default" must compile to *key
   omission* on Codex and OpenCode.

4. **Antigravity needs a version floor.** The `model:` frontmatter landed in `agy`
   1.1.5; the locally installed 1.1.3 will treat it as inert. Stamping must degrade
   gracefully (and ideally warn) below the floor.

5. **Gemini's session `--model` flag does NOT reach subagents** (docs, verbatim: *"The
   `/model` command (and the `--model` flag) does not override the model used by
   sub-agents"*). Frontmatter or `agents.overrides` is the only lever.

6. **Path collision risk.** Antigravity's global agent dir is `~/.gemini/config/agents/`
   while Gemini CLI's is `~/.gemini/agents/`. Both under `~/.gemini`, **different
   directories, not interchangeable.**

## Open risk items (unresolved — carry into the plan)

- Unknown-model behavior for Antigravity and Gemini CLI is **undocumented and untested**.
- Whether Antigravity frontmatter `model:` accepts full model slugs or only
  `inherit|flash|pro` is **unconfirmed** — assume tier aliases only.
- Two open upstream issues allege subagents ignore configured models:
  [openai/codex#26363](https://github.com/openai/codex/issues/26363) (Codex custom
  agents not selectable since 0.137.0) and
  [anomalyco/opencode#35126](https://github.com/anomalyco/opencode/issues/35126)
  (subagents launched via the task tool ignore `model:` frontmatter). **Neither
  reproduced here.** Treat as risk, not fact — but they mean per-agent model routing may
  be unreliable on those two CLIs regardless of what the harness writes.

## Sources

- Claude Code: https://code.claude.com/docs/en/sub-agents.md
- Codex: https://learn.chatgpt.com/docs/agent-configuration/subagents
- OpenCode: https://opencode.ai/docs/agents/
- Antigravity: https://antigravity.google/docs/subagents + CLI changelog
- Gemini CLI: `docs/core/subagents.md`, `docs/cli/model-routing.md` (main branch)
