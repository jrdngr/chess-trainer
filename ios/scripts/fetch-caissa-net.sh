#!/bin/sh
# Download Caissa's network into Sources/Engine/CaissaNet/caissa.pnn, the
# version the vendored search in Sources/Caissa was built against. Skips the
# download when the file is already there and matches.
set -e
NET_VERSION=eval-ml-11a-100B-spsa-transplant
SHA256=bc3df8d32b584f01e21f0f3f9515b3fc0f97fa0ca59b9b5991f333ed5b437b6b
DIR="$(cd "$(dirname "$0")/.." && pwd)/Sources/Engine/CaissaNet"
FILE="$DIR/caissa.pnn"

sum() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

if [ -f "$FILE" ] && [ "$(sum "$FILE")" = "$SHA256" ]; then
  echo "Caissa network already in place"
  exit 0
fi
curl -fsSL --retry 3 --retry-delay 2 -o "$FILE.tmp" \
  "https://github.com/Witek902/Caissa-Nets/releases/download/$NET_VERSION/$NET_VERSION.pnn"
if [ "$(sum "$FILE.tmp")" != "$SHA256" ]; then
  echo "Caissa network checksum mismatch" >&2
  rm -f "$FILE.tmp"
  exit 1
fi
mv -f "$FILE.tmp" "$FILE"
echo "Caissa network $NET_VERSION downloaded"
