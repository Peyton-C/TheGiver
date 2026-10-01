#!/bin/sh
# Builds "The Giver.app" into build/macos.
#
#   macos/bundle.sh            release build
#   macos/bundle.sh --install  also copies the app to /Applications
set -eu

cd "$(dirname "$0")/.."

# SwiftUI's macros ship with Xcode, not the Command Line Tools, so prefer
# Xcode when xcode-select points at the latter.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

swift build -c release --product TheGiver
bin="$(swift build -c release --show-bin-path)/TheGiver"

app="build/macos/The Giver.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/TheGiver"
cp macos/Info.plist "$app/Contents/Info.plist"

icon=assets/the_giver_icon/the_giver.icon
if [ -d "$icon" ]; then
    xcrun actool "$icon" \
        --compile "$app/Contents/Resources" \
        --app-icon the_giver \
        --enable-on-demand-resources NO \
        --development-region en \
        --target-device mac \
        --platform macosx \
        --minimum-deployment-target 26.0 \
        --output-partial-info-plist build/macos/icon.plist >/dev/null
fi

codesign --force --sign - "$app"
echo "Built $app"

if [ "${1:-}" = "--install" ]; then
    rm -rf "/Applications/The Giver.app"
    cp -R "$app" /Applications/
    echo "Installed to /Applications/The Giver.app"
fi
