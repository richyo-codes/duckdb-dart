import contextlib
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_native


class SourceBuildTest(unittest.TestCase):
    def invoke(self, target, system='Linux', machine='x86_64', commit=None, jobs=2):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(sys, 'argv', ['build_native.py', '--target', target,
                                           '--output', directory, '--jobs', str(jobs)]), \
                 patch.object(build_native.platform, 'system', return_value=system), \
                 patch.object(build_native.platform, 'machine', return_value=machine), \
                 patch.object(build_native, 'run') as run, \
                 patch.object(build_native.subprocess, 'check_output',
                              return_value=commit or build_native.CONFIG['duckdb_commit']), \
                 patch.object(build_native.shutil, 'copy2') as copy, \
                 patch.dict(build_native.os.environ, {}, clear=True), \
                 contextlib.redirect_stdout(io.StringIO()), \
                 contextlib.redirect_stderr(io.StringIO()):
                build_native.main()
                return run.call_args_list, copy.call_args

    def test_native_linux_architectures_use_host_toolchain_without_ndk(self):
        for target, machine in [('linux-x64', 'x86_64'), ('linux-arm64', 'aarch64')]:
            with self.subTest(target=target):
                calls, copied = self.invoke(target, machine=machine)
                configure = next(call.args for call in calls if call.args[:2] == ('cmake', '-S'))
                self.assertIn('-DCMAKE_BUILD_TYPE=Release', configure)
                self.assertIn('-DCMAKE_POSITION_INDEPENDENT_CODE=ON', configure)
                self.assertFalse(any('ANDROID' in str(arg) for arg in configure))
                self.assertIn('-DBUILD_EXTENSIONS=core_functions;parquet;json;icu', configure)
                self.assertEqual(calls[-1].args[:2], ('strip', '--strip-debug'))
                self.assertEqual(copied.args[0].name, 'libduckdb.so')

    def test_linux_cross_compilation_and_non_linux_hosts_are_rejected(self):
        for system, machine, target in [('Darwin', 'x86_64', 'linux-x64'),
                                         ('Linux', 'x86_64', 'linux-arm64'),
                                         ('Linux', 'riscv64', 'linux-x64')]:
            with self.subTest(system=system, machine=machine):
                with self.assertRaises(SystemExit):
                    self.invoke(target, system=system, machine=machine)

    def test_pinned_source_commit_is_still_enforced(self):
        with self.assertRaisesRegex(RuntimeError, 'Unexpected DuckDB source commit'):
            self.invoke('linux-x64', commit='unexpected')

    def test_invalid_job_count_is_rejected(self):
        with self.assertRaises(SystemExit):
            self.invoke('linux-x64', jobs=0)


if __name__ == '__main__':
    unittest.main()
