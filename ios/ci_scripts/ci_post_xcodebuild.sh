#!/bin/sh
# Xcode Cloud: after a plain build (the dev workflow), run the Swift package's
# tests. Archives (main's TestFlight workflow) skip them. A failing test fails
# the build.
set -e
if [ "$CI_XCODEBUILD_ACTION" != "build" ]; then
  echo "Skipping swift test for action: $CI_XCODEBUILD_ACTION"
  exit 0
fi
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
swift test
