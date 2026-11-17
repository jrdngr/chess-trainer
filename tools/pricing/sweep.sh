#!/usr/bin/env bash
# Play every job in jobs.txt headless (one `playbook measure` per line: seed, then options)
# and write ios/.measure/out-SEED.jsonl. Run from the repo root; on Linux it uses Docker.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$root/ios/.measure"
while read -r seed args; do
  [ -z "$seed" ] && continue
  rm -f "$root/ios/.measure/out-$seed.jsonl"
  cmd="swift run -c release playbook measure --seed $seed $args --out .measure/out-$seed.jsonl"
  if command -v swift >/dev/null; then (cd "$root/ios" && eval "$cmd")
  else docker run --rm -v "$root/ios":/src -w /src swift:6.4-noble bash -c "$cmd"; fi
done < "$(dirname "$0")/jobs.txt"
python3 "$(dirname "$0")/build.py" "$root/ios/.measure"
