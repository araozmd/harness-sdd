---
feature: E99-F17
agent: builder
date: 2026-08-14
---
# E99-F17 — the park suite's R7 precondition broke on the first real park

## What happened

`tests/test_feature_park.sh` R7 required the repository's **own live board** to carry zero
`parked` features:

```sh
n=sum(1 for e in d['epics'] for f in e.get('features',[]) if 'parked' in f)
sys.exit(0 if n==0 else 1)" || fail "R7 precondition: the repo board already carries a parked key"
```

`E21-F06` (merged in PR #131) is the first legitimate park in this repo's history, so the suite
that **tests parking** was broken by the first use of parking. A permanent suite coupled to
mutable live state makes the feature under test unusable the moment anyone uses it — the same
family as freezing a `VERSION` string or diffing DO-NOT-TOUCH files against `main`.

Found by the E99-F16 Builder while running the full suite; `main` was red.

## The fix

R7 now **derives** a parkless board from the live one (`--tasks "$T/noparks.json"`) instead of
demanding the live one be parkless. That keeps what the rule was for — the REAL selector over
the REAL board's content, no hand-written expectation that could drift into agreeing with a bug
— and survives any number of real parks.

## Two things the mutation check forced

1. **The first control I wrote was wrong**, and failed on its first run. I asserted that a live
   board carrying a park makes `node tools/next-task.mjs` emit park output. It does not:
   board-wide selection returns the first **actionable** feature with an empty `blocked` list and
   never mentions a park that is not in its way. The control now targets the parked feature
   (`--feature <id>`), where the guarantee actually lives.
2. **The derivation was not load-bearing until R7 was strengthened.** Mutation 1 — swap
   `--tasks "$T/noparks.json"` back to the live board — **survived**, because the board-wide
   assertion passes on either input. An assertion that cannot tell its two inputs apart is not
   testing either of them. R7 now pairs them: the same targeted selection must report `parked`
   on the live board and must **not** on the derived one. Mutation 1 re-run now fails with
   `the derived parkless board still reported a park for E21-F06`.

## Mutation evidence

| mutation | result |
|---|---|
| derived board → live board (weak R7) | **survived** — drove the strengthening above |
| derived board → live board (strengthened R7) | fails: "the derivation did not take effect" |
| live board unparked | control reports `note - R7 control not exercised`, does not silently pass |

Restored after each; the checkout was never left mutated.
