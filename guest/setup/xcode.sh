#!/bin/zsh -l
# Xcode from the base image: first-launch setup and an iOS simulator runtime.
set -euxo pipefail

xcodebuild -version >/dev/null || { echo "No Xcode in this base image; use a macos-*-xcode BASE_IMAGE" >&2; exit 1; }
sudo xcodebuild -runFirstLaunch
if ! xcrun simctl list runtimes | grep -q '^iOS'; then
  xcodebuild -downloadPlatform iOS
fi

echo "xcode: $(xcodebuild -version | head -1)" >> "$SANDBOX_INFO"
