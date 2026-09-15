#!/bin/sh
# E29-F01 R1–R4: real frozen v0.78.1 upgrades and ownership failure controls.
set -eu
SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
python3 - "$SRC" <<'PY'
import hashlib, os, pathlib, shutil, subprocess, sys, tempfile
src=pathlib.Path(sys.argv[1]); fixture=src/'tests/fixtures/frontend-v0.78.1'
with tempfile.TemporaryDirectory(prefix='harness-retirement-') as temp:
    root=pathlib.Path(temp); env=os.environ.copy()
    for key in ('HARNESS_AGENTS','HARNESS_HOST_AGENT','HARNESS_PR_LOOP_ENABLED','CLAUDECODE','CLAUDE_CODE_ENTRYPOINT','CODEX_THREAD_ID','OPENCODE','OPENCODE_PID','ANTIGRAVITY_AGENT','ANTIGRAVITY_CONVERSATION_ID'):
        env.pop(key,None)
    env.update(HOME=str(root/'home'),CODEX_HOME=str(root/'codex'))
    def install(p,*args,extra=None,ok=True):
        e=env.copy(); e.update(extra or {})
        r=subprocess.run(['sh',str(src/'harness-install.sh'),*args,str(p)],env=e,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        if (r.returncode==0)!=ok: raise AssertionError(r.stdout)
        return r.stdout
    def fresh(name):
        p=root/name; p.mkdir(); return p
    def old(name,variant='all-five-on'):
        p=fresh(name); subprocess.run(['sh',str(fixture/'materialize.sh'),variant,str(p)],check=True); return p
    def snapshot(p):
        return {str(f.relative_to(p)): ('link',os.readlink(f)) if f.is_symlink() else ('file',hashlib.sha256(f.read_bytes()).hexdigest()) for f in p.rglob('*') if f.is_file() or f.is_symlink()}
    def claims(p):
        return subprocess.check_output(['sh',str(p/'.harness/tools/harness-owned-paths.sh'),'all',str(p/'.harness')],text=True)
    # Explicit errors must precede every target mutation, including on an upgrade.
    p=old('explicit'); before=snapshot(p)
    for args,e in [(('--agents=gemini',),{}),(('--agents=claude,antigravity',),{}),((),{'HARNESS_AGENTS':'gemini'}),(('--agents=host',),{'HARNESS_HOST_AGENT':'antigravity'})]:
        out=install(p,*args,extra=e,ok=False)
        assert 'claude' in out and 'codex' in out and 'opencode' in out
        assert snapshot(p)==before, 'explicit rejected selector mutated target'
    p=fresh('all'); install(p,'--agents=all'); assert (p/'.harness/.agents').read_text()=='claude\ncodex\nopencode\n'
    p=fresh('ambient'); install(p,'--agents=host',extra={'ANTIGRAVITY_AGENT':'1','GEMINI_CLI':'1'}); assert (p/'.harness/.agents').read_text()=='claude\n'
    print('ok - active_registry_and_explicit_rejection (R1)')
    p=old('retired-only','retired-only-off'); before=snapshot(p)
    out=install(p,ok=False); assert '--agents=codex' in out and snapshot(p)==before
    install(p,'--agents=codex'); assert not (p/'GEMINI.md').exists()
    for variant in ('mixed-off','all-five-off','all-five-on','all-five-models-on','all-five-pro-on','all-five-flash-on','gemini-only-off','antigravity-only-off'):
        p=old('upgrade-'+variant,variant)
        args=('--agents=codex',) if variant in ('gemini-only-off','antigravity-only-off') else ()
        install(p,*args)
        selected=(p/'.harness/.agents').read_text()
        assert 'gemini' not in selected and 'antigravity' not in selected
        assert not (p/'.agents/rules/harness.md').exists()
        assert not list((p/'.agents/workflows').glob('*.md'))
        assert not list((p/'.agents/agents').glob('*.md'))
        assert not list((p/'.gemini/agents').glob('*.md'))
        assert not (p/'GEMINI.md').exists()
        assert (p/'.agents/skills/sdd-next/SKILL.md').is_file()
        assert (p/'.agents/skills/sdd-next/agents/openai.yaml').is_file()
        before=snapshot(p); install(p); assert snapshot(p)==before, 'mixed migration not idempotent'
    p=old('legacy','all-five-off'); (p/'.harness/.agents').unlink()
    sent=root/'codex/prompts/sdd-next.md'; sent.parent.mkdir(parents=True,exist_ok=True); sent.write_text('unrelated global prompt\n')
    install(p); assert (p/'.harness/.agents').read_text()=='claude\nopencode\n'; assert sent.read_text()=='unrelated global prompt\n'
    # A pre-selection installation never asserts prior Codex ownership.
    assert (p/'.codex/agents/builder.toml').exists()
    p=old('orphan'); (p/'.harness/.harness-version').unlink(); before=(p/'.agents/rules/harness.md').read_bytes()
    install(p,'--agents=claude'); assert (p/'.agents/rules/harness.md').read_bytes()==before
    print('ok - recorded_selection_migration (R2)')
    p=old('edited','all-five-models-on')
    changed=['.agents/rules/harness.md','.agents/agents/scout.md','.agents/workflows/sdd-next.md','.gemini/agents/scout.md']
    for rel in changed:
        q=p/rel; q.write_bytes(q.read_bytes()+b'\nUSER EDIT\n')
    original={rel:(p/rel).read_bytes() for rel in changed}
    (p/'GEMINI.md').write_text('User introduction\n'+(p/'GEMINI.md').read_text()+'User conclusion\n')
    unrelated=p/'.agents/workflows/custom.md'; unrelated.write_text('mine\n')
    out=install(p,'--agents=codex')
    for rel,data in original.items(): assert (p/rel).read_bytes()==data and rel in out
    assert (p/'GEMINI.md').read_text()=='User introduction\nUser conclusion\n'
    assert unrelated.read_text()=='mine\n'
    owned=claims(p)
    for rel in changed: assert rel not in owned, 'retired edited glue still mandatory'
    assert '.codex/agents/builder.toml' in owned and '.agents/skills/sdd-next/SKILL.md' in owned
    # The mandatory installed drift guard must not claim edited retired files.
    subprocess.run(['git','init','-q',str(p)],check=True)
    subprocess.run(['git','-C',str(p),'add','.'],check=True)
    subprocess.run(['git','-C',str(p),'-c','user.name=fixture','-c','user.email=fixture@example.invalid','commit','-qm','fixture'],check=True)
    (p/changed[0]).write_text('changed again after install\n')
    r=subprocess.run(['sh',str(p/'.harness/init.sh')],cwd=p,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    assert r.returncode==0,r.stdout
    print('ok - post_retirement_drift_ownership (R4)')
    # Edited / foreign / file-link / parent-link protections for each legacy surface.
    paths=['.agents/rules/harness.md','.agents/agents/builder.md','.agents/workflows/sdd-pr-loop.md','.gemini/agents/builder.md','GEMINI.md']
    for i,rel in enumerate(paths):
        for kind in ('foreign','file-link','parent-link'):
            if rel=='GEMINI.md' and kind=='parent-link': continue
            p=old(f'protected-{i}-{kind}','all-five-models-on'); q=p/rel
            if kind=='foreign': q.write_text('my unrelated file\n'); external=None
            elif kind=='file-link':
                external=root/f'external-{i}-{kind}'; external.write_bytes(q.read_bytes()); q.unlink(); q.symlink_to(external)
            else:
                external=root/f'external-{i}-{kind}'; shutil.move(str(q.parent),str(external)); q.parent.symlink_to(external,target_is_directory=True)
            before=snapshot(p); external_before=snapshot(external) if external and external.is_dir() else external.read_bytes() if external else None
            out=install(p,'--agents=codex')
            assert rel in out or str(pathlib.Path(rel).parent) in out
            if kind=='foreign': assert q.read_text()=='my unrelated file\n'
            elif kind=='file-link': assert q.is_symlink() and external.read_bytes()==external_before
            else: assert q.parent.is_symlink() and snapshot(external)==external_before
    for stamp_kind in ('missing','corrupt','file-link','parent-link'):
        p=old('stamp-'+stamp_kind,'all-five-models-on'); live=p/'.gemini/agents/builder.md'; st=p/'.harness/.model-agents/gemini/builder.md'; before=live.read_bytes()
        if stamp_kind=='missing': st.unlink()
        elif stamp_kind=='corrupt': st.write_text('not a stamp\n')
        elif stamp_kind=='file-link':
            target=root/'stamp-external'; target.write_bytes(st.read_bytes()); st.unlink(); st.symlink_to(target)
        else:
            target=root/'stamp-parent-external'; shutil.move(str(st.parent),str(target)); st.parent.symlink_to(target,target_is_directory=True)
        install(p,'--agents=codex'); assert live.read_bytes()==before
        if stamp_kind=='file-link': assert st.is_symlink() and target.read_bytes()==before
        elif stamp_kind=='parent-link': assert st.parent.is_symlink()
    p=old('binary-pointer'); before=b'\xffuser bytes\n'; (p/'GEMINI.md').write_bytes(before); install(p,'--agents=codex'); assert (p/'GEMINI.md').read_bytes()==before
    p=old('edited-pointer'); (p/'GEMINI.md').write_text((p/'GEMINI.md').read_text().replace('Spec-Driven','Custom'))
    before=(p/'GEMINI.md').read_bytes(); install(p,'--agents=codex'); assert (p/'GEMINI.md').read_bytes()==before
    p=old('shared-deselection','mixed-off'); unit=p/'.agents/skills/sdd-next'
    (unit/'SKILL.md').write_bytes((unit/'SKILL.md').read_bytes()+b'\nCUSTOM\n'); before=snapshot(unit)
    install(p,'--agents=claude'); assert snapshot(unit)==before
    assert not (p/'.agents/skills/sdd-new/SKILL.md').exists()
    assert not (p/'.agents/skills/sdd-new/agents/openai.yaml').exists()
    assert '.agents/skills/sdd-next/' not in claims(p)
    print('ok - legacy_owned_cleanup_and_preservation (R3)')
PY
