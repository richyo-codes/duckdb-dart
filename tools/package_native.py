#!/usr/bin/env python3
"""Package a mobile library and its digest using the hook's release contract."""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile

from build_native import CONFIG, MOBILE_TARGETS
from validate_native import validate_library


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', required=True, choices=MOBILE_TARGETS)
    parser.add_argument('--library-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    library = 'libduckdb.dylib' if args.target.startswith('ios-') else 'libduckdb.so'
    source = args.library_dir / library
    if not source.is_file():
        parser.error(f'Missing library: {source}')
    validate_library(source.read_bytes(), args.target)
    args.output.mkdir(parents=True, exist_ok=True)
    archive = args.output / f'duckdb-{CONFIG["duckdb_version"]}-{args.target}.tar.gz'
    with tarfile.open(archive, 'w:gz') as bundle:
        bundle.add(source, arcname=library)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_name(archive.name + '.sha256').write_text(f'{digest}  {archive.name}\n')
    provenance = {'duckdb_commit': CONFIG['duckdb_commit'],
                  'duckdb_version': CONFIG['duckdb_version'], 'target': args.target,
                  'sha256': digest, 'release_tag': CONFIG['release_tag']}
    archive.with_name(archive.name + '.json').write_text(json.dumps(provenance, indent=2) + '\n')


if __name__ == '__main__':
    main()
