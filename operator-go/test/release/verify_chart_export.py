#!/usr/bin/env python3
"""Compare an exported binary chart with its version-matched packaged chart."""
import argparse
import pathlib
import subprocess
import tarfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('archive', type=pathlib.Path)
parser.add_argument('export', type=pathlib.Path)
args = parser.parse_args()
with tarfile.open(args.archive) as archive:
    expected = {member.name.removeprefix('shadok/'): archive.extractfile(member).read()
                for member in archive.getmembers() if member.isfile()}
actual = {str(path.relative_to(args.export)): path.read_bytes()
          for path in args.export.rglob('*') if path.is_file()}
if actual.keys() != expected.keys():
    raise SystemExit(f'Chart files differ: extra={actual.keys() - expected.keys()}, missing={expected.keys() - actual.keys()}')
for name in expected:
    if name != 'Chart.yaml' and actual[name] != expected[name]:
        raise SystemExit(f'Chart content differs: {name}')
# Helm normalizes key order/quoting in packaged Chart.yaml; compare parsed output.
show = lambda path: subprocess.check_output(['helm', 'show', 'chart', str(path)])
if show(args.archive) != show(args.export):
    raise SystemExit('Chart metadata differs')
print(f'PASS: identical chart files, content and metadata ({len(actual)} files)')
