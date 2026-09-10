#!/usr/bin/env python3
"""Prepare CLI archives and a Helm chart locally; never publish or authenticate."""
import argparse
import gzip
import json
import os
import pathlib
import shutil
import subprocess
import tarfile
import tempfile

from release_common import checksums, validate

ROOT = pathlib.Path(__file__).resolve().parents[1]


def cli_archive(binary, destination):
    # Strip host paths, timestamps and ownership from release archives.
    with destination.open('wb') as output:
        with gzip.GzipFile(filename='', mode='wb', fileobj=output, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode='w') as archive:
                for path, name, mode in ((binary, 'shadok', 0o755), (ROOT.parent / 'LICENSE', 'LICENSE', 0o644)):
                    info = tarfile.TarInfo(name)
                    info.size = path.stat().st_size
                    info.mode = mode
                    with path.open('rb') as source:
                        archive.addfile(info, source)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--image-prefix', required=True)
    parser.add_argument('--output', default='dist')
    args = parser.parse_args()
    try:
        validate(args.version, args.image_prefix)
    except ValueError as error:
        parser.error(str(error))
    out = pathlib.Path(args.output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, CGO_ENABLED='0')
    artifacts = []
    for system in ('darwin', 'linux'):
        for arch in ('amd64', 'arm64'):
            with tempfile.TemporaryDirectory(prefix='shadok-cli-package-') as tmp:
                binary = pathlib.Path(tmp) / 'shadok'
                subprocess.run([os.environ.get('GO', 'go'), 'build', '-trimpath', '-buildvcs=false', '-ldflags',
                                f'-s -w -X shadok.org/operator/internal/buildinfo.Version={args.version} -X shadok.org/operator/internal/buildinfo.ImagePrefix={args.image_prefix}',
                                '-o', str(binary), './cmd/shadok'], cwd=ROOT,
                               env=dict(env, GOOS=system, GOARCH=arch), check=True)
                destination = out / f'shadok_{args.version}_{system}_{arch}.tar.gz'
                cli_archive(binary, destination)
                artifacts.append(destination)
    with tempfile.TemporaryDirectory(prefix='shadok-chart-package-') as tmp:
        chart = pathlib.Path(tmp) / 'shadok'
        shutil.copytree(ROOT / 'chart', chart)
        values = (chart / 'values.yaml').read_text()
        for component in ('operator', 'tools', 'gateway'):
            placeholder = f'repository: shadok-{component},'
            if values.count(placeholder) != 1:
                raise ValueError(f'expected exactly one image placeholder for {component}')
            values = values.replace(placeholder, f'repository: {args.image_prefix}/{component},')
        (chart / 'values.yaml').write_text(values)
        subprocess.run(['helm', 'lint', str(chart), '--strict'], check=True)
        subprocess.run(['helm', 'package', str(chart), '--version', args.version,
                        '--app-version', args.version, '--destination', str(out)], check=True)
    artifacts.append(out / f'shadok-{args.version}.tgz')
    manifest = out / f'release-{args.version}.json'
    manifest.write_text(json.dumps({'version': args.version,
        'images': {c: f'{args.image_prefix}/{c}:{args.version}' for c in ('operator', 'tools', 'gateway')},
        'artifacts': [f.name for f in artifacts], 'published': False}, indent=2) + '\n')
    (out / f'SHA256SUMS-{args.version}').write_text(checksums([*artifacts, manifest]))
    print(f'Prepared {len(artifacts)} artifacts in {out}; images still need building/publishing.')


if __name__ == '__main__':
    main()
