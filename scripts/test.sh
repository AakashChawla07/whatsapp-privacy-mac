#!/usr/bin/env bash
# Runs the test suite. With only the Command Line Tools installed (no Xcode), SwiftPM does not
# add the Swift Testing framework search paths itself, so they are passed explicitly here.
set -euo pipefail

cd "$(dirname "$0")/.."

CLT_DEV="/Library/Developer/CommandLineTools/Library/Developer"
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools && -d "$CLT_DEV/Frameworks/Testing.framework" ]]; then
    FW="$CLT_DEV/Frameworks"
    LIB="$CLT_DEV/usr/lib"
    exec swift test \
        -Xswiftc -F -Xswiftc "$FW" \
        -Xlinker -F -Xlinker "$FW" \
        -Xlinker -rpath -Xlinker "$FW" \
        -Xlinker -rpath -Xlinker "$LIB" \
        "$@"
fi

exec swift test "$@"
