#!/bin/sh
# E29-F01 R5–R12: native source/consumer emitters, ownership, invocation and release contract.
set -eu
SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
python3 - "$SRC" <<'PY'
import hashlib, os, pathlib, re, shutil, subprocess, sys, tempfile, tomllib
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
            for rel in ('.claude/agents','.claude/commands','.codex/agents','.agents/skills'):
                shutil.rmtree(p/rel,ignore_errors=True)
            (p/'.claude/.glue-manifest').unlink(missing_ok=True)
            (p/'.escalation-arming').unlink(missing_ok=True)
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
    for selection,claude,codex in [('claude',True,False),('codex',False,True),('claude,codex',True,True),('all',True,True),('host',False,True)]:
        q=source('select-'+selection.replace(',','-'));run(q,None,'--self','--agents='+selection,extra={'HARNESS_HOST_AGENT':'codex'} if selection=='host' else {})
        assert (q/'.claude/commands/sdd-next.md').exists()==claude
        assert (q/'.codex/agents/builder.toml').exists()==codex
        if codex:native(q)
    for selection in ('gemini','antigravity','opencode'):
        before=snapshot(p);run(p,None,'--self','--agents='+selection,ok=False);assert snapshot(p)==before
    before=snapshot(p);run(p,None,'--self','--agents=host',extra={'HARNESS_HOST_AGENT':'opencode'},ok=False);assert snapshot(p)==before
    print('ok - self_selection_and_paths (R5)')
    # Model-only overrides are independent of seed settings and the other host.
    q=source('models');shutil.copytree(src/'.claude/agents',q/'.claude/agents',dirs_exist_ok=True)
    run(q,None,'--self')
    claude_models={r:re.findall(r'^model: (.+)$',(q/f'.claude/agents/{r}.md').read_text(),re.M) for r in roles}
    for role,model in [('builder','gpt-5.6-sol'),('builder-heavy','gpt-6-astra')]:
        f=q/f'.codex/agents/{role}.toml';f.write_text(f.read_text().replace('developer_instructions =',f'model = "{model}"\ndeveloper_instructions ='))
    run(q,None,'--self')
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
        assert f'`${cmd}`' in skill and '$ARGUMENTS' in skill
        assert not re.search(r'/sdd-(?:new|next|plan|drill|fix|pr-loop)(?:[`\s])',skill)
        # Executable shell programs are preserved exactly across the adapter.
        assert re.findall(r'```(?:bash|sh)\n(.*?)```',skill,re.S)==re.findall(r'```(?:bash|sh)\n(.*?)```',canonical,re.S)
    assert '`$sdd-drill <epic-id>`' in (p/'.agents/skills/sdd-plan/SKILL.md').read_text()
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
    for variant in ('all-five-on','all-five-models-on'):
        old=fresh('golden-'+variant)
        subprocess.run(['sh',str(src/'tests/fixtures/frontend-v0.78.1/materialize.sh'),variant,str(old)],check=True)
        golden={str(f.relative_to(old)):f.read_bytes() for pattern in ('.claude/agents/*.md','.claude/commands/*.md','.opencode/command/*.md','.opencode/agent/*.md','opencode.json') for f in old.glob(pattern) if f.name!='sdd-pr-loop.md'}
        install(old,'--agents=all','--pr-loop=true')
        for rel,content in golden.items():assert (old/rel).read_bytes()==content, 'retained old emission changed: '+rel
    print('ok - retained_host_and_seed_regression (R11)')
    assert (src/'VERSION').read_text().strip()=='0.79.0' and not (src/'GEMINI.md').exists()
    a=(src/'AGENTS.md').read_text()
    for token in ('./init.sh','non-zero','STOP','harness.config.yaml','agents/orchestrator.md','progress/lessons.md','spec-ready','in-progress','independent Reviewer','chat history','telemetry','tokens','VERSION','CHANGELOG.md','MINOR','MAJOR','branch','PR','main'):
        assert token.lower() in a.lower(),token
    assert (p/'.harness/AGENTS.md').read_text()==a
    release=(src/'CHANGELOG.md').read_text().split('## [0.79.0]',1)[1].split('\n## ',1)[0]
    for token in ('0.78.1','gemini','antigravity','UNARMED','bounded','pre-1.0','selectors'):assert token in release
    print('ok - release_and_current_usage_contract (R12)')
PY
