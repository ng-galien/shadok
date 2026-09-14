#!/usr/bin/env python3
"""Reuse only successful push verification on main for the exact release commit."""
import json
import os
import subprocess


def verified(runs, sha, repository):
    return any(
        run.get('head_sha') == sha
        and run.get('head_branch') == 'main'
        and run.get('event') == 'push'
        and run.get('status') == 'completed'
        and run.get('conclusion') == 'success'
        and run.get('head_repository', {}).get('full_name') == repository
        for run in runs
    )


if __name__ == '__main__':
    repository = os.environ['REPOSITORY']
    sha = os.environ['RELEASE_SHA']
    result = subprocess.run([
        'gh', 'api', f'repos/{repository}/actions/workflows/verify.yml/runs'
        f'?head_sha={sha}&branch=main&event=push&per_page=100',
    ], text=True, capture_output=True)
    # API failures never bypass verification: run the full workflow instead.
    success = False
    if result.returncode == 0:
        success = verified(json.loads(result.stdout)['workflow_runs'], sha, repository)
    else:
        print('::warning::Could not look up prior verification; running full verification.')
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write(f'verified={str(success).lower()}\n')
    print('Reuse successful main verification' if success else 'Full verification required')
