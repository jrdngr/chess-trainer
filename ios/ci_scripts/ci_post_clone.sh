#!/bin/sh
# Xcode Cloud: the project is generated from project.yml, so make it after the clone.
set -e
brew install xcodegen
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
xcodegen generate
