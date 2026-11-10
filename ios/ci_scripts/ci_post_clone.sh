#!/bin/sh
# Xcode Cloud: the project is generated from project.yml, so make it after the clone.
#
# No Homebrew: Xcode Cloud's network can't reach ghcr.io, where brew's bottles
# and its Ruby live. XcodeGen comes from its GitHub release, and failing that
# is built from source (a clone from github.com, which the build already uses).
set -e
XCODEGEN_VERSION=2.46.0
TOOLS="${TMPDIR:-/tmp}/xcodegen-tools"
mkdir -p "$TOOLS"

XCODEGEN=""
if curl -fsSL --retry 3 -o "$TOOLS/xcodegen.zip" \
  "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"; then
  unzip -q -o "$TOOLS/xcodegen.zip" -d "$TOOLS"
  XCODEGEN="$TOOLS/xcodegen/bin/xcodegen"
fi

if [ ! -x "$XCODEGEN" ]; then
  echo "XcodeGen release download failed; building $XCODEGEN_VERSION from source"
  rm -rf "$TOOLS/src"
  git clone --depth 1 --branch "$XCODEGEN_VERSION" https://github.com/yonaskolb/XcodeGen.git "$TOOLS/src"
  (cd "$TOOLS/src" && swift build -c release --product xcodegen)
  XCODEGEN="$TOOLS/src/.build/release/xcodegen"
fi

"$XCODEGEN" --version
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
# Caissa's network is fetched at build time, not kept in git.
./scripts/fetch-caissa-net.sh
"$XCODEGEN" generate
