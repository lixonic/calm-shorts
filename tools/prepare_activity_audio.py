#!/usr/bin/env python3
"""Create quiet, offline counting cues with FFmpeg and its built-in Flite voice.

No external recordings or voice service are used. Existing app volume settings
still apply. Recordings contain one to five distinct cues separated by silence.
"""
from array import array
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import wave

RATE = 22050
ROOT = Path(__file__).resolve().parents[1]


def run(command):
    subprocess.run(command, check=True, capture_output=True, timeout=60)


def write_wave(path, samples):
    pcm = array('h', (round(max(-1, min(1, sample)) * 32767) for sample in samples))
    if sys.byteorder != 'little':
        pcm.byteswap()
    with wave.open(str(path), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())


def main():
    output = ROOT / 'assets/activities'
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as folder:
        temporary = Path(folder)
        hello = temporary / 'hello.wav'
        run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi',
             '-i', 'flite=text=Hello.:voice=slt', '-af', 'atempo=0.9,lowpass=f=3400',
             '-ar', str(RATE), '-ac', '1', '-c:a', 'pcm_s16le', str(hello)])
        with wave.open(str(hello), 'rb') as source:
            speech = array('h', source.readframes(source.getnframes()))
        if sys.byteorder != 'little':
            speech.byteswap()
        peak = max(abs(sample) for sample in speech)
        voice = [sample / peak * 0.22 for sample in speech]
        chime = []
        for index in range(round(RATE * 0.75)):
            t = index / RATE
            envelope = (1 - math.exp(-35 * t)) * math.exp(-5 * t)
            chime.append(0.16 * envelope * (math.sin(2 * math.pi * 440 * t) + 0.25 * math.sin(2 * math.pi * 660 * t)))
        for kind, unit in [('voices', voice), ('chimes', chime)]:
            for count in range(1, 6):
                samples = [0.0] * round(RATE * 0.3)
                for index in range(count):
                    samples.extend(unit)
                    if index < count - 1:
                        samples.extend([0.0] * round(RATE * 0.8))
                samples.extend([0.0] * round(RATE * 0.5))
                wav = temporary / f'{kind}-{count}.wav'
                write_wave(wav, samples)
                target = output / f'{kind}-{count}.m4a'
                run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(wav),
                     '-c:a', 'aac', '-b:a', '48k', '-ar', '44100', '-ac', '1',
                     '-movflags', '+faststart', str(target)])
                print(f'{target.name}: {len(samples) / RATE:.2f} seconds, {target.stat().st_size} bytes')


if __name__ == '__main__':
    main()
