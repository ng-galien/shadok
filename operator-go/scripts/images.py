#!/usr/bin/env python3
"""Build versioned OCI image archives or explicitly push to a chosen registry."""
import argparse
import json
import pathlib
import subprocess

from release_common import checksums, validate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--image-prefix', required=True)
    parser.add_argument('--builder', required=True, help='Buildx builder supporting OCI export, e.g. docker-container')
    parser.add_argument('--platforms', default='linux/amd64,linux/arm64')
    parser.add_argument('--build-image', default='golang:1.26')
    parser.add_argument('--runtime-image', default='gcr.io/distroless/static:nonroot')
    parser.add_argument('--output', default='dist')
    parser.add_argument('--push', action='store_true', help='Publish to the supplied registry instead of local OCI archives')
    args = parser.parse_args()
    try:
        validate(args.version, args.image_prefix)
    except ValueError as error:
        parser.error(str(error))
    platforms = args.platforms.split(',')
    if any(platform not in ('linux/amd64', 'linux/arm64') for platform in platforms):
        parser.error('supported platforms: linux/amd64,linux/arm64')
    if len(set(platforms)) != len(platforms):
        parser.error('duplicate platform')
    root = pathlib.Path(__file__).resolve().parents[1]
    out = pathlib.Path(args.output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    components = ('operator', 'gateway', 'tools')
    artifacts = []
    for component in components:
        metadata = out / f'{component}-{args.version}.metadata.json'
        command = ['docker', 'buildx', 'build', '--builder', args.builder,
                   '--platform', args.platforms, '--target', component,
                   '--build-arg', 'VERSION=' + args.version,
                   '--build-arg', 'IMAGE_PREFIX=' + args.image_prefix,
                   '--build-arg', 'BUILD_IMAGE=' + args.build_image,
                   '--build-arg', 'RUNTIME_IMAGE=' + args.runtime_image,
                   '--tag', f'{args.image_prefix}/{component}:{args.version}',
                   '--metadata-file', str(metadata)]
        artifacts.append(metadata)
        if args.push:
            command.append('--push')
        else:
            archive = out / f'{component}-{args.version}.oci.tar'
            command += ['--output', f'type=oci,dest={archive}']
            artifacts.append(archive)
        subprocess.run(command + [str(root)], check=True)
    manifest = out / f'images-{args.version}.json'
    manifest.write_text(json.dumps({
        'version': args.version, 'platforms': platforms,
        'buildImage': args.build_image, 'runtimeImage': args.runtime_image,
        'images': {c: f'{args.image_prefix}/{c}:{args.version}' for c in components},
        'pushed': args.push,
    }, indent=2) + '\n')
    (out / f'SHA256SUMS-images-{args.version}').write_text(checksums([*artifacts, manifest]))


if __name__ == '__main__':
    main()
