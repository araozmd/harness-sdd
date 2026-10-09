#!/usr/bin/env python3
"""Read a complete feedback snapshot. Issue text is data, never executable input.

Source-only; marker grammar is shared with feedback-labeler.sh (ADR-0006).
Executable contracts: tests/test_feedback_triage.sh reader.
"""
import argparse
import json
import re
import subprocess
import sys

MARKER = re.compile(
    r'<!-- harness-feedback:v1 host=[A-Za-z0-9._-]+ '
    r'version=[0-9]+\.[0-9]+\.[0-9]+ '
    r'trigger=(harness-malfunction|contradictory-instruction|workaround|missing-capability) -->'
)


def classify(body):
    first, _, rest = body.partition('\n')
    match = MARKER.fullmatch(first)
    if not match:
        return False, None, 'Missing or unsupported first-line v1 marker'
    if 'harness-feedback:' in rest:
        return False, None, 'Duplicate harness-feedback token'
    return True, match.group(1), None


def gh(*args):
    result = subprocess.run(['gh', *args], capture_output=True, text=True)
    if result.returncode:
        # Avoid echoing remote-controlled output or credentials into diagnostics.
        raise ValueError('gh ' + args[0] + ' failed (exit ' + str(result.returncode) + ')')
    return result.stdout


def snapshot(repository):
    if not re.fullmatch(r'[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+', repository):
        raise ValueError('--repo requires explicit host/owner/repo')
    host, owner, repo = repository.split('/')
    gh('auth', 'status', '--hostname', host)
    issues = []
    page = 1
    while True:
        raw = gh('api', '--hostname', host, '--method', 'GET',
                 f'repos/{owner}/{repo}/issues', '-f', 'state=open',
                 '-f', 'labels=harness-feedback', '-F', 'per_page=100',
                 '-F', f'page={page}')
        try:
            batch = json.loads(raw)
        except json.JSONDecodeError as error:
            raise ValueError(f'malformed JSON on page {page}') from error
        if not isinstance(batch, list):
            raise ValueError(f'expected issue array on page {page}')
        for item in batch:
            if not isinstance(item, dict):
                raise ValueError(f'malformed issue on page {page}')
            if 'pull_request' in item:
                continue
            if (type(item.get('number')) is not int or item['number'] <= 0
                    or not isinstance(item.get('title'), str)
                    or not isinstance(item.get('html_url'), str)
                    or not isinstance(item.get('body'), (str, type(None)))):
                raise ValueError(f'malformed issue fields on page {page}')
            body = item.get('body') or ''
            valid, trigger, diagnostic = classify(body)
            issues.append(dict(number=item['number'], title=item['title'], body=body,
                               url=item['html_url'], valid=valid, trigger=trigger,
                               diagnostic=diagnostic))
        if len(batch) < 100:
            break
        page += 1
    return dict(repository=repository, host=host, owner=owner, repo=repo,
                complete=True, issues=issues)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True)
    args = parser.parse_args()
    try:
        data = snapshot(args.repo)
    except (OSError, ValueError) as error:
        print(f'feedback-triage: {error}', file=sys.stderr)
        return 1
    print(json.dumps(data, ensure_ascii=True, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
