#!/bin/bash
set -e

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
