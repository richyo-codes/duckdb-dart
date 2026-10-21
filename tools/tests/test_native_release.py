import hashlib
import json
from pathlib import Path
import subprocess
import sys
import struct
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_native import CONFIG, MOBILE_TARGETS
from publish_native import validate
from validate_native import validate_library

def elf_fixture(alignment=16384):
    data = bytearray(120)
    data[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<HH", data, 16, 3, 183)
    struct.pack_into("<Q", data, 32, 64)
    struct.pack_into("<HH", data, 54, 56, 1)
    struct.pack_into("<I", data, 64, 1)
    struct.pack_into("<Q", data, 112, alignment)
    return bytes(data)



class NativeReleaseTest(unittest.TestCase):
    def test_complete_release_and_tampered_archive(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for target in MOBILE_TARGETS:
                archive = root / f'duckdb-{CONFIG["duckdb_version"]}-{target}.tar.gz'
                archive.write_bytes(b'fixture')
                digest = hashlib.sha256(b'fixture').hexdigest()
                archive.with_name(archive.name + '.sha256').write_text(f'{digest}  {archive.name}\n')
                archive.with_name(archive.name + '.json').write_text(json.dumps({
                    'duckdb_commit': CONFIG['duckdb_commit'],
                    'duckdb_version': CONFIG['duckdb_version'], 'target': target,
                    'sha256': digest, 'release_tag': CONFIG['release_tag']}))
            self.assertEqual(len(validate(root)), len(MOBILE_TARGETS) * 3)
            archive.write_bytes(b'tampered')
            with self.assertRaisesRegex(ValueError, 'Checksum mismatch'):
                validate(root)

    def test_android_architecture_and_alignment(self):
        validate_library(elf_fixture(), 'android-arm64')
        with self.assertRaisesRegex(ValueError, 'architecture'):
            validate_library(elf_fixture(), 'android-x64')
        with self.assertRaisesRegex(ValueError, '16 KB'):
            validate_library(elf_fixture(4096), 'android-arm64')

    def test_ios_device_and_simulator_are_distinct(self):
        header = struct.pack('<8I', 0xFEEDFACF, 0x0100000C, 0, 6, 1, 24, 0, 0)
        data = header + struct.pack('<6I', 0x32, 24, 2, 13 << 16, 0, 0)
        validate_library(data, 'ios-arm64')
        with self.assertRaisesRegex(ValueError, 'SDK mismatch'):
            validate_library(data, 'ios-simulator-arm64')

    def test_incomplete_release_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(FileNotFoundError):
                validate(Path(temporary))

    def test_packaging_round_trip(self):
        import tarfile
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'libduckdb.so').write_bytes(elf_fixture())
            subprocess.run([sys.executable, 'tools/package_native.py',
                            '--target', 'android-arm64', '--library-dir', str(root),
                            '--output', str(root / 'dist')], check=True)
            archive = next((root / 'dist').glob('*.tar.gz'))
            with tarfile.open(archive) as bundle:
                self.assertEqual(bundle.getnames(), ['libduckdb.so'])
                self.assertEqual(bundle.extractfile('libduckdb.so').read(), elf_fixture())


if __name__ == '__main__':
    unittest.main()
