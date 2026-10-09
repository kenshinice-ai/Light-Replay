"""Read-only semantic audit probes for the SceneRecord validators.
Run from any location after scripts/test.sh:
  python3 docs/reviews/2026-09-30-schema-probes.py
SCENE_RECORD_CHECK may point to another built Swift CLI.
Only synthetic inputs are used. Exit 1 means a semantically insufficient record was accepted.
"""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(root / 'engine'), str(root / 'engine/tests')]
from test_scenerecord import ready_record
from lightreplay import scenerecord

cli = Path(os.environ.get('SCENE_RECORD_CHECK', Path.home() / 'Library/Caches/propertyreplay/SceneRecord-build/debug/scene-record-check'))
if not cli.is_file():
    raise SystemExit('Build SceneRecord first, or set SCENE_RECORD_CHECK.')

cases = {}
r = ready_record()
r['north']['candidates'][0]['sigma_deg'] = 12
r['north']['resolved']['sigma_deg'] = 12
cases['single_magnetic_sigma_12_ready'] = r
cases['missing_lens_gate'] = ready_record()
r = ready_record()
r['visibility']['coverage'].update(corridor_cells=100, covered_cells=1, unknown_cells=99, glass_cells=0, coverage_pct=.01)
cases['coverage_one_percent_pass'] = r
r = ready_record()
r['visibility']['coverage'].update(glass_cells=9)
cases['all_covered_cells_glass_pass'] = r
r = ready_record()
r['capture_session']['frames'][0]['t'] = 99999
cases['frame_beyond_session'] = r
r = ready_record()
r['target']['anchor_world'] = [7, 0, 0]
cases['target_vs_lock_anchor_mismatch'] = r

results = []
for label, record in cases.items():
    try:
        scenerecord.validate(record)
        python_status = 'ACCEPT'
    except scenerecord.ValidationError as error:
        python_status = 'REJECT: ' + str(error)
    swift = subprocess.run([str(cli), '--compact', '-'], input=json.dumps(record), text=True, capture_output=True)
    results.append(dict(case=label, expected='REJECT', python=python_status,
                        swift='ACCEPT' if swift.returncode == 0 else 'REJECT: ' + swift.stderr.strip()))
print(json.dumps(results, indent=2))
raise SystemExit(1 if any(r['python'] == 'ACCEPT' or r['swift'] == 'ACCEPT' for r in results) else 0)
