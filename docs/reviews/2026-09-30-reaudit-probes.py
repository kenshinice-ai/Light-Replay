"""Second-round, synthetic-only SceneRecord audit. This is not a production quality evaluator.
Run after scripts/test.sh:
    python3 docs/reviews/2026-09-30-reaudit-probes.py
Two shape violations must reject. Four other cases record the remaining quality-layer boundary.
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
    raise SystemExit('Run scripts/test.sh or set SCENE_RECORD_CHECK first.')
base = ready_record()
cases = {}
r = copy.deepcopy(base)
r['north']['resolved']['sigma_deg'] = 12
r['north']['candidates'][0]['sigma_deg'] = 12
cases['single_group_sigma_12'] = r
r = copy.deepcopy(base)
r['quality']['gates'].pop('lens', None)
cases['missing_lens'] = r
r = copy.deepcopy(base)
r['visibility']['coverage'].update(corridor_cells=100, covered_cells=1, unknown_cells=99, glass_cells=0, coverage_pct=.01)
cases['coverage_1_percent'] = r
r = copy.deepcopy(base)
r['visibility']['coverage']['glass_cells'] = 9
cases['glass_90_percent'] = r
r = copy.deepcopy(base)
r['capture_session']['frames'][0]['t'] = 99999
cases['frame_outside_session'] = r
r = copy.deepcopy(base)
r['target']['anchor_world'] = [7, 0, 0]
cases['mismatched_anchor'] = r

output = []
for name, record in cases.items():
    try:
        scenerecord.validate(record)
        python_result = 'ACCEPT'
    except scenerecord.ValidationError as error:
        python_result = 'REJECT: ' + str(error)
    swift = subprocess.run([str(cli), '--compact', '-'], input=json.dumps(record), text=True, capture_output=True)
    output.append(dict(case=name, python=python_result,
                       swift='ACCEPT' if swift.returncode == 0 else 'REJECT: ' + swift.stderr.strip()))
print(json.dumps(output, indent=2))
