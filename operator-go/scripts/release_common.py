"""Shared validation and checksums for explicit local release commands."""
import hashlib
import re


def validate(version, image_prefix):
    number = r'(?:0|[1-9][0-9]*)'
    identifier = r'(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
    if not re.fullmatch(rf'{number}\.{number}\.{number}(?:-{identifier}(?:\.{identifier})*)?', version):
        raise ValueError('version must be SemVer without leading v or build metadata (OCI tags cannot contain +)')
    if len(version) > 128:
        raise ValueError('version exceeds the OCI tag length limit')
    if not re.fullmatch(r'[a-z0-9][a-z0-9.:-]*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*', image_prefix):
        raise ValueError('image-prefix must be a lowercase registry/path without trailing slash')


def checksums(paths):
    lines = []
    for path in sorted(paths):
        digest = hashlib.sha256()
        with path.open('rb') as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b''):
                digest.update(chunk)
        lines.append(f'{digest.hexdigest()}  {path.name}\n')
    return ''.join(lines)
