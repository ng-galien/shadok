"""Publication must never substitute a PR, other commit or failed run for main CI."""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / 'scripts'))
from verified_commit import verified


class VerifiedCommitTests(unittest.TestCase):
    def setUp(self):
        self.run = dict(head_sha='abc', head_branch='main', event='push',
                        status='completed', conclusion='success',
                        head_repository={'full_name': 'owner/repo'})

    def test_exact_main_success(self):
        self.assertTrue(verified([self.run], 'abc', 'owner/repo'))

    def test_untrusted_or_incomplete_runs_do_not_skip_checks(self):
        for field, value in [('head_sha', 'other'), ('head_branch', 'feature'),
                             ('event', 'pull_request'), ('status', 'in_progress'),
                             ('conclusion', 'failure'), ('conclusion', 'cancelled'),
                             ('head_repository', {'full_name': 'fork/repo'})]:
            with self.subTest(field=field, value=value):
                self.assertFalse(verified([{**self.run, field: value}], 'abc', 'owner/repo'))
        self.assertFalse(verified([], 'abc', 'owner/repo'))
