#!/usr/bin/env python3
"""Bounded public evidence gate. Tests: test_feedback_report.sh::details_*.

These lexical filters cannot establish confidentiality or factual correctness;
the session owner must review the draft before invoking the reporter.
"""
import hashlib
import json
import os
import re
import stat
import sys

CONTEXT = {
    'harness-malfunction': ('failure', 'project_health'),
    'contradictory-instruction': ('instruction_a', 'instruction_b'),
    'workaround': ('documented_path', 'failed_because', 'alternative'),
    'missing-capability': ('occurrences', 'workflow_gap', 'impact'),
}
COMMON = ('summary', 'observed', 'expected', 'reproduction', 'evidence')
SECRET = re.compile(r'gh[pousr]_[A-Za-z0-9]+|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9_-]+|AKIA[A-Z0-9]{16}|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')
UNSAFE = re.compile(r'-----[^\n]*PRIVATE KEY-----|\b(?:token|secret|password|api_key|authorization)\s*[:=]\s*\S|[A-Za-z][A-Za-z0-9+.-]*://|\b(?:https?|ftp|file|mailto|data|ssh):|[A-Za-z]:[\\/]|\\\\|~[/\\]|(?:^|[/\\\s])\.\.(?:[/\\\s]|$)|<!--|-->|harness-feedback:', re.I)
PATH = re.compile(r'(?<![\w./~\\-])(?:[\w.~\\-]*[/\\])+[\w.~\\/-]*(?::\d+)?')
PLACEHOLDER = re.compile(r'\b(?:todo|tbd|unknown|n\s+a|none|not\s+available|pending|placeholder|see\s+logs|see\s+notes|redacted)\b', re.I)


def pairs(items):
    obj = {}
    for key, value in items:
        if key in obj:
            raise ValueError('details-file: duplicate key')
        obj[key] = value
    return obj


def substantive(value, metadata):
    value = re.sub(r'\[REDACTED-[^\]]*\]', ' ', value, flags=re.I)
    for token in sorted(metadata, key=len, reverse=True):
        if token:
            value = re.sub(r'(?<!\w)' + re.escape(token) + r'(?!\w)', ' ', value, flags=re.I)
    value = re.sub(r'[^\w]+', ' ', value, flags=re.UNICODE)
    value = PLACEHOLDER.sub(' ', value)
    return ' '.join(value.split())


def validate(path, trigger, files, metadata):
    if not path:
        raise ValueError('details-file: missing')
    try:
        # Nonblocking open also avoids hanging on a FIFO swapped in after inspection.
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        with os.fdopen(fd, 'rb') as stream:
            if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                raise ValueError('details-file: not a regular file')
            raw = stream.read(16385)
    except OSError:
        raise ValueError('details-file: missing or unreadable') from None
    if len(raw) > 16384:
        raise ValueError('details-file: exceeds 16384 bytes')
    try:
        obj = json.loads(raw.decode('utf-8'), object_pairs_hook=pairs)
    except (UnicodeError, json.JSONDecodeError):
        raise ValueError('details-file: invalid UTF-8 JSON') from None
    errors = []
    accepted = {}
    metadata = metadata + list(COMMON) + list(CONTEXT[trigger]) + ['context', 'version', 'trigger', 'symptom', 'files', 'file', 'command', 'role', 'phase', 'exit', 'exit code']

    def fields(data, keys, prefix, output):
        if not isinstance(data, dict):
            errors.append(prefix.rstrip('.') + ': expected object')
            return
        if set(data) - set(keys):
            errors.append((prefix.rstrip('.') or 'details-file') + ': unknown keys')
        for key in keys:
            field = prefix + key
            if key not in data:
                errors.append(field + ': missing')
                continue
            value = data[key]
            if not isinstance(value, str):
                errors.append(field + ': expected string')
                continue
            value = value.strip()
            limit = 240 if key == 'summary' else 1000 if prefix else 1500
            if not 20 <= len(value) <= limit:
                errors.append(field + ': length outside 20–' + str(limit))
            if any((ord(c) < 32 and c not in '\n\t') or 127 <= ord(c) <= 159 or 0x202A <= ord(c) <= 0x202E or 0x2066 <= ord(c) <= 0x2069 or 0xD800 <= ord(c) <= 0xDFFF for c in value):
                errors.append(field + ': forbidden control or surrogate')
            paths = PATH.findall(value)
            if SECRET.search(value) or UNSAFE.search(value) or any(re.sub(r':\d+$', '', p) not in files for p in paths):
                errors.append(field + ': unsafe content')
            # The redactor is a second layer; unsafe inputs are rejected above.
            clean = SECRET.sub('[REDACTED-SECRET]', value)
            clean = re.sub(r'/(?:home|Users|tmp|private)/\S+', '[REDACTED-PATH]', clean)
            if len(substantive(clean, metadata)) < 20:
                errors.append(field + ': insufficient substantive content')
            output[key] = clean
            if key == 'evidence' and not any(re.search(r'(?<![\w./~\\-])' + re.escape(p) + r'(?::\d+)?(?![\w./\\-])', clean) for p in files):
                errors.append(field + ': accepted file reference missing')

    if not isinstance(obj, dict):
        raise ValueError('details-file: expected object')
    fields({k: v for k, v in obj.items() if k != 'context'}, COMMON, '', accepted)
    if 'context' not in obj:
        errors.append('context: missing')
    else:
        accepted['context'] = {}
        fields(obj['context'], CONTEXT[trigger], 'context.', accepted['context'])
    if errors:
        raise ValueError('\n'.join(errors))
    return accepted


def main():
    path, trigger, symptom, files_path, out = sys.argv[1:6]
    files = sorted(set(open(files_path, encoding='utf-8').read().splitlines()))
    details = validate(path, trigger, files, [trigger, symptom] + files + sys.argv[6:])
    def canonical(value):
        return {k: canonical(v) for k, v in value.items()} if isinstance(value, dict) else ' '.join(value.split())
    identity = dict(trigger=trigger, symptom=symptom, files=files, details=canonical(details))
    digest = hashlib.sha256(json.dumps(identity, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()[:16]
    with open(out + '/digest', 'w') as stream:
        stream.write(digest)
    with open(out + '/details.json', 'w', encoding='utf-8') as stream:
        json.dump(details, stream, ensure_ascii=False, indent=2)
    with open(out + '/details.md', 'w', encoding='utf-8') as stream:
        for key, title in zip(COMMON, ('Summary', 'Observed', 'Expected', 'Reproduction or inspection', 'Evidence')):
            stream.write('\n## ' + title + '\n\n')
            stream.write('\n'.join('    ' + line for line in details[key].splitlines()) + '\n')
        stream.write('\n## Trigger context\n')
        for key, value in details['context'].items():
            stream.write('\n### ' + key.replace('_', ' ').capitalize() + '\n\n')
            stream.write('\n'.join('    ' + line for line in value.splitlines()) + '\n')


if __name__ == '__main__':
    try:
        main()
    except ValueError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except Exception:
        print('details-file: parser unavailable or read failure', file=sys.stderr)
        sys.exit(1)
