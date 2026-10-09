#!/usr/bin/env bash
# Archive Property Replay and upload it to App Store Connect for TestFlight. The only path that uploads; CI never
# does (family rule, 07 TOOLS/HANDOFF.md §0.5). Modelled on PWE Receipts' scripts/testflight.sh.
#
# Signing and upload use either the Apple ID signed in to Xcode → Settings → Accounts, or an App Store Connect API
# key through ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID (Lee's; load them into the environment, never print them).
#
#   scripts/testflight.sh --no-upload   # preflight, tests, strings, archive; nothing leaves this Mac
#   scripts/testflight.sh               # the same, then upload and tag — needs Lee's go for this build number,
#                                       # and PR_CLOUDKIT_SCHEMA_DEPLOYED=1 once the CloudKit schema is in Production
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
PROJECT="ios/PropertyReplay.xcodeproj"
SCHEME="PropertyReplay"
WORK="${TMPDIR:-/tmp}/propertyreplay-release"
UPLOAD=1
[[ "${1:-}" == "--no-upload" ]] && UPLOAD=0

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die()  { red "✗ $*"; exit 1; }

step "Preflight"
scripts/preflight.sh --clean || die "Preflight failed. Nothing was built."
xcodebuild -version | sed -n 1p

AUTH=()
if [[ -n "${ASC_KEY_PATH:-}" || -n "${ASC_KEY_ID:-}" || -n "${ASC_ISSUER_ID:-}" ]]; then
  [[ -n "${ASC_KEY_PATH:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]] \
    || die "Set all three of ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID, or none (to use the Xcode account)."
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  echo "Signing with an App Store Connect API key."
else
  echo "Signing with the Apple ID signed in to Xcode (Settings → Accounts)."
fi

VERSION=$(grep -m1 -o 'MARKETING_VERSION = [0-9.]*' "$PROJECT/project.pbxproj" | awk '{print $3}')
[[ -n "$VERSION" ]] || die "MARKETING_VERSION not found in the project (ios/project.yml sets it; run xcodegen generate)."
BUILD=$(git rev-list --count HEAD)
COMMIT=$(git rev-parse HEAD)   # the tag goes on what was archived, not on HEAD at the end
TAG="testflight/$VERSION-$BUILD"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "$TAG already exists — commit something first so the build number moves."
echo "Version $VERSION, build $BUILD, tag $TAG"

step "Checkout"
# Tests and the archive read a detached checkout of $COMMIT, outside iCloud, so nothing edited meanwhile is built.
SRC="$WORK/src"
git worktree remove --force "$SRC" 2>/dev/null || rm -rf "$SRC"
git worktree prune
git worktree add --detach "$SRC" "$COMMIT" >/dev/null
trap 'cd "$ROOT" && git worktree remove --force "$SRC" 2>/dev/null || true' EXIT
cd "$SRC"
echo "Building $(git rev-parse --short HEAD) from $SRC"

step "Pure algorithm tests"
./scripts/test.sh || die "Pure tests failed. Nothing was archived."

step "Unit tests (simulator)"
./scripts/ios-test.sh unit || die "Unit tests failed. Nothing was archived."

step "Strings"
# Every user-facing string ships with its Simplified Chinese (Lee, 2026-10-03). Developer-only keys are marked.
python3 - ios/PropertyReplay/Localizable.xcstrings ios/Packages/PropertyModel/Sources/PropertyModel/Localizable.xcstrings \
  ios/Packages/CaptureCore/Sources/CaptureCore/Localizable.xcstrings <<'PY' || die "A string has no zh-Hans. Nothing was archived."
import json, sys
bad = 0
for path in sys.argv[1:]:
    d = json.load(open(path))
    for key, e in d["strings"].items():
        if e.get("shouldTranslate") is False: continue
        if "zh-Hans" not in e.get("localizations", {}):
            print(f"{path}: no zh-Hans for {key!r}"); bad += 1
sys.exit(1 if bad else 0)
PY

step "Archive"
rm -rf "$WORK/PropertyReplay.xcarchive" "$WORK/export"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$WORK/PropertyReplay.xcarchive" -derivedDataPath "$WORK/archive-derived" \
  CURRENT_PROJECT_VERSION="$BUILD" -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} archive -quiet \
  || die "Archive failed. If it mentions signing or 'No Account', sign in to Xcode → Settings → Accounts once (group memory asc-api-key-location)."

if [[ $UPLOAD -eq 0 ]]; then
  echo "Archive at $WORK/PropertyReplay.xcarchive (not uploaded)."
  exit 0
fi

step "Upload to App Store Connect"
# A TestFlight build talks to the Production CloudKit container. Until the schema is deployed there (CloudKit
# Console → Deploy Schema Changes), every sync would fail on testers' devices; HANDOFF lists this under 等 Lee.
[[ "${PR_CLOUDKIT_SCHEMA_DEPLOYED:-}" == "1" ]] \
  || die "Deploy the CloudKit schema to Production first, then rerun with PR_CLOUDKIT_SCHEMA_DEPLOYED=1."
xcodebuild -exportArchive -archivePath "$WORK/PropertyReplay.xcarchive" \
  -exportOptionsPlist "$SRC/scripts/ExportOptions.plist" -exportPath "$WORK/export" \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} \
  || die "Upload failed. 'Failed to find an account with App Store Connect access' means Xcode → Settings → Accounts has no usable Apple ID for team 2SQV3H5MH9 (group memory xcode-failed-to-use-accounts: remove and re-add)."

step "Tag"
cd "$ROOT"
git tag -a "$TAG" "$COMMIT" -m "TestFlight upload $VERSION ($BUILD)"
git remote get-url origin >/dev/null 2>&1 && git push origin "$TAG"
echo "Uploaded $VERSION ($BUILD); tagged $TAG."
