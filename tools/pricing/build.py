"""Build the pawn-rate calculator page from its template and the measured runs.

Usage:
  python3 build.py              rebuild pawn-rates.html from runs.jsonl
  python3 build.py MEASURE_DIR  first merge MEASURE_DIR/out-*.jsonl (seeds from jobs.txt) into runs.jsonl
"""
import json, os, sys

here = os.path.dirname(os.path.abspath(__file__))
runs_path = os.path.join(here, "runs.jsonl")

def variant(args):
    a = " ".join(args)
    if "--miss" in a: return "miss"
    if "--adaptive" in a: return "adaptive"
    if "freeform" in a: return "freeform"
    return args[args.index("--strategy") + 1]

if len(sys.argv) > 1:
    src = sys.argv[1]
    rows = []
    for line in open(os.path.join(here, "jobs.txt")):
        seed, *args = line.split()
        path = os.path.join(src, f"out-{seed}.jsonl")
        if not os.path.exists(path): continue
        for run in open(path):
            r = json.loads(run)
            r["variant"] = variant(args)
            rows.append(r)
    with open(runs_path, "w") as f:
        for r in rows: f.write(json.dumps(r, sort_keys=True) + "\n")
else:
    rows = [json.loads(line) for line in open(runs_path)]

keep = ["variant", "strategy", "rating", "side", "start", "opening", "index", "playbookMoves", "prepMoves", "growthMoves", "otherMoves", "misses", "ending", "events"]
data = json.dumps([{k: r[k] for k in keep} for r in rows], separators=(",", ":"))
page = open(os.path.join(here, "pawn-rates.template.html")).read().replace("/*DATA*/[]", data)
open(os.path.join(here, "pawn-rates.html"), "w").write(page)
print(len(rows), "runs")
