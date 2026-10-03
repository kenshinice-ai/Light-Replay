#!/usr/bin/env bash
# Run every pure-algorithm test suite. Build products live outside iCloud on purpose:
# codesign rejects bundles carrying the iCloud file provider's FinderInfo (see docs/HANDOFF.md).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${PROPERTYREPLAY_BUILD_ROOT:-$HOME/Library/Caches/propertyreplay}"
mkdir -p "$SCRATCH"

# iCloud conflict copies compile fine and ship silently (family rule, 07 TOOLS/HANDOFF.md §0.3): stop here.
"$ROOT/scripts/preflight.sh" || exit 1

echo "== NorthResolver (Swift, parity with engine/tests/fixtures/north-cases.json)"
swift test --package-path "$ROOT/ios/Packages/NorthResolver" --scratch-path "$SCRATCH/NorthResolver-build" 2>&1 | grep -E "Executed|error:" | tail -1

echo "== SceneRecord (Swift, incl. QualityEvaluator against engine/tests/fixtures/quality-cases.json)"
swift test --package-path "$ROOT/ios/Packages/SceneRecord" --scratch-path "$SCRATCH/SceneRecord-build" 2>&1 | grep -E "Executed|error:" | tail -1

echo "== SunEngine (Swift, parity with engine/tests/fixtures/sun-positions.json and sun-bands.json)"
swift test --package-path "$ROOT/ios/Packages/SunEngine" --scratch-path "$SCRATCH/SunEngine-build" 2>&1 | grep -E "Executed|error:" | tail -1

echo "== engine (Python, incl. Swift parity)"
cd "$ROOT/engine"
SCENE_RECORD_CHECK="$SCRATCH/SceneRecord-build/debug/scene-record-check" python3 -m unittest discover -s tests 2>&1 | tail -1
