#!/usr/bin/env python3
"""Exercise the real m32 runner with mocked USB/SSH/flash commands; no phone access."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PostflightTests(unittest.TestCase):
    def run_cycle(self, dump_rc, postflight_rc):
        with tempfile.TemporaryDirectory(prefix='a50-runner-test-') as temp:
            base = Path(temp)
            (base / 'tools').mkdir()
            (base / 'bin').mkdir()
            runner = base / 'tools/m32_run_test.sh'
            runner.write_bytes((ROOT / 'tools/m32_run_test.sh').read_bytes())

            def script(path, body):
                path.write_text('#!/bin/sh\nset -eu\n' + body + '\n')
                path.chmod(0o700)

            script(base / 'bin/ssh', 'exit 0')
            script(base / 'bin/sleep', 'exit 0')
            script(base / 'bin/lsusb', 'echo "Bus 001 Device 001: ID 04e8:685d Mock Download"')
            script(base / 'bin/heimdall',
                   'echo flash >> "$A50_TEST_AUDIT"\n'
                   'printf "DTB upload successful\\nDTBO upload successful\\nBOOT upload successful\\n"')
            script(base / 'tools/m32_read_618.sh',
                   'echo dump >> "$A50_TEST_AUDIT"\nexit "$A50_TEST_DUMP_RC"')
            script(base / 'tools/m24_preflight.sh',
                   'echo postflight >> "$A50_TEST_AUDIT"\n'
                   'echo "== live phone (mock)"\n'
                   'if [ "$A50_TEST_POST_RC" -eq 0 ]; then echo "PRE-FLIGHT: ALL CHECKS PASSED"; fi\n'
                   'exit "$A50_TEST_POST_RC"')
            (base / 'test.img').write_bytes(b'mock image, never flashed')
            audit = base / 'audit.txt'
            env = os.environ.copy()
            env.update(PATH=str(base / 'bin') + os.pathsep + env['PATH'],
                       START_IN_DL='1', A50_TEST_AUDIT=str(audit),
                       A50_TEST_DUMP_RC=str(dump_rc), A50_TEST_POST_RC=str(postflight_rc))
            result = subprocess.run(['bash', str(runner), 'test.img', 'dump.txt', '192.0.2.1', '1'],
                                    cwd=base, env=env, text=True, capture_output=True, timeout=10)
            events = audit.read_text().splitlines()
            self.assertEqual(events, ['flash', 'flash', 'dump', 'postflight'], result.stdout + result.stderr)
            return result

    def test_missing_dump_still_checks_restore(self):
        result = self.run_cycle(1, 0)
        self.assertEqual(result.returncode, 1)
        self.assertIn('post-flight passed', result.stdout)

    def test_complete_dump_checks_restore(self):
        result = self.run_cycle(0, 0)
        self.assertEqual(result.returncode, 0)
        self.assertIn('PRE-FLIGHT: ALL CHECKS PASSED', result.stdout)

    def test_bad_restore_fails_with_complete_dump(self):
        self.assertNotEqual(self.run_cycle(0, 1).returncode, 0)

    def test_bad_restore_and_missing_dump_both_observed(self):
        self.assertNotEqual(self.run_cycle(1, 1).returncode, 0)


if __name__ == '__main__':
    unittest.main()
