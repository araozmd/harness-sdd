#!/usr/bin/env python3
"""telemetry-report.py — roll up the harness telemetry log into text/markdown tables.

Zero-dependency (python3 stdlib only). Reads the append-only JSONL telemetry log written
by the Orchestrator (see agents/orchestrator.md "## Telemetry") and emits rollup tables
to stdout. Token/USD cost is OUT of scope: the reserved `cost` record field is ignored.

Usage:
    python3 tools/telemetry-report.py [GRANULARITY] [--log PATH]

GRANULARITY is one of:
    daily weekly monthly quarterly semester annual   calendar rollups
    session                                           the current session (since the
                                                      most recent session-start marker)
With no GRANULARITY, prints an all-granularity summary.

The default log path is <HARNESS_DIR>/telemetry.jsonl, where HARNESS_DIR is the dir this
script's parent (the harness root) lives in — the same path init.sh computes. Override
with --log. An absent or empty log exits 0 with a "no telemetry yet" notice.
"""

import argparse
import json
import os
import re
import statistics
import sys
from datetime import datetime, timezone

PHASES = ["architect", "builder", "reviewer", "scout", "inception", "slice-dispatch"]
GRANULARITIES = ["daily", "weekly", "monthly", "quarterly", "semester", "annual"]
NO_DATA = "no telemetry yet"


def _harness_dir():
    """HARNESS_DIR is this script's grandparent dir (tools/ lives under the harness
    root, beside init.sh and harness.config.yaml)."""
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(here)  # tools/ -> harness root


def _configured_log(harness_dir):
    """The `telemetry.log` override from harness.config.yaml, or None. Scoped to the
    top-level `telemetry:` block (so an unrelated `log:` elsewhere is never matched),
    mirroring how the writer (agents/orchestrator.md) resolves it. Zero-dep: a minimal
    regex parse, no YAML library. Resolved under HARNESS_DIR unless absolute."""
    cfg = os.path.join(harness_dir, "harness.config.yaml")
    try:
        with open(cfg) as f:
            lines = f.read().splitlines()
    except OSError:
        return None
    in_telemetry = False
    for ln in lines:
        if re.match(r"^telemetry:\s*(#.*)?$", ln):
            in_telemetry = True
            continue
        if in_telemetry and re.match(r"^[^\s#]", ln):  # next top-level key ends the block
            break
        if in_telemetry:
            m = re.match(r"^\s+log:\s*(.*)$", ln)
            if m:
                # Mirror the installer's _cfg_telemetry_log awk EXACTLY so reader and
                # writer agree: strip a trailing comment, then a surrounding quote of
                # EITHER kind (single or double).
                val = re.sub(r"\s*#.*$", "", m.group(1)).strip()
                val = re.sub(r"^['\"]|['\"]$", "", val).strip()
                if not val:
                    return None
                return val if os.path.isabs(val) else os.path.join(harness_dir, val)
    return None


def default_log_path():
    """The reader resolves the SAME path the writer does: the configured
    `telemetry.log` if set, else <HARNESS_DIR>/telemetry.jsonl. This keeps the
    end-of-session summary and the writer in sync even under a config override."""
    harness_dir = _harness_dir()
    return _configured_log(harness_dir) or os.path.join(harness_dir, "telemetry.jsonl")


