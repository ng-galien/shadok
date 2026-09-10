#!/usr/bin/env python3
"""Fail closed unless a version tag points into the repository's default main branch."""
import argparse
import os
import pathlib
import subprocess

from release_common import validate


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


def chart_versions(path):
    values = {}
    for line in path.read_text().splitlines():
        if line.startswith(('version:', 'appVersion:')):
            key, value = line.split(':', 1)
            if key in values:
                raise ValueError(f'duplicate chart {key}')
            values[key] = value.strip().strip('\"\'')
    return values


def guard(root, ref, default_branch, expected_sha):
    if default_branch != 'main':
        raise ValueError('release policy requires the actual default branch to be main')
    if not ref.startswith('refs/tags/v'):
        raise ValueError('releases require a v-prefixed tag ref')
    version = ref.removeprefix('refs/tags/v')
    validate(version, 'ghcr.io/ng-galien/shadok')
    tag_commit = git(root, 'rev-parse', '--verify', ref + '^{commit}')
    head = git(root, 'rev-parse', 'HEAD')
    expected = git(root, 'rev-parse', '--verify', expected_sha + '^{commit}')
    if head != tag_commit or head != expected:
        raise ValueError('checkout, event commit and tag must identify the same commit')
    # The caller fetches this exact remote ref immediately before invoking us.
    git(root, 'rev-parse', '--verify', 'refs/remotes/origin/main^{commit}')
    result = subprocess.run(['git', '-C', str(root), 'merge-base', '--is-ancestor',
                             tag_commit, 'refs/remotes/origin/main'], check=False)
    if result.returncode != 0:
        raise ValueError('tagged commit does not belong to origin/main')
    versions = chart_versions(root / 'operator-go/chart/Chart.yaml')
    if versions != {'version': version, 'appVersion': version}:
        raise ValueError('tag must match chart version and appVersion exactly')
    version_file = root / 'VERSION'
    if version_file.exists() and version_file.read_text().strip() != version:
        raise ValueError('tag must match VERSION exactly')
    return version


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ref', required=True)
    parser.add_argument('--default-branch', required=True)
    parser.add_argument('--sha', required=True)
    parser.add_argument('--root', type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    try:
        version = guard(args.root, args.ref, args.default_branch, args.sha)
    except (ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'release rejected: {error}\n')
    if output := os.environ.get('GITHUB_OUTPUT'):
        with open(output, 'a') as destination:
            destination.write(f'version={version}\n')
    print(version)


if __name__ == '__main__':
    main()
