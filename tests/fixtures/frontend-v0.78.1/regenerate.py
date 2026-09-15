#!/usr/bin/env python3
"""Maintainer-only regeneration from the pinned local Git object; never used by CI."""
import hashlib
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

COMMIT = "b3b47114d2274dfbe0a07e377aca199659def479"
HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
ALL = "claude,gemini,opencode,antigravity,codex"
CASES = {
    "all-five-off": (ALL, False, None),
    "all-five-on": (ALL, True, None),
    "all-five-models-on": (ALL, True, "mixed"),
    "all-five-pro-on": (ALL, True, "standard"),
    "all-five-flash-on": (ALL, True, "cheap"),
    "mixed-off": ("gemini,antigravity,codex", False, None),
    "retired-only-off": ("gemini,antigravity", False, None),
    "gemini-only-off": ("gemini", False, None),
    "antigravity-only-off": ("antigravity", False, None),
}


def retained(path):
    """Keep emitted glue and prior ownership/body evidence, not a runnable body."""
    if path.parts[0] != ".harness":
        return path.parts[0] != ".gitignore"
    return path.parts[1] in {
        ".harness-version", ".agents", "harness.config.yaml", "AGENTS.md",
        "agents", ".codex-skills", ".model-agents", ".opencode.stamp",
    }


def snapshot(target):
    return {str(p.relative_to(target)): p.read_bytes()
            for p in sorted(target.rglob("*"))
            if p.is_file() and retained(p.relative_to(target))}


def write_tree(root, entries):
    for name, data in entries.items():
        p = root / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)


scratch = Path(tempfile.gettempdir()) / "scratchpad/E29-F01-fixture-builder"
scratch.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="regenerate-", dir=scratch) as work:
    work = Path(work)
    source = work / "source"
    source.mkdir()
    archive = work / "baseline.tar"
    with archive.open("wb") as out:
        subprocess.run(["git", "-C", str(REPO), "archive", COMMIT], stdout=out, check=True)
    with tarfile.open(archive) as tar:
        tar.extractall(source, filter="data")
    env = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "HOME": str(work / "home"),
           "CODEX_HOME": str(work / "codex-home")}
    for key in ("HOME", "CODEX_HOME"):
        Path(env[key]).mkdir()
    snapshots = {}
    for name, (agents, gate, model) in CASES.items():
        target = work / name
        target.mkdir()
        cmd = ["sh", str(source / "harness-install.sh"), "--agents=" + agents,
               "--builder-backend=in-session", "--pr-loop=" + str(gate).lower(), str(target)]
        with (work / (name + ".log")).open("w") as log:
            subprocess.run(cmd, env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=log, check=True)
            if model:
                config = target / ".harness/harness.config.yaml"
                text = config.read_text()
                lines = text.splitlines(keepends=True)
                active = False
                tiers = {"orchestrator": "reasoning", "architect": "reasoning",
                         "builder": "standard", "builder-heavy": "reasoning",
                         "reviewer": "standard", "scout": "cheap", "doc-critic": "cheap"}
                for i, line in enumerate(lines):
                    if line.startswith("models:"):
                        active = True
                    elif active and line[:1] not in (" ", "#", "\n"):
                        active = False
                    if active and line.startswith("  ") and ":" in line and not line.lstrip().startswith("#"):
                        key = line.strip().split(":", 1)[0]
                        if key in tiers or key == "default":
                            tier = tiers.get(key, "standard") if model == "mixed" else model
                            lines[i] = line.replace(": inherit", ": " + tier, 1)
                text = "".join(lines)
                pins = "".join(f'  pin.{host}.{tier}: "{value}"\n'
                               for host, prefix in (("codex", "fixture-"), ("opencode", "fixture/"))
                               for tier, value in ((t, prefix + t) for t in ("reasoning", "standard", "cheap")))
                text = text.replace("models:\n", "models:\n" + pins, 1)
                config.write_text(text)
                subprocess.run(cmd, env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=log, check=True)
        snapshots[name] = snapshot(target)
    for name in ("base", "overlays"):
        shutil.rmtree(HERE / name, ignore_errors=True)
    base = snapshots["all-five-off"]
    write_tree(HERE / "base", base)
    for name, entries in snapshots.items():
        if name == "all-five-off":
            continue
        overlay = HERE / "overlays" / name
        overlay.mkdir(parents=True)
        parent = "all-five-on" if CASES[name][2] else "all-five-off"
        prior = snapshots[parent]
        (overlay / "parent.txt").write_text(parent + "\n")
        write_tree(overlay / "files", {p: data for p, data in entries.items() if prior.get(p) != data})
        (overlay / "remove.txt").write_text("".join(p + "\n" for p in sorted(prior.keys() - entries.keys())))
    digest = []
    for root in (HERE / "base", HERE / "overlays"):
        for p in sorted(root.rglob("*")):
            if p.is_file():
                digest.append(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(HERE)}\n")
    (HERE / "SHA256SUMS").write_text("".join(digest))
    for name, expected in snapshots.items():
        target = work / ("reconstructed-" + name)
        subprocess.run(["sh", str(HERE / "materialize.sh"), name, str(target)], check=True)
        assert snapshot(target) == expected, "Materialization differs from old output: " + name
print("Regenerated pinned v0.78.1 fixtures and SHA256SUMS")
