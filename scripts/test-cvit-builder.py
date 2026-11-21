#!/usr/bin/env python3
"""Test chained-directory CVIT image construction."""
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILDER = ROOT / 'scripts/mk_cvit_nova.py'
BLOCK_WORDS = 129


class BuilderTests(unittest.TestCase):
    def test_directory_boundaries(self):
        for count in (0, 1, 9, 10, 18, 19):
            with self.subTest(count=count), tempfile.TemporaryDirectory() as tmp:
                tmp = Path(tmp)
                member = tmp / 'text.txt'
                member.write_bytes(b'hello')
                image = tmp / 'disk.img'
                specs = [f'FILE{i}={member}' for i in range(count)]
                subprocess.run([sys.executable, str(BUILDER), str(image), *specs], check=True, capture_output=True)
                data = image.read_bytes()
                def block(n):
                    return struct.unpack_from('<129H', data, n * BLOCK_WORDS * 2)
                header = block(0)
                dirs = max(1, (count + 8) // 9)
                self.assertEqual(header[:7], (0x4356, 0x4e56, 2, 1, dirs, dirs + 1, dirs + 1 + count))
                for d in range(dirs):
                    directory = block(d + 1)
                    link = directory[108:120]
                    self.assertEqual(link[6], d + 2 if d + 1 < dirs else 0)
                    self.assertEqual(link[:6], (0,) * 6)
                    for j in range(min(9, count - d * 9)):
                        i = d * 9 + j
                        entry = directory[j * 12:(j + 1) * 12]
                        name = ''.join(chr(w >> 8) + chr(w & 255) for w in entry[:5]).rstrip()
                        self.assertEqual(name, f'FILE{i}')
                        self.assertEqual(entry[5:8], (1, dirs + 1 + i, 1))
                        self.assertEqual(entry[10], 5)
                        self.assertEqual(block(entry[6])[:5], tuple(b'hello'))


if __name__ == '__main__':
    unittest.main()
