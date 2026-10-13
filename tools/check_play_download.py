#!/usr/bin/env python3
"""Enforce headroom below Play's 500 MB base download limit using bundletool CSV."""
import csv
import json
from pathlib import Path
import sys

MAX_DOWNLOAD_BYTES = 480_000_000


def check(path: Path) -> dict:
    rows = list(csv.DictReader(path.read_text().splitlines()))
    if not rows or not all('MAX' in row and 'MIN' in row for row in rows):
        raise ValueError('Missing bundletool MIN/MAX download-size data')
    maximum = max(int(row['MAX']) for row in rows)
    if maximum > MAX_DOWNLOAD_BYTES:
        raise ValueError(f'Play download {maximum / 1e6:.1f} MB exceeds the 480 MB safety budget')
    return {'maximumCompressedDownloadBytes': maximum, 'budgetBytes': MAX_DOWNLOAD_BYTES}


if __name__ == '__main__':
    print(json.dumps(check(Path(sys.argv[1])), indent=2))
