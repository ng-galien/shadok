import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / 'scripts'))
from release_guard import guard


class GuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        self.git('init', '-b', 'main')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'user.name', 'Release test')
        self.chart = self.root / 'operator-go/chart/Chart.yaml'
        self.chart.parent.mkdir(parents=True)
        self.chart.write_text('apiVersion: v2\nname: shadok\nversion: 1.0.0\nappVersion: "1.0.0"\n')
        self.git('add', '.')
        self.git('commit', '-m', 'Initial')
        self.sha = self.git('rev-parse', 'HEAD')
        self.git('update-ref', 'refs/remotes/origin/main', self.sha)
        self.git('tag', 'v1.0.0')

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args], text=True, stderr=subprocess.DEVNULL).strip()

    def check(self, ref='refs/tags/v1.0.0', branch='main', sha=None):
        return guard(self.root, ref, branch, sha or self.sha)

    def test_main_tag_and_annotated_tag_are_accepted(self):
        self.assertEqual(self.check(), '1.0.0')
        self.git('tag', '-f', '-a', 'v1.0.0', '-m', 'Release')
        self.assertEqual(self.check(), '1.0.0')

    def test_tagged_ancestor_of_updated_main_is_accepted(self):
        (self.root / 'later').write_text('later main change')
        self.git('add', '.')
        self.git('commit', '-m', 'Later main commit')
        self.git('update-ref', 'refs/remotes/origin/main', self.git('rev-parse', 'HEAD'))
        self.git('checkout', '--detach', self.sha)
        self.assertEqual(self.check(), '1.0.0')

    def test_unmerged_feature_tag_is_rejected(self):
        self.git('switch', '-c', 'feature')
        (self.root / 'feature').write_text('change')
        self.git('add', '.')
        self.git('commit', '-m', 'Feature')
        self.git('tag', '-f', 'v1.0.0')
        with self.assertRaisesRegex(ValueError, 'does not belong'):
            self.check(sha=self.git('rev-parse', 'HEAD'))

    def test_branch_event_wrong_default_and_version_mismatch_are_rejected(self):
        for ref, branch in [('refs/heads/main', 'main'), ('refs/tags/v1.0.0', 'develop'),
                            ('refs/tags/v01.0.0', 'main')]:
            with self.subTest(ref=ref, branch=branch), self.assertRaises(ValueError):
                self.check(ref, branch)
        self.chart.write_text('version: 1.0.1\nappVersion: 1.0.0\n')
        with self.assertRaisesRegex(ValueError, 'chart version'):
            self.check()

    def test_mismatched_event_commit_is_rejected(self):
        (self.root / 'next').write_text('next')
        self.git('add', '.')
        self.git('commit', '-m', 'Next')
        with self.assertRaisesRegex(ValueError, 'same commit'):
            self.check()

    def test_optional_version_file_must_match(self):
        (self.root / 'VERSION').write_text('2.0.0\n')
        with self.assertRaisesRegex(ValueError, 'VERSION'):
            self.check()


if __name__ == '__main__':
    unittest.main()
