# E99-F09: Update Antigravity integration to use Skills architecture - Tests

## Automated Tests
- **Test 1: Antigravity Installation Paths**
  - **Action:** Run `harness-install.sh` with `--agents=antigravity`.
  - **Expected:** The directory `.agents/skills/` is created. `.agents/workflows/` and `.agents/agents/` are not created. Subdirectories like `.agents/skills/sdd-next/` exist.
- **Test 2: Skill Frontmatter**
  - **Action:** Inspect the generated `.agents/skills/sdd-next/SKILL.md` file.
  - **Expected:** The file starts with a YAML frontmatter block containing `name: sdd-next` and a `description:` field.
- **Test 3: Antigravity Deselection**
  - **Action:** Run `harness-install.sh` with `--agents=antigravity`, then run it again with `--agents=claude`.
  - **Expected:** The `.agents/skills/` directory and its contents created during the Antigravity installation are completely removed.