def parse_ts(value):
    """Parse an ISO-8601 UTC timestamp (e.g. 2026-06-06T14:03:21Z) -> aware datetime.
    Returns None on anything unparseable (best-effort reader)."""
    if not isinstance(value, str):
        return None
    v = value.strip()
    if v.endswith("Z"):
        v = v[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(v)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def read_records(path):
    """Read the JSONL log, skipping malformed lines (never abort). Returns a list of
    dicts. A missing file yields an empty list (absence is not an error)."""
    records = []
    try:
        f = open(path, "r", encoding="utf-8")
    except OSError:
        return records
    with f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except (ValueError, TypeError):
                continue
            if isinstance(obj, dict):
                records.append(obj)
    return records


def phase_records(records):
    """Valid phase records: a phase span needs a recognized phase, a parseable start,
    and a non-negative numeric duration_s."""
    out = []
    for r in records:
        if r.get("type") != "phase":
            continue
        ph = r.get("phase")
        if ph not in PHASES:
            continue
        start = parse_ts(r.get("start"))
        if start is None:
            continue
        dur = r.get("duration_s")
        if not isinstance(dur, (int, float)) or isinstance(dur, bool):
            continue
        if dur < 0:
            continue
        out.append({"phase": ph, "start": start, "duration_s": dur,
                    "round": r.get("round"), "slice": r.get("slice")})
    return out


def gate_closes(records):
    """Gate close records carrying a human_latency_s and an autonomous flag."""
    out = []
    for r in records:
        if r.get("type") != "gate" or r.get("event") != "in_progress":
            continue
        when = parse_ts(r.get("in_progress_at"))
        lat = r.get("human_latency_s")
        if not isinstance(lat, (int, float)) or isinstance(lat, bool):
            continue
        if lat < 0:
            continue
        out.append({"when": when, "human_latency_s": lat,
                    "autonomous": bool(r.get("autonomous", False))})
    return out


# ── calendar bucketing ────────────────────────────────────────────────────────
def bucket_key(dt, granularity):
    if dt is None:
        return None
    if granularity == "daily":
        return dt.strftime("%Y-%m-%d")
    if granularity == "weekly":
        iso = dt.isocalendar()
        return "%04d-W%02d" % (iso[0], iso[1])
    if granularity == "monthly":
        return dt.strftime("%Y-%m")
    if granularity == "quarterly":
        return "%04d-Q%d" % (dt.year, (dt.month - 1) // 3 + 1)
    if granularity == "semester":
        return "%04d-H%d" % (dt.year, 1 if dt.month <= 6 else 2)
    if granularity == "annual":
        return "%04d" % dt.year
    return None


def human_latency_stats(closes):
    """mean + median over human (non-autonomous) gate closes only (R10/R16)."""
    human = [c["human_latency_s"] for c in closes if not c["autonomous"]]
    if not human:
        return None, None, 0, sum(1 for c in closes if c["autonomous"])
    mean = statistics.mean(human)
    median = statistics.median(human)
    return mean, median, len(human), sum(1 for c in closes if c["autonomous"])


def fmt_dur(s):
    """Render a duration (seconds) as HH:MM:SS so the tables read in clock units
    instead of raw seconds. Hours are NOT capped at 24 (a multi-day gate latency
    shows e.g. 48:00:00), keeping the format unambiguous and lexically sortable."""
    s = int(round(s))
    h, rem = divmod(s, 3600)
    m, sec = divmod(rem, 60)
    return "%02d:%02d:%02d" % (h, m, sec)


def render_period(label, phases, closes):
    """Render one period's markdown block: per-phase breakdown + latency."""
    lines = []
    lines.append("### %s" % label)
    lines.append("")
    total = sum(p["duration_s"] for p in phases)
    lines.append("- Total autonomous agent time: %s" % fmt_dur(total))
    lines.append("- Phase count: %d" % len(phases))
    lines.append("")
    lines.append("| phase | count | total duration |")
    lines.append("|---|---|---|")
    for ph in PHASES:
        sel = [p for p in phases if p["phase"] == ph]
        if not sel:
            continue
        lines.append("| %s | %d | %s |"
                     % (ph, len(sel), fmt_dur(sum(p["duration_s"] for p in sel))))
    lines.append("| **total** | %d | %s |" % (len(phases), fmt_dur(total)))
    lines.append("")
    mean, median, nhuman, nauto = human_latency_stats(closes)
    if mean is None:
        lines.append("- Human-gate latency: (no human-reviewed gate closes)")
    else:
        lines.append("- Human-gate latency (n=%d): mean %s, median %s"
                     % (nhuman, fmt_dur(mean), fmt_dur(median)))
    if nauto:
        lines.append("- Autonomous gate transitions (excluded from latency): %d" % nauto)
    lines.append("")
    return "\n".join(lines)


def report_granularity(phases, closes, granularity, out):
    out.append("## %s rollup" % granularity)
    out.append("")
    buckets = {}
    for p in phases:
        k = bucket_key(p["start"], granularity)
        buckets.setdefault(k, {"phases": [], "closes": []})["phases"].append(p)
    for c in closes:
        k = bucket_key(c["when"], granularity)
        if k is None:
            continue
        buckets.setdefault(k, {"phases": [], "closes": []})["closes"].append(c)
    if not buckets:
        out.append("_%s_" % NO_DATA)
        out.append("")
        return
    for label in sorted(buckets):
        out.append(render_period(label, buckets[label]["phases"],
                                 buckets[label]["closes"]))


# ── session view (R26, R27) ───────────────────────────────────────────────────
def latest_session_start(records):
    latest = None
    for r in records:
        if r.get("type") != "session-start":
            continue
        ts = parse_ts(r.get("started_at"))
        if ts is None:
            continue
        if latest is None or ts > latest:
            latest = ts
    return latest


def report_session(records, out):
    marker = latest_session_start(records)
    phases = phase_records(records)
    closes = gate_closes(records)
    if marker is not None:
        phases = [p for p in phases if p["start"] >= marker]
        closes = [c for c in closes if c["when"] is not None and c["when"] >= marker]
    if not phases and not closes:
        out.append("_%s_" % NO_DATA)
        out.append("")
        return
    out.append("## Session summary")
    out.append("")
    if marker is not None:
        out.append("_Scope: records at/after the latest session-start marker "
                   "(%s)._" % marker.strftime("%Y-%m-%dT%H:%M:%SZ"))
        out.append("")
    # per-phase durations
    out.append("| phase | count | total duration |")
    out.append("|---|---|---|")
    for ph in PHASES:
        sel = [p for p in phases if p["phase"] == ph]
        if not sel:
            continue
        out.append("| %s | %d | %s |"
                   % (ph, len(sel), fmt_dur(sum(p["duration_s"] for p in sel))))
    total = sum(p["duration_s"] for p in phases)
    out.append("| **total** | %d | %s |" % (len(phases), fmt_dur(total)))
    out.append("")
    out.append("- Total autonomous agent time: %s" % fmt_dur(total))
    # build<->review round count = max round seen on builder/reviewer phases
    rounds = [p["round"] for p in phases
              if p["phase"] in ("builder", "reviewer")
              and isinstance(p["round"], int) and not isinstance(p["round"], bool)]
    round_count = max(rounds) if rounds else 0
    out.append("- Build/review rounds: %d" % round_count)
    mean, median, nhuman, nauto = human_latency_stats(closes)
    if mean is None:
        out.append("- Human-gate latency: (none observed)")
    else:
        out.append("- Human-gate latency (n=%d): mean %s, median %s"
                   % (nhuman, fmt_dur(mean), fmt_dur(median)))
    if nauto:
        out.append("- Autonomous gate transitions (excluded from latency): %d" % nauto)
    out.append("")


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Roll up the harness telemetry log into text/markdown tables.")
    parser.add_argument("granularity", nargs="?", default=None,
                        choices=GRANULARITIES + ["session"],
                        help="rollup granularity; omit for an all-granularity summary")
    parser.add_argument("--log", default=None,
                        help="path to the telemetry JSONL log "
                             "(default: <HARNESS_DIR>/telemetry.jsonl)")
    args = parser.parse_args(argv)

    log_path = args.log or default_log_path()
    records = read_records(log_path)

    if not records:
        print(NO_DATA)
        return 0

    out = []
    if args.granularity == "session":
        report_session(records, out)
    elif args.granularity is None:
        phases = phase_records(records)
        closes = gate_closes(records)
        out.append("# Telemetry summary (all granularities)")
        out.append("")
        for g in GRANULARITIES:
            report_granularity(phases, closes, g, out)
    else:
        phases = phase_records(records)
        closes = gate_closes(records)
        report_granularity(phases, closes, args.granularity, out)

    text = "\n".join(out).rstrip()
    if not text:
        print(NO_DATA)
        return 0
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
