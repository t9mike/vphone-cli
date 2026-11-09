#!/bin/zsh
set -euo pipefail
tests=${0:a:h}
repo=${tests:h:h:h}
out=$repo/.build/standby-tests
mkdir -p "$out"
xcrun --sdk macosx swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
    -module-cache-path "$out/module-cache" \
    "$tests:h/UI/UserInterface/Panels/Fold/VPhoneFoldModel.swift" \
    "$tests:h/UI/GuestCommunication/VPhoneGuestControlFold.swift" \
    "$tests/StandByTests.swift" -o "$out/StandByTests"
"$out/StandByTests"
