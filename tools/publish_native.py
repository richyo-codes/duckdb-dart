#!/usr/bin/env python3
"""Validate all mobile assets and upload a new draft release; never overwrite."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

from build_native import CONFIG, MOBILE_TARGETS


def validate(directory):
    files = []
    for target in MOBILE_TARGETS:
        archive = directory / f'duckdb-{CONFIG["duckdb_version"]}-{target}.tar.gz'
        checksum = archive.with_name(archive.name + '.sha256')
        provenance = archive.with_name(archive.name + '.json')
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        if checksum.read_text().strip() != f'{digest}  {archive.name}':
            raise ValueError(f'Checksum mismatch for {archive}')
        metadata = json.loads(provenance.read_text())
        expected = {'duckdb_commit': CONFIG['duckdb_commit'],
                    'duckdb_version': CONFIG['duckdb_version'], 'target': target,
                    'sha256': digest, 'release_tag': CONFIG['release_tag']}
        if metadata != expected:
            raise ValueError(f'Provenance mismatch for {archive}')
        files.extend([archive, checksum, provenance])
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    args = parser.parse_args()
    files = validate(args.directory)
    repository = os.environ['GITHUB_REPOSITORY']
    if repository != CONFIG['repository']:
        raise ValueError('Update hook/native_config.json repository before publishing from a fork.')
    tag = CONFIG['release_tag']
    ref = os.environ.get('GITHUB_REF', '')
    if ref.startswith('refs/tags/') and ref != f'refs/tags/{tag}':
        raise ValueError('The pushed tag must match native_config.json release_tag.')
    # gh release create fails if this release already exists; no --clobber.
    notes = args.directory / 'release-notes.txt'
    notes.write_text(f'DuckDB {CONFIG["duckdb_version"]}\n\n'
                     f'Upstream commit: {CONFIG["duckdb_commit"]}\n'
                     f'Packaging commit: {os.environ["GITHUB_SHA"]}\n\n'
                     'Android: arm64, x64 (NDK r28, API 21, 16 KB load alignment).\n'
                     'iOS: arm64 device; arm64 and x64 simulators (minimum iOS 13).\n'
                     'Desktop archives are downloaded directly from DuckDB.\n'
                     'Validate on devices before publishing this draft.\n')
    subprocess.run(['gh', 'release', 'create', tag, '--repo', repository,
                    '--target', os.environ['GITHUB_SHA'], '--draft',
                    '--title', f'DuckDB native binaries {tag}',
                    '--notes-file', str(notes), *map(str, files)], check=True)


if __name__ == '__main__':
    main()
