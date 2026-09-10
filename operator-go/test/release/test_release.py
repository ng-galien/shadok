"""Offline release contract tests; no Docker daemon or external registry required."""
import importlib.util
import json
import pathlib
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = pathlib.Path(__file__).resolve().parents[2] / 'scripts'
sys.path.insert(0, str(SCRIPTS))
from release_common import checksums, validate
spec = importlib.util.spec_from_file_location('shadok_package', SCRIPTS / 'package.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class ReleaseTests(unittest.TestCase):
    def test_versions_match_semver_and_oci_tags(self):
        for version in ('0.1.0', '1.2.3-rc.1', '1.2.3-alpha-01'):
            validate(version, 'localhost:15000/team/shadok')
        for version in ('01.2.3', '1.2.3-01', '1.2.3-', '1.2.3-rc..1', 'v1.2.3', '1.2.3+metadata'):
            with self.subTest(version=version), self.assertRaises(ValueError):
                validate(version, 'example.org/shadok')
        for prefix in ('https://example.org/shadok', 'example.org/team/', '../bad', 'UPPER/repo', 'example.org/a//b'):
            with self.subTest(prefix=prefix), self.assertRaises(ValueError):
                validate('1.2.3', prefix)

    def test_archive_is_reproducible_and_contains_executable_and_license(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            binary = root / 'binary'
            binary.write_bytes(b'example binary')
            first, second = root / 'first.tar.gz', root / 'second.tar.gz'
            package.cli_archive(binary, first)
            package.cli_archive(binary, second)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            with tarfile.open(first) as archive:
                self.assertEqual(archive.getnames(), ['shadok', 'LICENSE'])
                license_info = archive.getmember('LICENSE')
                self.assertEqual((license_info.mode, license_info.uid, license_info.gid, license_info.mtime), (0o644, 0, 0, 0))
                self.assertEqual(archive.extractfile(license_info).read(), (package.ROOT.parent / 'LICENSE').read_bytes())
                info = archive.getmember('shadok')
                self.assertEqual((info.mode, info.uid, info.gid, info.mtime), (0o755, 0, 0, 0))
                self.assertEqual(archive.extractfile(info).read(), binary.read_bytes())
            self.assertIn('  first.tar.gz\n', checksums([first]))

    def test_chart_license_matches_canonical_root_license(self):
        self.assertEqual((package.ROOT / 'chart/LICENSE').read_bytes(),
                         (package.ROOT.parent / 'LICENSE').read_bytes())

    def test_bundle_cross_compiles_and_rewrites_all_image_references(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            calls = []
            def run(command, **kwargs):
                calls.append((command, kwargs))
                if command[1] == 'build':
                    pathlib.Path(command[command.index('-o') + 1]).write_bytes(b'compiled')
                elif command[:2] == ['helm', 'lint']:
                    values = (pathlib.Path(command[2]) / 'values.yaml').read_text()
                    for component in ('operator', 'gateway', 'tools'):
                        self.assertIn(f'repository: registry.example/team/{component},', values)
                elif command[:2] == ['helm', 'package']:
                    (root / 'shadok-1.2.3.tgz').write_bytes(b'chart')
            with patch.object(sys, 'argv', ['package.py', '--version', '1.2.3', '--image-prefix',
                                           'registry.example/team', '--output', tmp]), patch.object(package.subprocess, 'run', side_effect=run):
                package.main()
            builds = [kwargs['env'] for command, kwargs in calls if command[1] == 'build']
            for command, _ in calls:
                if command[1] == 'build':
                    self.assertIn('-buildvcs=false', command)
                    self.assertIn('buildinfo.ImagePrefix=registry.example/team', command[command.index('-ldflags') + 1])
            self.assertEqual({(env['GOOS'], env['GOARCH']) for env in builds},
                             {('darwin', 'amd64'), ('darwin', 'arm64'), ('linux', 'amd64'), ('linux', 'arm64')})
            manifest = json.loads((root / 'release-1.2.3.json').read_text())
            self.assertFalse(manifest['published'])
            self.assertEqual(len(manifest['artifacts']), 5)
            self.assertEqual((root / 'SHA256SUMS-1.2.3').read_text(),
                             checksums([root / name for name in manifest['artifacts']] + [root / 'release-1.2.3.json']))

    def test_images_default_to_offline_archives_with_metadata(self):
        spec = importlib.util.spec_from_file_location('shadok_images', SCRIPTS / 'images.py')
        images = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(images)
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            calls = []
            def run(command, **kwargs):
                calls.append(command)
                pathlib.Path(command[command.index('--metadata-file') + 1]).write_text('{}')
                pathlib.Path(command[command.index('--output') + 1].split('dest=', 1)[1]).write_bytes(b'oci')
            with patch.object(sys, 'argv', ['images.py', '--version', '1.2.3', '--image-prefix',
                                           'registry.example/team', '--builder', 'review', '--output', tmp]), patch.object(images.subprocess, 'run', side_effect=run):
                images.main()
            self.assertEqual(len(calls), 3)
            self.assertTrue(all('--push' not in command for command in calls))
            self.assertTrue(all('linux/amd64,linux/arm64' in command for command in calls))
            self.assertTrue(all('IMAGE_PREFIX=registry.example/team' in command for command in calls))
            manifest = json.loads((root / 'images-1.2.3.json').read_text())
            self.assertFalse(manifest['pushed'])
            self.assertEqual(len((root / 'SHA256SUMS-images-1.2.3').read_text().splitlines()), 7)


if __name__ == '__main__':
    unittest.main()
