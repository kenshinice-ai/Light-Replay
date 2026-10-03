#!/usr/bin/env bash
# Pulls every user-facing string the compiler finds into ios/PropertyReplay/Localizable.xcstrings and lists the keys
# that still have no Simplified Chinese.
#
#   ./scripts/strings-sync.sh
#
# Why a script: Xcode's IDE updates a string catalog while it builds, but `xcodebuild` only writes the per-file
# .stringsdata that the IDE merges. `xcstringstool sync` does that merge. The packages (PropertyModel, CaptureCore)
# keep hand-written catalogs next to their sources; the compiler does not extract for them.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${PROPERTYREPLAY_BUILD_ROOT:-$HOME/Library/Caches/propertyreplay}/DerivedData-strings"
CATALOG="$ROOT/ios/PropertyReplay/Localizable.xcstrings"

xcodebuild build -project "$ROOT/ios/PropertyReplay.xcodeproj" -scheme PropertyReplay \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED" 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u
OBJECTS="$(find "$DERIVED/Build/Intermediates.noindex/PropertyReplay.build" -type d -path "*PropertyReplay.build/Objects-normal/*" | head -1)"
find "$OBJECTS" -name "*.stringsdata" ! -name "ExtractedAppShortcutsMetadata.stringsdata" -print0 \
  | xargs -0 xcrun xcstringstool sync "$CATALOG" --skip-marking-strings-stale --stringsdata

python3 - "$CATALOG" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
missing = [k for k, e in d["strings"].items()
           if e.get("shouldTranslate") is not False and "zh-Hans" not in e.get("localizations", {})]
print(f"{len(d['strings'])} keys; {len(missing)} without zh-Hans")
for k in missing: print("   ", k)
PY
