#!/usr/bin/env python3
"""Audit counterexamples against the current Swift LiveYaw, without editing production sources.

Run on this Mac: python3 docs/reviews/2026-10-05-light-scan-probes.py
Builds only in a temporary directory outside iCloud. Inputs are synthetic; no field data is read.
"""
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
CAPTURE = ROOT / "ios/Packages/CaptureCore/Sources/CaptureCore"
NORTH = ROOT / "ios/Packages/NorthResolver/Sources/NorthResolver/NorthResolver.swift"

MAIN = r'''import Foundation
func add(_ yaw: inout LiveYaw, _ delta: Double, count: Int) {
    for _ in 0..<count {
        yaw.add(HeadingSample(trueHeading: delta, magneticHeading: delta, headingAccuracy: 10,
                              sampledAt: Date()), cameraAzimuthARDeg: 0, cameraPitchDeg: 0)
    }
}

// LightScanModel.handle accepts preview readings; start() clears only CaptureRecorder's log.
// Reproduce the resulting difference with the same merge used by SceneRecordBuilder.
var preview = LiveYaw()
add(&preview, 115, count: 400)
add(&preview, 100, count: 200)
let recorded = NorthResolver.merge(Array(repeating: (yawDeg: 100.0, sigmaDeg: 10.0), count: 200))
print("LS01 preview: live=\(preview.estimate!.deltaDeg) recorded=\(recorded.yawDeg)")

// Every round of compaction halves old readings, but subsequent new readings all get one vote.
var long = LiveYaw()
add(&long, 100, count: LiveYaw.capacity)
add(&long, 130, count: LiveYaw.capacity / 2 + 1)
let full = NorthResolver.merge(
    Array(repeating: (yawDeg: 100.0, sigmaDeg: 10.0), count: LiveYaw.capacity) +
    Array(repeating: (yawDeg: 130.0, sigmaDeg: 10.0), count: LiveYaw.capacity / 2 + 1))
print("LS02 compaction: live=\(long.estimate!.deltaDeg) retained=\(long.estimate!.samples) full=\(full.yawDeg)")

// The change to the pitch cutoff does exclude the upward flipped readings as intended.
var upward = LiveYaw()
add(&upward, 100, count: 40)
for _ in 0..<100 {
    upward.add(HeadingSample(trueHeading: 280, magneticHeading: 280, headingAccuracy: 10,
                             sampledAt: Date()), cameraAzimuthARDeg: 0, cameraPitchDeg: 40)
}
print("pitch filter: delta=\(upward.estimate!.deltaDeg) samples=\(upward.estimate!.samples)")
precondition(abs(upward.estimate!.deltaDeg - 100) < 1e-8 && upward.estimate!.samples == 40)
'''


def main():
    coach = (CAPTURE / "ScanCoach.swift").read_text()
    log = (CAPTURE / "CaptureLog.swift").read_text()
    # Compile the actual current definitions, not a Python translation of the algorithm.
    heading = log[log.index("public struct HeadingSample:"):log.index("public struct LocationSample:")]
    live = coach[coach.index("public struct LiveYaw:"):]
    with tempfile.TemporaryDirectory(prefix="propertyreplay-light-probes-", dir="/private/tmp") as tmp:
        directory = Path(tmp)
        (directory / "LiveYaw.swift").write_text("import Foundation\n" + heading + live)
        (directory / "main.swift").write_text(MAIN)
        executable = directory / "probe"
        subprocess.run([
            "swiftc", "-module-cache-path", str(directory / "module-cache"), str(NORTH),
            str(directory / "LiveYaw.swift"), str(directory / "main.swift"), "-o", str(executable)
        ], check=True, timeout=120)
        subprocess.run([str(executable)], check=True, timeout=60)


if __name__ == "__main__":
    main()
