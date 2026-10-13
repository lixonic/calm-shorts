#!/usr/bin/env python3
"""Verify offline content, native alignment and size in a built APK or AAB."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile

MAX_MEDIA_BYTES = 461_000_000
MAX_APK_BYTES = 495_000_000


def bundled_media_bytes(root: Path) -> int:
    assets = root / 'assets'
    return sum(p.stat().st_size for folder in ('videos', 'posters', 'activities')
               for p in (assets / folder).glob('*') if p.is_file())


def elf_alignment(data: bytes) -> list[int]:
    if len(data) < 64 or data[:4] != b'\x7fELF' or data[4] not in (1, 2) or data[5] not in (1, 2):
        raise ValueError('Invalid native ELF library')
    is64 = data[4] == 2
    order = '<' if data[5] == 1 else '>'
    offset = struct.unpack_from(order + ('Q' if is64 else 'I'), data, 32 if is64 else 28)[0]
    size, count = struct.unpack_from(order + 'HH', data, 54 if is64 else 42)
    minimum = 56 if is64 else 32
    if size < minimum or offset + size * count > len(data):
        raise ValueError('Invalid ELF program headers')
    alignments = []
    for index in range(count):
        start = offset + index * size
        if struct.unpack_from(order + 'I', data, start)[0] != 1:
            continue
        file_offset, address = struct.unpack_from(order + ('QQ' if is64 else 'II'), data, start + (8 if is64 else 4))
        alignment = struct.unpack_from(order + ('Q' if is64 else 'I'), data, start + (48 if is64 else 28))[0]
        if alignment < 16384 or (address - file_offset) % 16384:
            raise ValueError('ELF load segment is not 16 KB aligned')
        alignments.append(alignment)
    if not alignments:
        raise ValueError('ELF library has no load segments')
    return alignments


def verify_native(archive: zipfile.ZipFile, *, check_zip: bool) -> list[dict]:
    libraries = []
    for entry in archive.infolist():
        if not entry.filename.endswith('.so') or '/lib/' not in '/' + entry.filename:
            continue
        with archive.open(entry) as source:
            alignments = elf_alignment(source.read(65536))
        row = {'name': entry.filename, 'elfAlignments': alignments}
        if check_zip:
            if entry.compress_type != zipfile.ZIP_STORED:
                raise ValueError(f'Native library must be stored for direct loading: {entry.filename}')
            archive.fp.seek(entry.header_offset)
            header = archive.fp.read(30)
            if header[:4] != b'PK\x03\x04':
                raise ValueError('Invalid local ZIP header')
            name_size, extra_size = struct.unpack_from('<HH', header, 26)
            offset = entry.header_offset + 30 + name_size + extra_size
            if offset % 16384:
                raise ValueError(f'Native ZIP payload is not 16 KB aligned: {entry.filename}')
            row['zipDataOffset'] = offset
        libraries.append(row)
    return libraries


def digest_stream(source) -> str:
    digest = hashlib.sha256()
    for block in iter(lambda: source.read(1024 * 1024), b''):
        digest.update(block)
    return digest.hexdigest()


def verify(path: Path, root: Path) -> dict:
    is_bundle = path.suffix == '.aab'
    if not is_bundle and path.stat().st_size > MAX_APK_BYTES:
        raise ValueError(f'APK exceeds {MAX_APK_BYTES / 1e6:.0f} MB safety budget')
    media_size = bundled_media_bytes(root)
    if media_size > MAX_MEDIA_BYTES:
        raise ValueError(f'Offline media exceeds {MAX_MEDIA_BYTES / 1e6:.0f} MB budget; remove content or prepare smaller copies')
    prefix = ('base/' if is_bundle else '') + 'assets/flutter_assets/'
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        if is_bundle and not (any(n.startswith('META-INF/') and n.endswith('.SF') for n in names) and any(n.startswith('META-INF/') and n.endswith(('.RSA', '.DSA', '.EC')) for n in names)):
            raise ValueError('AAB signing files are missing')
        native = verify_native(archive, check_zip=not is_bundle)
        if not any('/arm64-v8a/' in row['name'] for row in native):
            raise ValueError('64-bit ARM support is missing')
        library = json.loads(archive.read(prefix + 'assets/library.json'))
        if library != json.loads((root / 'assets/library.json').read_text()):
            raise ValueError('Packaged video catalog differs')
        expected = set()
        for video in library['videos']:
            for field in ('assetPath', 'posterAssetPath'):
                expected.add(prefix + video[field])
        for p in (root / 'assets/activities').glob('*.m4a'):
            expected.add(prefix + p.relative_to(root).as_posix())
        for name in expected:
            source_path = root / name[len(prefix):]
            if archive.getinfo(name).file_size != source_path.stat().st_size:
                raise ValueError(f'Incorrect asset size: {name}')
            with archive.open(name) as packaged, source_path.open('rb') as original:
                if digest_stream(packaged) != digest_stream(original):
                    raise ValueError(f'Incorrect asset contents: {name}')
        actual = {n for n in names if any(n.startswith(prefix + 'assets/' + folder + '/')
                  for folder in ('videos', 'posters', 'activities')) and not n.endswith('/')}
        if actual != expected:
            raise ValueError('Packaged media does not match the catalog')
        if json.loads(archive.read(prefix + 'assets/prompts.json')) != json.loads((root / 'assets/prompts.json').read_text()):
            raise ValueError('Packaged prompts differ')
        if any('.local-admin/' in n or n.startswith(prefix + ('admin/')) or n.startswith(prefix + 'assets/new-videos/') for n in names):
            raise ValueError('Private admin or incoming files were bundled')
        return {'format': 'AAB' if is_bundle else 'APK', 'artifactBytes': path.stat().st_size,
                'offlineMediaBytes': media_size, 'videos': len(library['videos']),
                'dexBytes': sum(e.file_size for e in archive.infolist() if e.filename.endswith('.dex')),
                'nativeLibraries': native}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    report = verify(args.archive, args.root)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
