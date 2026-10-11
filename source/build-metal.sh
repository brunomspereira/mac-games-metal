#!/bin/zsh
set -eu
task_source_dir=${0:A:h}
task_output_dir=${task_source_dir:h}
task_trial="$task_output_dir/MetalTrial"
task_app="$task_trial/Mac Games Metal Test.app"
test -f "$task_trial/LauncherData/Game/GTAIV/d3d9.dll"
test -f "$task_trial/Runtime/WineCX/lib/wine/x86_64-unix/d9mtmetal.so"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
cp "$task_source_dir/MacGames.icns" "$task_app/Contents/Resources/MacGames.icns"
clang -arch x86_64 -O2 "$task_source_dir/metal-smoke.m" -I "$task_source_dir" \
  -o "$task_app/Contents/Resources/MetalSmoke" -framework Metal -framework Foundation
codesign --force --sign - "$task_app/Contents/Resources/MetalSmoke"
swiftc -swift-version 5 -O -D METAL_TRIAL -module-cache-path "$task_output_dir/../work/swift-cache" \
  "$task_source_dir/main.swift" -o "$task_app/Contents/MacOS/MacGames" -framework AppKit
/usr/bin/python3 - "$task_app/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as output:
    plistlib.dump({
        'CFBundleExecutable': 'MacGames',
        'CFBundleIdentifier': 'local.macgames.launcher.metal-test',
        'CFBundleName': 'Mac Games Metal Test',
        'CFBundleIconFile': 'MacGames.icns',
        'CFBundlePackageType': 'APPL',
        'CFBundleVersion': '1',
        'CFBundleShortVersionString': '0.1',
        'LSMinimumSystemVersion': '14.0',
        'NSHighResolutionCapable': True,
    }, output)
PY
codesign --force --sign - "$task_app"
"$task_app/Contents/MacOS/MacGames" --self-test
/usr/bin/python3 "$task_source_dir/check-runtime.py" "$task_trial"
