# Frozen v0.78.1 front-end artifacts

These are actual installer outputs from **v0.78.1**, commit
`b3b47114d2274dfbe0a07e377aca199659def479`, captured for E29-F01 before
retiring Gemini/Antigravity and changing native Codex generation. They are
historical test evidence, not current installation instructions.

## Use in tests

```sh
sh tests/fixtures/frontend-v0.78.1/materialize.sh all-five-models-on "$target"
```

The destination must be empty or absent. This copies checked-in bytes only;
it does not run either installer, access Git, fetch a tag, or read home config.

| Fixture name | Recorded selection | PR loop | Models |
|---|---|---|---|
| `all-five-off` | All five historical hosts | Off | Inherit |
| `all-five-on` | All five historical hosts | On | Inherit |
| `all-five-models-on` | All five historical hosts | On | Mixed tiers and explicit synthetic Codex/OpenCode pins |
| `all-five-pro-on` | All five historical hosts | On | Standard tier for all roles; Gemini/Antigravity `pro` |
| `all-five-flash-on` | All five historical hosts | On | Cheap tier for all roles; Gemini/Antigravity `flash` |
| `mixed-off` | `antigravity,codex,gemini` | Off | Inherit |
| `retired-only-off` | `antigravity,gemini` | Off | Inherit |
| `gemini-only-off` | `gemini` | Off | Inherit |
| `antigravity-only-off` | `antigravity` | Off | Inherit |

The mixed model case uses reasoning for Orchestrator, Architect and heavy Builder;
standard for Builder and Reviewer; cheap for Scout and Doc-critic. Its default
tier is standard, including the gated PR-fixer. `fixture-*` and `fixture/*`
pins are deliberately synthetic strings for resolver regression assertions;
they are not claims about available models.

`base/` contains the all-five/off emitted set. Each `overlays/<name>/` stores
only changed/new files in `files/` and relative paths absent from that historical
install in `remove.txt`. `parent.txt` identifies the starting snapshot: model
variants extend `all-five-on`; all other overlays extend `all-five-off`. This
avoids duplicating the large unchanged PR-loop workflows. Selection variants
come from separate actual old installs. Use the materializer to apply parents.

The fixture retains all emitted front-end glue, root pointers, prior selection
and version, config, canonical installed role/entrypoint bodies, last-written
model and skill stamps, and the OpenCode stamp. Old `.claude/commands/` and
`.agents/workflows/` preserve historical command bytes, including the gated
PR-loop workflow, independently of new command generation. The role/config
evidence also supports reconstruction of old Antigravity persona references.

Large unrelated installed docs, tools, store, templates, sample task data,
manifest, and ignore files are omitted. Consequently this is **not a runnable
v0.78.1 harness body**: upgrade tests must install the new body before invoking
installed init. Tests may derive pre-selection/versionless cases, protected
edits, foreign files and symlinks in disposable copies; none are baked into
the pristine ownership evidence.

## Provenance and reproduction

Generation date: 2026-09-14. No network or authenticated host was used.

```sh
git rev-parse 'v0.78.1^{}'
# Must print b3b47114d2274dfbe0a07e377aca199659def479
python3 tests/fixtures/frontend-v0.78.1/regenerate.py
(cd tests/fixtures/frontend-v0.78.1 && sha256sum -c SHA256SUMS)
```

The maintainer-only generator archives that exact commit to a new temporary
source directory under the feature's scratch namespace. It never reads the
working installer to generate old bytes. Each target is empty initially;
the archived installer runs with these arguments:

```text
sh <archived-source>/harness-install.sh --agents=<explicit CSV>
    --builder-backend=in-session --pr-loop=<true|false> <empty-target>
```

The all-five CSV is `claude,gemini,opencode,antigravity,codex`; the old installer
does not accept the literal selector `all`. Generation has a clean environment
containing only `PATH=/usr/bin:/bin`, `LC_ALL=C`, and disposable `HOME` and
`CODEX_HOME` directories. For model variants, the generator edits the installed
config's `models` values and adds synthetic pins, then reruns that same archived
installer. `regenerate.py` records the exact tier/pin edit and pruning rules.
It verifies all nine materialized variants against their actual old emitted
file bytes before deleting temporary generation data.

`SHA256SUMS` covers every payload file and deletion list, with relative paths.
No mutable generation location or real home directory is embedded in the
payload. Repeating generation must leave these checksums unchanged. Tests use
`materialize.sh`, not the maintainer-only generator, so CI requires no historical
Git object or Python extraction support for fixture reconstruction.
