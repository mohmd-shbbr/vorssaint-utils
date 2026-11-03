#!/usr/bin/env python3
"""Run the production Linux preflight with real Git merge fixtures, no network."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
def workflow(path):
    return json.loads(subprocess.check_output(['ruby', '-ryaml', '-rjson', '-e',
        'puts JSON.generate(YAML.load_file(ARGV[0]))', str(ROOT / path)], text=True))
wf = workflow('.github/workflows/personal-upstream-sync.yml')
step = next(s for s in wf['jobs']['check']['steps'] if s.get('id') == 'check')
script = step['run'].replace('git fetch https://github.com/vorssaint/vorssaint-utils.git', 'git fetch "$SYNC_TEST_UPSTREAM"')
assert wf['jobs']['check']['runs-on'] == 'ubuntu-latest'
assert wf['jobs']['validate']['needs'] == 'check'
assert wf['jobs']['validate']['if'] == "needs.check.outputs.needed == 'true'"
issues = workflow('.github/workflows/issue-fix-status.yml')
assert all("github.repository == 'vorssaint/vorssaint-utils'" in j['if'] for j in issues['jobs'].values())

def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args], text=True, stderr=subprocess.DEVNULL).strip()
def commit(repo, message):
    git(repo, 'add', '.'); git(repo, 'commit', '-m', message)

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    upstream = root / 'upstream'; upstream.mkdir()
    git(upstream, 'init', '-b', 'main')
    git(upstream, 'config', 'user.name', 'Fixture')
    git(upstream, 'config', 'user.email', 'fixture@example.invalid')
    (upstream / 'shared').write_text('base\n'); commit(upstream, 'base')
    base = git(upstream, 'rev-parse', 'HEAD')
    (upstream / 'shared').write_text('upstream\n'); commit(upstream, 'release')
    git(upstream, 'tag', 'v1')
    binaries = root / 'bin'; binaries.mkdir()
    (binaries / 'gh').write_text('#!/bin/sh\nprintf "v1\\n"\n'); (binaries / 'gh').chmod(0o755)
    for scenario, needed in [('unchanged', 'false'), ('clean', 'true'), ('conflict', 'false')]:
        repo = root / scenario
        subprocess.run(['git', 'clone', str(upstream), str(repo)], check=True, capture_output=True)
        git(repo, 'config', 'user.name', 'Fixture'); git(repo, 'config', 'user.email', 'fixture@example.invalid')
        if scenario != 'unchanged':
            git(repo, 'reset', '--hard', base)
            (repo / ('shared' if scenario == 'conflict' else 'custom')).write_text('custom\n')
            commit(repo, 'custom work')
        before = git(repo, 'rev-parse', 'HEAD')
        output = root / (scenario + '.outputs'); summary = root / (scenario + '.summary')
        env = {**os.environ, 'PATH': str(binaries) + ':' + os.environ['PATH'],
               'SYNC_TEST_UPSTREAM': str(upstream), 'GITHUB_OUTPUT': str(output),
               'GITHUB_STEP_SUMMARY': str(summary), 'RUNNER_TEMP': str(root)}
        result = subprocess.run(['bash', '-c', script], cwd=repo, env=env, text=True, capture_output=True)
        assert result.returncode == 0, result.stderr
        values = dict(line.split('=', 1) for line in output.read_text().splitlines())
        assert values['needed'] == needed, scenario
        assert git(repo, 'rev-parse', 'HEAD') == before
        assert not git(repo, 'status', '--porcelain')
        if scenario == 'conflict': assert 'Manual merge needed' in summary.read_text()
        print(scenario + ': PASS (branch unchanged)')
print('Upstream sync workflow checks: PASS')
