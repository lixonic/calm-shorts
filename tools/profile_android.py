#!/usr/bin/env python3
"""Collect release APK startup, actual OS background memory, and wake-lock evidence via adb."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import shutil
import subprocess
import time

PACKAGE = 'dev.calmshorts.reels'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True, help='Explicit adb device serial; never chooses a phone for you')
    parser.add_argument('--apk', type=Path, help='Optional APK to install with -r; never uninstalls an existing app')
    parser.add_argument('--output', type=Path, default=Path('build/performance/android-release.json'))
    parser.add_argument('--runs', type=int, default=5)
    args = parser.parse_args()
    adb = shutil.which('adb')
    if not adb:
        parser.error('adb is missing. Install Android SDK platform-tools and place them on PATH.')
    if not 1 <= args.runs <= 20:
        parser.error('--runs must be between 1 and 20')
    def run(*command):
        return subprocess.run([adb, '-s', args.serial, *command], capture_output=True,
                              text=True, check=True, timeout=90).stdout.strip()
    if run('get-state') != 'device':
        parser.error('The selected device is not authorized and ready')
    if args.apk:
        run('install', '-r', str(args.apk))
    report = {'capturedAt': datetime.now(timezone.utc).isoformat(), 'serial': args.serial,
              'model': run('shell', 'getprop', 'ro.product.model'),
              'androidSdk': run('shell', 'getprop', 'ro.build.version.sdk'),
              'pageSizeBytes': int(run('shell', 'getconf', 'PAGESIZE')),
              'note': 'dumpsys PSS/RSS is diagnostic evidence, not the 28-day Android vitals P90 metric.',
              'coldStarts': []}
    component = PACKAGE + '/.MainActivity'
    try:
        for _ in range(args.runs):
            run('shell', 'am', 'force-stop', PACKAGE)
            launch = run('shell', 'am', 'start', '-W', '-n', component)
            timings = {key: int(value) for key, value in re.findall(r'^(ThisTime|TotalTime|WaitTime): (\d+)$', launch, re.M)}
            report['coldStarts'].append({'timingMs': timings, 'raw': launch})
            time.sleep(2)
        report['foregroundMeminfo'] = run('shell', 'dumpsys', 'meminfo', PACKAGE)
        report['foregroundPower'] = run('shell', 'dumpsys', 'power')
        run('shell', 'input', 'keyevent', 'KEYCODE_HOME')
        time.sleep(4)
        report['backgroundMeminfo'] = run('shell', 'dumpsys', 'meminfo', PACKAGE)
        report['backgroundPower'] = run('shell', 'dumpsys', 'power')
        report['backgroundProcess'] = run('shell', 'pidof', PACKAGE)
        run('shell', 'am', 'start', '-W', '-n', component)
        time.sleep(2)
        report['restoredMeminfo'] = run('shell', 'dumpsys', 'meminfo', PACKAGE)
        report['batterystats'] = run('shell', 'dumpsys', 'batterystats', PACKAGE)
    finally:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(f'Captured Android measurements in {args.output}')


if __name__ == '__main__':
    main()
