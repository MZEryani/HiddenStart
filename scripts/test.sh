#!/bin/bash
set -e

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode-27.0.0.app" ]; then
  export DEVELOPER_DIR="/Applications/Xcode-27.0.0.app/Contents/Developer"
fi

# If Xcode project exists, test via xcodebuild
if [ -f "HiddenStart.xcodeproj/project.pbxproj" ]; then
  xcodebuild -project HiddenStart.xcodeproj -scheme HiddenStart -destination 'platform=macOS' test
else
  # Fallback to SPM
  swift test \
    -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
    -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
    -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib \
    "$@"
fi
