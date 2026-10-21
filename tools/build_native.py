#!/usr/bin/env python3
"""Build pinned DuckDB for mobile targets or the native Linux host."""
import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / 'hook/native_config.json').read_text())
MOBILE_TARGETS = ('android-arm64', 'android-x64', 'ios-arm64',
                  'ios-simulator-arm64', 'ios-simulator-x64')
LINUX_TARGETS = ('linux-x64', 'linux-arm64')


def run(*args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', required=True, choices=MOBILE_TARGETS + LINUX_TARGETS)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--jobs', type=int, default=2)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error('--jobs must be positive.')
    ios = args.target.startswith('ios-')
    linux = args.target.startswith('linux-')
    if ios and platform.system() != 'Darwin':
        parser.error('iOS source builds require macOS and Xcode.')
    if linux:
        architecture = {'x86_64': 'x64', 'amd64': 'x64',
                        'aarch64': 'arm64', 'arm64': 'arm64'}.get(platform.machine().lower())
        if platform.system() != 'Linux' or args.target != f'linux-{architecture}':
            parser.error('Linux source builds require a matching native Linux host; cross-compilation is not configured. Use binary mode or library_path.')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    source = output / 'source'
    build = output / 'build'
    if not source.exists():
        run('git', 'clone', '--depth', '1', '--branch', CONFIG['duckdb_version'],
            'https://github.com/duckdb/duckdb.git', source)
    commit = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if commit != CONFIG['duckdb_commit']:
        raise RuntimeError(f'Unexpected DuckDB source commit: {commit}')
    options = [
        '-DCMAKE_BUILD_TYPE=Release', '-DBUILD_UNITTESTS=OFF', '-DBUILD_SHELL=OFF',
        '-DEXPORT_DLL_SYMBOLS=ON', '-DOVERRIDE_GIT_DESCRIBE=' + CONFIG['duckdb_version'],
        '-DBUILD_EXTENSIONS=core_functions;parquet;json;icu',
        '-DSTATICALLY_LINK_EXTENSIONS=core_functions;parquet;json;icu',
    ]
    if ios:
        simulator = 'simulator' in args.target
        options += [
            '-DCMAKE_SYSTEM_NAME=iOS',
            '-DCMAKE_OSX_SYSROOT=' + ('iphonesimulator' if simulator else 'iphoneos'),
            '-DCMAKE_OSX_ARCHITECTURES=' + ('x86_64' if args.target.endswith('x64') else 'arm64'),
            '-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0',
            '-DCMAKE_INSTALL_NAME_DIR=@rpath',
            '-DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO',
        ]
        library = 'libduckdb.dylib'
    elif linux:
        options += ['-DCMAKE_POSITION_INDEPENDENT_CODE=ON']
        library = 'libduckdb.so'
    else:
        ndk = os.environ.get('ANDROID_NDK_HOME') or os.environ.get('ANDROID_NDK_ROOT')
        if not ndk:
            parser.error('Set ANDROID_NDK_HOME to an installed Android NDK (r28 or newer).')
        options += [
            '-DCMAKE_TOOLCHAIN_FILE=' + str(Path(ndk) / 'build/cmake/android.toolchain.cmake'),
            '-DANDROID_ABI=' + ('arm64-v8a' if args.target.endswith('arm64') else 'x86_64'),
            '-DANDROID_PLATFORM=android-21', '-DANDROID_STL=c++_static',
            '-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384',
        ]
        library = 'libduckdb.so'
    run('cmake', '-S', source, '-B', build, '-G', 'Ninja', *options)
    run('cmake', '--build', build, '--target', 'duckdb', '--parallel', args.jobs)
    packaged = output / library
    shutil.copy2(build / 'src' / library, packaged)
    if ios:
        run('xcrun', 'strip', '-S', packaged)
    elif linux:
        run('strip', '--strip-debug', packaged)
    else:
        host = {'Linux': 'linux-x86_64', 'Darwin': 'darwin-x86_64',
                'Windows': 'windows-x86_64'}[platform.system()]
        executable = 'llvm-strip.exe' if platform.system() == 'Windows' else 'llvm-strip'
        run(Path(ndk) / 'toolchains/llvm/prebuilt' / host / 'bin' / executable,
            '--strip-debug', packaged)
    print(packaged)


if __name__ == '__main__':
    main()
