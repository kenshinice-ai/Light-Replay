#!/usr/bin/env bash
# The checks the PWE Tools family runs before a build that leaves this Mac (07 TOOLS/HANDOFF.md §0):
#   1. nothing in the repo is a cloud-only placeholder (git and xcodebuild hang on them instead of failing);
#   2. no iCloud conflict copies ("Foo 2.swift" beside "Foo.swift"), tracked or not;
#   3. optionally, a clean working tree (--clean), so a tag can point at what was built.
#
#   ./scripts/preflight.sh            # 1 and 2
#   ./scripts/preflight.sh --clean    # 1, 2 and 3
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
status=0

# No early-exit readers (grep -q, head) on the writer side: under pipefail SIGPIPE would fail the pipeline silently.
dataless="$(ls -lOR . 2>/dev/null | grep -c dataless || true)"
if [[ "$dataless" != "0" ]]; then
  echo "preflight: $dataless cloud-only (dataless) files. Open the folder in Finder → Download Now, then rerun." >&2
  status=1
fi

CHECK="$ROOT/../check-icloud-copies.py"
if [[ -f "$CHECK" ]]; then
  python3 "$CHECK" "$ROOT" || status=1
else
  echo "preflight: 07 TOOLS/check-icloud-copies.py not found beside this repo; conflict copies not checked." >&2
fi

if [[ "${1:-}" == "--clean" ]] && [[ -n "$(git status --porcelain)" ]]; then
  echo "preflight: working tree is not clean. Commit first." >&2
  status=1
fi

[[ $status -eq 0 ]] && echo "preflight: ok"
exit $status
