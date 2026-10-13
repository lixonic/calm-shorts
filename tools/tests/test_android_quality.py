import io
from pathlib import Path
import struct
import sys
import unittest
import zipfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verify_android import elf_alignment, verify_native


def elf(alignment=16384, address=0):
    data = bytearray(120)
    data[:6] = b'\x7fELF\x02\x01'
    struct.pack_into('<Q', data, 32, 64)
    struct.pack_into('<HH', data, 54, 56, 1)
    struct.pack_into('<I', data, 64, 1)
    struct.pack_into('<QQ', data, 72, 0, address)
    struct.pack_into('<Q', data, 112, alignment)
    return bytes(data)


class NativeAlignmentTests(unittest.TestCase):
    def test_rejects_4kb_and_incongruent_load_segments(self):
        for value in (elf(4096), elf(65536, 1), b'not an ELF'):
            with self.assertRaises(ValueError):
                elf_alignment(value)
        self.assertEqual(elf_alignment(elf(65536)), [65536])

    def test_checks_zip_payload_alignment_not_only_elf(self):
        for aligned in (False, True):
            data = io.BytesIO()
            with zipfile.ZipFile(data, 'w') as archive:
                info = zipfile.ZipInfo('lib/arm64-v8a/libapp.so')
                if aligned:
                    length = (-(30 + len(info.filename))) % 16384
                    info.extra = struct.pack('<HH', 0xcafe, length - 4) + bytes(length - 4)
                archive.writestr(info, elf())
            data.seek(0)
            with zipfile.ZipFile(data) as archive:
                if aligned:
                    self.assertEqual(verify_native(archive, check_zip=True)[0]['zipDataOffset'], 16384)
                else:
                    with self.assertRaisesRegex(ValueError, 'ZIP payload'):
                        verify_native(archive, check_zip=True)
                    self.assertEqual(len(verify_native(archive, check_zip=False)), 1)
