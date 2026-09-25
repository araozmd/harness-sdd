#!/bin/sh
# E29-F01 R5–R12: native source/consumer emitters, ownership, invocation and release contract.
set -eu
SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
python3 - "$SRC" <<'PY'
import hashlib, json, os, pathlib, re, shutil, subprocess, sys, tempfile, tomllib
src=pathlib.Path(sys.argv[1])
roles={'orchestrator','architect','builder','builder-heavy','reviewer','scout','doc-critic'}
cmds={'sdd-new','sdd-plan','sdd-drill','sdd-next','sdd-fix','sdd-fix-parallel'}
with tempfile.TemporaryDirectory(prefix='harness-native-') as temp:
    root=pathlib.Path(temp); env=os.environ.copy()
    for k in ('HARNESS_AGENTS','HARNESS_HOST_AGENT','HARNESS_PR_LOOP_ENABLED','CLAUDECODE','CLAUDE_CODE_ENTRYPOINT','CODEX_THREAD_ID','OPENCODE','OPENCODE_PID'): env.pop(k,None)
    env.update(HOME=str(root/'home'),CODEX_HOME=str(root/'codex'))
    def run(source,p,*args,ok=True,extra=None):
        e=env.copy();e.update(extra or {})
        r=subprocess.run(['sh',str(source/'harness-install.sh'),*args,*([str(p)] if p else [])],env=e,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        assert (r.returncode==0)==ok,r.stdout
        return r.stdout
    def install(p,*args,**kw): return run(src,p,*args,**kw)
    def fresh(name): p=root/name;p.mkdir();return p
    def source(name,clean=True):
        p=root/name;shutil.copytree(src,p,ignore=shutil.ignore_patterns('.git','node_modules','scratchpad','__pycache__'))
        if clean:
            for rel in ('.claude/agents','.claude/commands','.codex/agents','.agents/skills','.opencode'):
                shutil.rmtree(p/rel,ignore_errors=True)
            (p/'.claude/.glue-manifest').unlink(missing_ok=True)
            (p/'.escalation-arming').unlink(missing_ok=True)
            # F02: `opencode.json` is root-level generated glue. Delete it too, so a
            # `--self` run must GENERATE it rather than inherit the committed copy (a
            # copied fixture inherits the artifact under test, progress/lessons.md
            # 2026-09-05) and so a narrowed selection can be asserted to leave none.
            (p/'opencode.json').unlink(missing_ok=True)
        return p
    def snapshot(p):
        return {str(f.relative_to(p)):('link',os.readlink(f)) if f.is_symlink() else ('file',hashlib.sha256(f.read_bytes()).hexdigest()) for f in p.rglob('*') if f.is_file() or f.is_symlink()}
    def native(p,gated=True,prefix=''):
        expected=roles | ({'pr-fixer'} if gated else set())
        assert {f.stem for f in (p/'.codex/agents').glob('*.toml')}==expected
        for role in expected:
            body=tomllib.loads((p/f'.codex/agents/{role}.toml').read_text())
            assert {'name','description','developer_instructions'} <= body.keys() and body['name']==role
            assert f'Read {prefix}agents/{role}.md' in body['developer_instructions']
        for cmd in cmds | ({'sdd-pr-loop'} if gated else set()):
            unit=p/f'.agents/skills/{cmd}'
            assert (unit/'SKILL.md').is_file()
            assert (unit/'agents/openai.yaml').read_text()=='policy:\n  allow_implicit_invocation: false\n'
    p=source('default'); seed=(p/'harness.config.yaml').read_bytes(); canonical=(p/'AGENTS.md').read_bytes()
    run(p,None,'--self'); native(p); assert (p/'.claude/commands/sdd-next.md').exists()
    assert (p/'harness.config.yaml').read_bytes()==seed and (p/'AGENTS.md').read_bytes()==canonical
    before=snapshot(p);run(p,None,'--self');assert snapshot(p)==before,'self second run changed bytes'
    for selection,claude,codex,opencode in [('claude',True,False,False),('codex',False,True,False),('opencode',False,False,True),('claude,codex',True,True,False),('all',True,True,True),('host',False,True,False)]:
        q=source('select-'+selection.replace(',','-'));run(q,None,'--self','--agents='+selection,extra={'HARNESS_HOST_AGENT':'codex'} if selection=='host' else {})
        assert (q/'.claude/commands/sdd-next.md').exists()==claude
        assert (q/'.codex/agents/builder.toml').exists()==codex
        # F02 R1: OpenCode is now a first-class `--self` target, generated not inherited
        # (source() deletes it), so a narrowed selection must actually leave it absent.
        assert (q/'.opencode/command/sdd-next.md').exists()==opencode
        assert (q/'opencode.json').exists()==opencode
        if codex:native(q)
    # F02 R9: `--agents=host` resolves an OpenCode session to the OpenCode surface.
    q=source('select-host-opencode');run(q,None,'--self','--agents=host',extra={'HARNESS_HOST_AGENT':'opencode'})
    assert (q/'.opencode/command/sdd-next.md').exists() and (q/'opencode.json').exists()
    assert not (q/'.claude/commands/sdd-next.md').exists() and not (q/'.codex/agents/builder.toml').exists()
    for selection in ('gemini','antigravity'):
        before=snapshot(p);run(p,None,'--self','--agents='+selection,ok=False);assert snapshot(p)==before
    print('ok - self_selection_and_paths (R5)')
    # Model-only overrides are independent of seed settings and the other host.
    q=source('models');shutil.copytree(src/'.claude/agents',q/'.claude/agents',dirs_exist_ok=True)
    # F02 H2: these arming assertions are about Codex model routing. Pin the selection to
    # claude,codex so a bare `--self` (which now also selects OpenCode) cannot make the
    # conservative AND `blocked` for an unrelated reason.
    run(q,None,'--self','--agents=claude,codex')
    claude_models={r:re.findall(r'^model: (.+)$',(q/f'.claude/agents/{r}.md').read_text(),re.M) for r in roles}
    for role,model in [('builder','gpt-5.6-sol'),('builder-heavy','gpt-6-astra')]:
        f=q/f'.codex/agents/{role}.toml';f.write_text(f.read_text().replace('developer_instructions =',f'model = "{model}"\ndeveloper_instructions ='))
    run(q,None,'--self','--agents=claude,codex')
    assert tomllib.loads((q/'.codex/agents/builder.toml').read_text())['model']=='gpt-5.6-sol'
    assert tomllib.loads((q/'.codex/agents/builder-heavy.toml').read_text())['model']=='gpt-6-astra'
    assert 'model' not in tomllib.loads((q/'.codex/agents/scout.toml').read_text())
    for role,model in claude_models.items(): assert re.findall(r'^model: (.+)$',(q/f'.claude/agents/{role}.md').read_text(),re.M)==model
    assert 'codex=raise' in (q/'.escalation-arming').read_text()
    assert 'armed\n'==(q/'.escalation-arming').read_text().splitlines(keepends=True)[0]
    inherited=source('inherited');shutil.copytree(src/'.claude/agents',inherited/'.claude/agents',dirs_exist_ok=True);run(inherited,None,'--self')
    assert (inherited/'.escalation-arming').read_text().startswith('blocked\n') and 'codex=neither' in (inherited/'.escalation-arming').read_text()
    run(inherited,None,'--self','--agents=claude');assert (inherited/'.escalation-arming').read_text().startswith('armed\n')
    # Foreign first-time files, arbitrary edits, and links cannot be claimed or overwritten.
    for kind in ('foreign','edited','link','parent-link','skill-edited','policy-edited'):
        r=source('protected-'+kind);rel='.agents/skills/sdd-next/SKILL.md' if kind=='skill-edited' else '.agents/skills/sdd-next/agents/openai.yaml' if kind=='policy-edited' else '.codex/agents/scout.toml'
        if kind!='foreign':run(r,None,'--self')
        f=r/rel;f.parent.mkdir(parents=True,exist_ok=True)
        if kind in ('foreign','edited','skill-edited','policy-edited'):f.write_text((f.read_text() if f.exists() else '')+'\nUSER CONTENT\n')
        elif kind=='link':
            external=root/'source-external';external.write_bytes(f.read_bytes());f.unlink();f.symlink_to(external)
        else:
            external=root/'source-parent-external';shutil.move(str(f.parent),str(external));f.parent.symlink_to(external,target_is_directory=True)
        before=snapshot(f.parent)
        unit=r/'.agents/skills/sdd-next';companion=snapshot(unit) if kind in ('skill-edited','policy-edited') else None
        out=run(r,None,'--self');assert 'left unchanged and unclaimed' in out
        if kind not in ('parent-link',):
            after=snapshot(f.parent); assert all(after.get(k)==v for k,v in before.items())
        else: assert f.parent.is_symlink() and external.is_dir()
        assert rel not in (r/'.claude/.glue-manifest').read_text()
        if companion:assert snapshot(unit)==companion and '.agents/skills/sdd-next/' not in (r/'.claude/.glue-manifest').read_text()
    # R11: a temp install is not proof that a protected source Builder was stamped.
    # This must inspect the actual source pair, while unrelated role edits stay inert.
    for role,kind in [('builder','edited'),('builder-heavy','edited'),('builder-heavy','link'),('builder-heavy','parent-link'),('scout','edited')]:
        r=root/f'source-arming-{role}-{kind}';shutil.copytree(q,r)
        f=r/f'.codex/agents/{role}.toml'
        if kind=='edited':
            f.write_text(f.read_text().replace(f'Read agents/{role}.md', 'Read agents/architect.md'))
            before=f.read_bytes()
        elif kind=='link':
            external=root/'arming-role-external';external.write_bytes(f.read_bytes());f.unlink();f.symlink_to(external);before=external.read_bytes()
        else:
            external=root/'arming-parent-external';shutil.move(str(f.parent),str(external));f.parent.symlink_to(external,target_is_directory=True);before=snapshot(external)
        run(r,None,'--self','--agents=claude,codex')
        verdict=(r/'.escalation-arming').read_text()
        if role=='scout':assert verdict.startswith('armed\n') and 'codex=raise' in verdict,verdict
        else:assert verdict.startswith('blocked\n') and 'codex=unstamped' in verdict,verdict
        if kind=='parent-link':assert f.parent.is_symlink() and snapshot(external)==before
        elif kind=='link':assert f.is_symlink() and external.read_bytes()==before
        else:assert f.read_bytes()==before
        manifest=(r/'.claude/.glue-manifest').read_text()
        assert str(f.relative_to(r)) not in manifest
        assert subprocess.check_output(['cksum','.escalation-arming'],cwd=r,text=True).strip() in manifest
        # The blocked verdict and its ownership are stable after the protected file
        # has been excluded from the new manifest, not just on the first rejection.
        snapshot_before=snapshot(r);run(r,None,'--self','--agents=claude,codex');assert snapshot(r)==snapshot_before
    print('ok - source_model_and_collision_preservation (R6)')
    # Every Codex artifact class participates in actual source init drift diagnostics.
    for rel in ('.codex/agents/scout.toml','.agents/skills/sdd-next/SKILL.md','.agents/skills/sdd-next/agents/openai.yaml'):
        f=p/rel;original=f.read_bytes();f.write_bytes(original+b'\nDRIFT\n')
        r=subprocess.run(['sh',str(p/'init.sh')],cwd=p,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        assert 'generated glue diverges' in r.stdout and rel in r.stdout
        f.write_bytes(original);f.unlink()
        r=subprocess.run(['sh',str(p/'init.sh')],cwd=p,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        assert rel in r.stdout and 'generated glue diverges' in r.stdout
        f.write_bytes(original)
    manifest=(p/'.claude/.glue-manifest').read_text()
    assert '.codex/agents/pr-fixer.toml' in manifest and '.agents/skills/sdd-next/agents/openai.yaml' in manifest
    (p/'.codex/unrelated').write_text('mine');run(p,None,'--self','--agents=claude')
    assert not (p/'.codex/agents/scout.toml').exists() and (p/'.codex/unrelated').read_text()=='mine'
    print('ok - codex_manifest_and_idempotence (R7)')
    p=fresh('consumer');install(p,'--agents=all','--pr-loop=true');native(p,prefix='.harness/')
    for cmd in cmds|{'sdd-pr-loop'}:
        skill=(p/f'.agents/skills/{cmd}/SKILL.md').read_text();canonical=(p/f'.claude/commands/{cmd}.md').read_text()
        adapter=skill.split('## Invocation adapter',1)[1].split('## Canonical workflow',1)[0]
        workflow=skill.split('## Canonical workflow',1)[1]
        # PR #198 comment 4040142185: one body is read by BOTH claimants, so the BODY stays
        # host-neutral — it keeps the canonical PORTABLE `/sdd-*` spellings, and the ADAPTER
        # above carries the Codex `$sdd-*` / OpenCode `/sdd-*` mapping. `$sdd-*` is the
        # Codex-only spelling, so a body carrying it tells an OpenCode reader to invoke a
        # token its host cannot accept; the adapter must retain BOTH invocations.
        assert f'`${cmd}`' in adapter and f'`/{cmd}`' in adapter and '$ARGUMENTS' in adapter
        assert '$sdd-' not in workflow,f'{cmd}: shared body still carries the Codex-only $sdd-* spelling'
        # The body must equal the canonical command body, so the neutrality guarantee cannot
        # be satisfied by a body unrelated to what the host actually runs.
        assert workflow.lstrip('\n')==canonical.split('---\n',2)[2].lstrip('\n'),f'{cmd}: shared body differs from the canonical command body'
        # Executable shell programs are preserved exactly across the adapter.
        assert re.findall(r'```(?:bash|sh)\n(.*?)```',skill,re.S)==re.findall(r'```(?:bash|sh)\n(.*?)```',canonical,re.S)
    # The portable spelling reaches both hosts through the adapter; the Codex-only spelling
    # must not appear in the body (PR #198 comment 4040142185).
    assert '`/sdd-drill <epic-id>`' in (p/'.agents/skills/sdd-plan/SKILL.md').read_text()
    assert '`$sdd-drill <epic-id>`' not in (p/'.agents/skills/sdd-plan/SKILL.md').read_text()
    # E31-F01 R4: one shared unit, read by both claimants, so the adapter must name the
    # Codex `$sdd-*` invocation AND the OpenCode `/sdd-*` invocation, keep the `$ARGUMENTS`
    # mapping, and never point a host at `/skills` (OpenCode has no such command).
    h=fresh('adapter-host-neutral');install(h,'--agents=codex,opencode')
    for cmd in cmds:
        text=(h/f'.agents/skills/{cmd}/SKILL.md').read_text()
        adapter=text.split('## Invocation adapter',1)[1].split('## Canonical workflow',1)[0]
        assert f'`${cmd}`' in adapter,f'{cmd}: adapter lost the Codex invocation'
        assert f'`/{cmd}`' in adapter,f'{cmd}: adapter lost the OpenCode invocation'
        assert '$ARGUMENTS' in adapter,f'{cmd}: adapter lost the $ARGUMENTS mapping'
        assert '/skills' not in adapter,f'{cmd}: adapter still tells the host to use /skills'
        # The body's cross-command references (e.g. sdd-plan -> `/sdd-drill`) must also
        # reach Codex, so the adapter states the general `/sdd-<name>` -> host mapping.
        assert '`$sdd-<name>`' in adapter,f'{cmd}: adapter has no general Codex invocation mapping'
        assert '`/sdd-<name>`' in adapter,f'{cmd}: adapter has no general OpenCode invocation mapping'
    print('ok - skill_adapter_is_host_neutral (R4)')
    for host,advice in [('claude','Claude Code:'),('codex','Codex:'),('opencode','OpenCode:')]:
        target=fresh('advice-'+host);out=install(target,'--agents='+host);assert advice in out
        if host=='codex':assert 'invoke $sdd-next' in out and 'Open the repo in Claude Code' not in out
    print('ok - invocation_arguments_and_completion (R8)')
    # Gate and pristine reclamation apply to role + skill, independently protected edits.
    p=fresh('gate');install(p,'--agents=codex');native(p,False,prefix='.harness/')
    install(p,'--agents=codex','--pr-loop=true');native(p,prefix='.harness/')
    assert (p/'.harness/.model-agents/codex/pr-fixer.toml').is_file()
    install(p,'--agents=codex','--pr-loop=false');native(p,False,prefix='.harness/')
    assert not (p/'.agents/skills/sdd-pr-loop/SKILL.md').exists()
    install(p,'--agents=codex','--pr-loop=true');install(p,'--agents=claude');assert not (p/'.codex/agents/pr-fixer.toml').exists()
    for kind in ('edited','foreign','link','parent-link'):
        p=fresh('fixer-'+kind)
        if kind!='foreign': install(p,'--agents=codex','--pr-loop=true')
        f=p/'.codex/agents/pr-fixer.toml';f.parent.mkdir(parents=True,exist_ok=True)
        if kind in ('edited','foreign'):f.write_text((f.read_text() if f.exists() else '')+'\nCUSTOM\n');before=f.read_bytes()
        elif kind=='link':
            external=root/'fixer-external';external.write_bytes(f.read_bytes());f.unlink();f.symlink_to(external);before=external.read_bytes()
        else:
            external=root/'fixer-parent-external';shutil.move(str(f.parent),str(external));f.parent.symlink_to(external,target_is_directory=True);before=snapshot(external)
        out=install(p,'--agents=codex','--pr-loop=true');assert 'pr-fixer.toml' in out or '.codex/agents' in out
        install(p,'--agents=codex','--pr-loop=false')
        if kind=='parent-link':assert f.parent.is_symlink() and snapshot(external)==before
        elif kind=='link':assert f.is_symlink() and external.read_bytes()==before
        else:assert f.read_bytes()==before
    q=source('source-gate');run(q,None,'--self');cfg=q/'harness.config.yaml';cfg.write_text(re.sub(r'(?m)^(  enabled:) true( +# opt-in master gate)',r'\1 false\2',cfg.read_text()))
    run(q,None,'--self');assert not (q/'.codex/agents/pr-fixer.toml').exists() and not (q/'.agents/skills/sdd-pr-loop/SKILL.md').exists()
    print('ok - pr_fixer_gate_and_ownership (R9)')
    p=fresh('contract');install(p,'--agents=codex','--pr-loop=true')
    dispatch=(p/'.agents/skills/sdd-pr-loop/SKILL.md').read_text().split('**Native role dispatch:**',1)[1].split('**Always write the worker file',1)[0]
    assert 'Codex' in dispatch and 'fresh context' in dispatch and 'STOP' in dispatch
    assert '**in-session**' not in dispatch and 'handoff' in dispatch
    text=(src/'agents/orchestrator.md').read_text().split('## How you delegate',1)[1].split('**Telemetry',1)[0]
    for tokens in [('Codex','named role'),('fresh','context'),('human','spec-ready'),('independent','Reviewer'),('init-failure','halt')]:
        assert all(t in text for t in tokens),tokens
    print('ok - native_handoff_contract (R10)')
    # Retained output uses the same canonical bodies; consumer defaults remain inert.
    p=fresh('seed');install(p,'--agents=claude,opencode,codex');cfg=(p/'.harness/harness.config.yaml').read_text()
    assert re.search(r'(?m)^    backend: in-session',cfg) and re.search(r'(?m)^  enabled: false.*opt-in master gate',cfg)
    for role in roles: assert 'model' not in tomllib.loads((p/f'.codex/agents/{role}.toml').read_text())
    assert not (p/'.codex/agents/pr-fixer.toml').exists()
    # Opt-in distinct compatible model pins use existing resolver and arming semantics.
    cfg=cfg.replace('builder: inherit','builder: standard').replace('builder-heavy: inherit','builder-heavy: reasoning')
    cfg=cfg.replace('# pin.codex.standard: ""','pin.codex.standard: "gpt-5.6-sol"').replace('# pin.codex.reasoning: ""','pin.codex.reasoning: "gpt-6-astra"')
    (p/'.harness/harness.config.yaml').write_text(cfg);install(p,'--agents=codex')
    assert tomllib.loads((p/'.codex/agents/builder.toml').read_text())['model']=='gpt-5.6-sol'
    assert tomllib.loads((p/'.codex/agents/builder-heavy.toml').read_text())['model']=='gpt-6-astra'
    assert (p/'.harness/.escalation-arming').read_text().startswith('armed\n')
    # Frozen old emission is the regression oracle, not the newly edited emitter.
    # Files a feature INTENTIONALLY regenerates are excluded, or the oracle would
    # contradict that feature: `sdd-pr-loop.md` has always been regenerated, and
    # E28-F02 adds the Planner topology step to the `/sdd-plan` body and the Driller
    # stop-and-hand-off step to the `/sdd-drill` body. E99-F163 likewise regenerates
    # `.claude/agents/builder-heavy.md` — the emitted description now names the resolved
    # stamp (model, and on codex reasoning effort), which is the N4 fix; its content is
    # pinned positively by tests/test_escalation.sh's N4 assertions. The CURRENT
    # `sdd-plan`/`sdd-drill` bodies are still pinned — by the skill-equals-canonical
    # assertion above and by tests/test_planner_topology.sh R8/R10 — so this only drops
    # the claim that the v0.78.1 bytes survive, which those features deliberately make
    # false.
    _regenerated={'sdd-pr-loop.md','sdd-plan.md','sdd-drill.md','builder-heavy.md'}
    for variant in ('all-five-on','all-five-models-on'):
        old=fresh('golden-'+variant)
        subprocess.run(['sh',str(src/'tests/fixtures/frontend-v0.78.1/materialize.sh'),variant,str(old)],check=True)
        golden={str(f.relative_to(old)):f.read_bytes() for pattern in ('.claude/agents/*.md','.claude/commands/*.md','.opencode/command/*.md','.opencode/agent/*.md','opencode.json') for f in old.glob(pattern) if f.name not in _regenerated}
        install(old,'--agents=all','--pr-loop=true')
        for rel,content in golden.items():assert (old/rel).read_bytes()==content, 'retained old emission changed: '+rel
    print('ok - retained_host_and_seed_regression (R11)')
    # F02 R9: the COMMITTED SOURCE-layout OpenCode glue must resolve /sdd-next and the
    # builder-heavy + pr-fixer agents. The static assertions are mandatory; the live probe
    # is gated on the binary and reports skipped where OpenCode is unavailable (CI).
    oc=json.loads((src/'opencode.json').read_text())
    assert 'builder-heavy' in oc.get('agent',{}) and oc['agent']['builder-heavy'].get('prompt')=='{file:./agents/builder-heavy.md}'
    assert (src/'.opencode/command/sdd-next.md').is_file()
    assert (src/'.opencode/agent/pr-fixer.md').is_file()
    ocbin=shutil.which('opencode')
    if ocbin:
        # OpenCode installs runtime deps into `.opencode/` on first run, so the LIVE probe
        # runs against an ISOLATED copy of the source layout — never the repository itself.
        # Capture through a FILE, not a pipe: opencode truncates its JSON at 64 KiB when
        # stdout is a pipe, which silently drops the `command` section this probe asserts.
        probe=pathlib.Path(tempfile.mkdtemp(prefix='opencode-source-probe-'))
        try:
            for rel in ('opencode.json','AGENTS.md'):
                if (src/rel).is_file(): shutil.copy2(src/rel,probe/rel)
            (probe/'.opencode').mkdir(parents=True,exist_ok=True)
            for rel in ('.opencode/command','.opencode/agent','agents'):
                if (src/rel).is_dir(): shutil.copytree(src/rel,probe/rel)
            def oc(*args):
                fd,fn=tempfile.mkstemp(prefix='opencode-probe-');os.close(fd)
                with open(fn,'w') as fh:
                    subprocess.run([ocbin,*args],cwd=probe,stdout=fh,stderr=subprocess.STDOUT,timeout=120)
                data=pathlib.Path(fn).read_text();os.unlink(fn);return data
            agents=oc('agent','list')
            assert 'builder-heavy (subagent)' in agents and 'pr-fixer (subagent)' in agents,agents
            commands=oc('debug','config')
            assert '"sdd-next"' in commands,'live opencode probe did not resolve /sdd-next'
            print('ok - opencode_source_host_resolves (R9, live)')
        finally:
            shutil.rmtree(probe,ignore_errors=True)
    else:
        print('skip - live opencode probe unavailable; static source-layout assertions passed (R9)')
    assert (src/'VERSION').read_text().strip()=='0.84.3' and not (src/'GEMINI.md').exists()
    a=(src/'AGENTS.md').read_text()
    for token in ('./init.sh','non-zero','STOP','harness.config.yaml','agents/orchestrator.md','progress/lessons.md','spec-ready','in-progress','independent Reviewer','chat history','telemetry','tokens','VERSION','CHANGELOG.md','MINOR','MAJOR','branch','PR','main'):
        assert token.lower() in a.lower(),token
    assert (p/'.harness/AGENTS.md').read_text()==a
    release=(src/'CHANGELOG.md').read_text().split('## [0.79.0]',1)[1].split('\n## ',1)[0]
    for token in ('0.78.1','gemini','antigravity','UNARMED','bounded','pre-1.0','selectors'):assert token in release
    print('ok - release_and_current_usage_contract (R12)')
PY
