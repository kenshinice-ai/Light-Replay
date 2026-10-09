#!/usr/bin/env bash
# Run every pure-algorithm test suite. Build products live outside iCloud on purpose:
# codesign rejects bundles carrying the iCloud file provider's FinderInfo (see docs/HANDOFF.md).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${PROPERTYREPLAY_BUILD_ROOT:-$HOME/Library/Caches/propertyreplay}"
mkdir -p "$SCRATCH"

echo "== SceneRecord (Swift)"
swift test --package-path "$ROOT/ios/Packages/SceneRecord" --scratch-path "$SCRATCH/SceneRecord-build" 2>&1 | grep -E "Executed|error:" | tail -1

echo "== GuideCore (Swift, Guide regression)"
swift test --package-path "$ROOT/ios/Packages/GuideCore" --scratch-path "$SCRATCH/GuideCore-build" 2>&1 | grep -E "Executed|error:" | tail -1

echo "== engine (Python, incl. Swift parity)"
cd "$ROOT/engine"
SCENE_RECORD_CHECK="$SCRATCH/SceneRecord-build/debug/scene-record-check" python3 -m unittest discover -s tests 2>&1 | tail -1
