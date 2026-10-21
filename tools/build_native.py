#!/usr/bin/env python3
"""Compatibility entry point for release tooling; source builds run in Dart."""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / 'hook/native_config.json').read_text())
MOBILE_TARGETS = ('android-arm64', 'android-x64', 'ios-arm64',
                  'ios-simulator-arm64', 'ios-simulator-x64')

if __name__ == '__main__':
    sys.exit(subprocess.call(['dart', str(ROOT / 'tools/build_native.dart'), *sys.argv[1:]]))
