#!/usr/bin/env python3
"""Read-only dependency diagnostics for the local TaskStore (E16-F01)."""

import json
import re
import sys
from collections import deque


REASON_TEXT = {
    "dependency-cycle": "dependency cycle ({kind}): {path}",
    "gated-epic": "epic {epic_id} is draft",
    "unmet-dependency": "blocking dependencies: {blockers}",
    "human-gate": "spec-ready requires approval | gated quick fix requires approval",
    "owner-excluded": "effective owner={owner}",
    "owner-unresolved": "workflow.identity={identity}",
    "no-candidates": "no actionable work [no-candidates]: {terminal}",
}
HUMAN_GATE_TEXT = (
    "spec-ready requires approval",
    "gated quick fix requires approval",
)
OWNER_UNRESOLVED_TEXT = (
    "workflow.identity=<empty>",
    "workflow.identity=@me lookup failed",
    "workflow.identity=self lookup failed",
)
NO_CANDIDATES_TEXT = (
    "no actionable work [no-candidates]: board has no features",
    "no actionable work [no-candidates]: all features are done",
)

_NODE_RE = re.compile(r"^E(\d+)-F(\d+)(?:@([a-z0-9-]+))?$")


def node_sort_key(node_id):
    """Return the canonical numeric feature/slice ordering key."""
    match = _NODE_RE.match(node_id) if isinstance(node_id, str) else None
    if not match:
        return (1, str(node_id))
    epic, feature, repo = match.groups()
    return (0, int(epic), int(feature), repo is not None, repo or "")


def _nodes(board, kind):
    for epic in board.get("epics") or []:
        if not isinstance(epic, dict):
            continue
        for feature in epic.get("features") or []:
            if not isinstance(feature, dict):
                continue
            if kind == "feature":
                yield feature
            elif kind == "slice":
                for slice_record in feature.get("slices") or []:
                    if isinstance(slice_record, dict):
                        yield slice_record


def build_dependency_graph(board, kind):
    """Build one disjoint graph and return (adjacency, unresolved_dependencies)."""
    if kind not in ("feature", "slice"):
        raise ValueError("graph kind must be 'feature' or 'slice'")
    records = {
        record["id"]: record
        for record in _nodes(board, kind)
        if isinstance(record.get("id"), str)
    }
    adjacency = {}
    unresolved = {}
    for node_id in sorted(records, key=node_sort_key):
        dependencies = records[node_id].get("depends_on") or []
        resolved = sorted(
            {dep for dep in dependencies if dep in records}, key=node_sort_key
        )
        missing = sorted(
            {dep for dep in dependencies if dep not in records}, key=node_sort_key
        )
        adjacency[node_id] = resolved
        if missing:
            unresolved[node_id] = missing
    return adjacency, unresolved


def _strongly_connected_components(adjacency):
    """Return SCCs using iterative Kosaraju traversal."""
    ordered = sorted(adjacency, key=node_sort_key)
    seen = set()
    finish = []
    for start in ordered:
        if start in seen:
            continue
        seen.add(start)
        stack = [(start, 0)]
        while stack:
            node, index = stack[-1]
            neighbors = adjacency[node]
            if index < len(neighbors):
                neighbor = neighbors[index]
                stack[-1] = (node, index + 1)
                if neighbor not in seen:
                    seen.add(neighbor)
                    stack.append((neighbor, 0))
            else:
                finish.append(node)
                stack.pop()

    reverse = {node: [] for node in adjacency}
    for node, neighbors in adjacency.items():
        for neighbor in neighbors:
            reverse[neighbor].append(node)
    for node in reverse:
        reverse[node].sort(key=node_sort_key)

    seen.clear()
    components = []
    for start in reversed(finish):
        if start in seen:
            continue
        seen.add(start)
        component = []
        stack = [start]
        while stack:
            node = stack.pop()
            component.append(node)
            for neighbor in reversed(reverse[node]):
                if neighbor not in seen:
                    seen.add(neighbor)
                    stack.append(neighbor)
        components.append(sorted(component, key=node_sort_key))
    return components


def _cycle_witness(adjacency, component):
    allowed = set(component)
    root = min(component, key=node_sort_key)
    neighbors = [node for node in adjacency[root] if node in allowed]
    if root in neighbors:
        return [root, root]
    first = min(neighbors, key=node_sort_key)

    queue = deque([first])
    previous = {first: None}
    while queue:
        node = queue.popleft()
        if node == root:
            break
        for neighbor in adjacency[node]:
            if neighbor in allowed and neighbor not in previous:
                previous[neighbor] = node
                queue.append(neighbor)

    path = []
    node = root
    while node is not None:
        path.append(node)
        node = previous[node]
    path.reverse()
    return [root] + path


def find_dependency_cycles(board):
    """Return one deterministic closed witness for each cyclic SCC."""
    records = []
    for kind in ("feature", "slice"):
        adjacency, _ = build_dependency_graph(board, kind)
        for component in _strongly_connected_components(adjacency):
            cyclic = len(component) > 1 or (
                len(component) == 1 and component[0] in adjacency[component[0]]
            )
            if cyclic:
                records.append(
                    {
                        "code": "dependency-cycle",
                        "kind": kind,
                        "path": _cycle_witness(adjacency, component),
                    }
                )
    records.sort(
        key=lambda record: (
            0 if record["kind"] == "feature" else 1,
            tuple(node_sort_key(node) for node in record["path"]),
        )
    )
    return records


def format_cycle(record):
    return "%s\t%s\t%s" % (
        record["code"],
        record["kind"],
        " -> ".join(record["path"]),
    )


def _main(argv):
    if len(argv) != 2 or argv[0] != "cycles":
        print("usage: task-diagnostics.py cycles <tasks-json>", file=sys.stderr)
        return 2
    path = argv[1]
    try:
        with open(path, encoding="utf-8") as source:
            board = json.load(source)
    except (OSError, ValueError) as error:
        print("task diagnostics: cannot read %s: %s" % (path, error), file=sys.stderr)
        return 1
    try:
        for record in find_dependency_cycles(board):
            print(format_cycle(record))
    except (AttributeError, TypeError, ValueError) as error:
        print("task diagnostics: cannot analyze %s: %s" % (path, error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
