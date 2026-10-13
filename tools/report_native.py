#!/usr/bin/env python3
"""Publish concise non-secret emulator measurements as a public CI notice."""
import json
from pathlib import Path

path = Path('build/integration_response_data.json')
if path.exists() and path.read_text().strip() not in ('', 'null'):
    data = json.loads(path.read_text())
    report = {key: data.get(key) for key in ('firstPlayableMs', 'cacheBudgetBytes', 'swipeStepsRequested', 'playback', 'memory', 'swipeFrames', 'backwardSwipeFrames')}
    print('::notice title=Native emulator measurements::' + json.dumps(report).replace('%', '%25'))
else:
    print('No completed native measurement report is available.')
