#!/usr/bin/env python3
"""Put what the Swift ports answer into the golden cases, for an intended change in behavior.

    docker run --rm -e GOLDEN_WRITE=1 -v "$PWD":/src -w /src swift:6.4-noble swift test
    python3 Tests/SpecTests/Golden/rewrite.py

Run from `ios/`. The tests write `.golden-out/`; this rewrites only the cases whose
answer changed, line by line, and prints how many changed per function. Review the
diff before committing, and say in the commit message why the answers changed.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent
OUT = ROOT.parent.parent.parent / ".golden-out"


def same(a, b):
    if isinstance(a, bool) or isinstance(b, bool):
        return a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return a == b or abs(a - b) <= 1e-9 * max(1, abs(a), abs(b))
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    if isinstance(a, dict) and isinstance(b, dict):
        return all(same(a.get(k), b.get(k)) for k in set(a) | set(b))
    return a == b


def dump(value):
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False)


def rewrite_line(line, fields):
    """`fields` maps a key of the line's object to its new value."""
    stripped = line.rstrip("\n")
    comma = stripped.endswith(",")
    body = stripped.rstrip(",")
    indent = body[: len(body) - len(body.lstrip())]
    obj = json.loads(body)
    if all(same(obj.get(k), v) for k, v in fields.items()):
        return line, False
    for k, v in fields.items():
        obj[k] = v
    return indent + dump(obj) + ("," if comma else "") + "\n", True


def functions(area, got):
    path = ROOT / "cases" / "functions" / f"{area}.json"
    lines = path.read_text().splitlines(keepends=True)
    fn, i, changed = None, 0, {}
    for n, line in enumerate(lines):
        m = re.match(r'\s*"fn": "(.*)",?$', line.rstrip("\n"))
        if m:
            fn, i = m.group(1), 0
            continue
        if fn in got and line.lstrip().startswith('{"args"'):
            new, did = rewrite_line(line, {"out": got[fn][i]})
            lines[n] = new
            if did:
                changed[fn] = changed.get(fn, 0) + 1
            i += 1
    path.write_text("".join(lines))
    for fn, count in sorted(changed.items()):
        print(f"{area}: {fn}: {count} changed")


def scenarios(area, got):
    path = ROOT / "cases" / "scenarios" / f"{area}.json"
    lines = path.read_text().splitlines(keepends=True)
    name, i, changed = None, 0, {}
    for n, line in enumerate(lines):
        m = re.match(r'\s*"name": "(.*)",?$', line.rstrip("\n"))
        if m:
            name, i = m.group(1), 0
            continue
        if name in got and line.lstrip().startswith('{"call"'):
            if i < len(got[name]):
                new, did = rewrite_line(line, got[name][i])
                lines[n] = new
                if did:
                    changed[name] = changed.get(name, 0) + 1
            i += 1
    path.write_text("".join(lines))
    for name, count in sorted(changed.items()):
        print(f"scenario {area}: {name}: {count} steps changed")


def main():
    if not OUT.exists():
        sys.exit(f"nothing in {OUT}: run the tests with GOLDEN_WRITE=1 first")
    for f in sorted(OUT.glob("*.json")):
        kind, area = f.stem.split("-", 1)
        got = json.loads(f.read_text())
        (functions if kind == "functions" else scenarios)(area, got)


main()
