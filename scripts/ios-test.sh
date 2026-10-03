#!/usr/bin/env bash
# Runs the iOS test scheme on a dedicated simulator and returns as soon as xcodebuild reports the result.
#
#   ./scripts/ios-test.sh                         everything (unit + UI)
#   ./scripts/ios-test.sh unit                    unit bundles only
#   ./scripts/ios-test.sh ui                      UI tests only
#   ./scripts/ios-test.sh -only-testing:PropertyReplayUITests/LightScanUITests
#   PR_APPEARANCE=dark ./scripts/ios-test.sh ui         the same device in dark appearance (screenshots for the eye)
#
# Why a wrapper: xcodebuild can linger for ten minutes collecting simulator diagnostics after a failure, so they are
# turned off and there is a hard cap. The default iPhone simulators are shared with other projects' sessions, so the
# tests use their own device, created on first use and shut down afterwards unless it was already booted
# (group memories simulator-shared-with-other-sessions, shut-down-simulators-after-a-batch).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${PR_SIM_NAME:-Property Replay iPhone}"
TYPE="${PR_SIM_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro}"
DERIVED="${PROPERTYREPLAY_BUILD_ROOT:-$HOME/Library/Caches/propertyreplay}/DerivedData"
CAP="${PR_TEST_TIMEOUT:-1500}"

UDID="$(xcrun simctl list devices | grep -F "$NAME (" | grep -oE '[0-9A-F-]{36}' | head -1)"
if [ -z "$UDID" ]; then
  RUNTIME="$(xcrun simctl list runtimes | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-27[0-9-]*' | tail -1)"
  UDID="$(xcrun simctl create "$NAME" "$TYPE" "$RUNTIME")"
  echo "created simulator $NAME ($UDID)"
fi
WAS_BOOTED=0
xcrun simctl list devices | grep -F "$UDID" | grep -q Booted && WAS_BOOTED=1
# The keyboard's first-use introductions stall XCUITest 60 s a step (group memory ui-tests-simulator-without-icloud):
# mark them seen. Appearance is set here because the app has no launch argument for it.
xcrun simctl boot "$UDID" 2>/dev/null || true
for key in DidShowContinuousPathIntroduction DidShowGestureKeyboardIntroduction; do
  xcrun simctl spawn "$UDID" defaults write com.apple.Preferences "$key" -bool YES 2>/dev/null || true
done
xcrun simctl ui "$UDID" appearance "${PR_APPEARANCE:-light}" 2>/dev/null || true

ARGS=()
case "${1:-}" in
  unit) shift; ARGS+=(-skip-testing:PropertyReplayUITests) ;;
  ui) shift; ARGS+=(-only-testing:PropertyReplayUITests) ;;
esac
ARGS+=("$@")

LOG="$(mktemp -t propertyreplay-test)"
xcodebuild test -project "$ROOT/ios/PropertyReplay.xcodeproj" -scheme PropertyReplay -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" -collect-test-diagnostics never ${ARGS[@]+"${ARGS[@]}"} > "$LOG" 2>&1 &
PID=$!
START=$SECONDS
while kill -0 "$PID" 2>/dev/null; do
  if grep -qE '^\*\* TEST (SUCCEEDED|FAILED) \*\*' "$LOG"; then sleep 2; kill "$PID" 2>/dev/null; break; fi
  if [ $((SECONDS - START)) -gt "$CAP" ]; then echo "hard cap ${CAP}s reached; stopping xcodebuild"; kill "$PID" 2>/dev/null; break; fi
  sleep 3
done
wait "$PID" 2>/dev/null

grep -E "error:|Test Case .* failed|Executed [0-9]+ tests?, with [1-9]" "$LOG" | sort -u | head -40
grep -E "Test Case .* passed" "$LOG" | wc -l | xargs echo "test cases passed:"
grep -E '^\*\* TEST (SUCCEEDED|FAILED) \*\*' "$LOG" | tail -1 || echo "no result line (see $LOG)"
echo "log: $LOG"
[ "$WAS_BOOTED" = 1 ] || xcrun simctl shutdown "$UDID" 2>/dev/null
grep -qE '^\*\* TEST SUCCEEDED \*\*' "$LOG"
