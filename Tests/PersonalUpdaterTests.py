#!/usr/bin/env python3
"""Exercise the production worker and installer with temporary signed app fixtures."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

TOOLS = Path(__file__).resolve().parents[1] / 'Tools'
WORKER = TOOLS / 'personal-updater-worker.sh'


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args], text=True).strip()


with tempfile.TemporaryDirectory(prefix='vorssaint-updater-test-') as directory:
    root = Path(directory)
    upstream = root / 'upstream'
    upstream.mkdir()
    git(upstream, 'init', '-b', 'main')
    git(upstream, 'config', 'user.name', 'Updater Test')
    git(upstream, 'config', 'user.email', 'updater-test@example.invalid')
    (upstream / 'Tools').mkdir()
    shutil.copy2(TOOLS / 'personal-install.sh', upstream / 'Tools/personal-install.sh')
    script = upstream / 'build.sh'
    script.write_text('''#!/bin/bash
set -eu
printf '%s\\n' "$*" >> "$UPDATER_TEST_LOG"
mkdir -p build
printf '#!/bin/bash\\nexit 0\\n' > build/VorssaintDeveloper
chmod +x build/VorssaintDeveloper
app='build/stage.noindex/Vorssaint (Developer).app'
mkdir -p "$app/Contents/MacOS"
cp /bin/echo "$app/Contents/MacOS/Test"
printf '%s' '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Test</string><key>CFBundleIdentifier</key><string>test.vorssaint.updater</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>' > "$app/Contents/Info.plist"
codesign --force --sign - "$app"
''')
    script.chmod(0o755)
    working_script = script.read_text()
    (upstream / '.gitignore').write_text('build/\n')
    git(upstream, 'add', '.')
    git(upstream, 'commit', '-m', 'working source')
    working_commit = git(upstream, 'rev-parse', 'HEAD')
    state = root / 'state'
    state.mkdir()
    log = root / 'build-calls'
    app = root / 'Test.app'
    env = {**os.environ, 'UPDATER_TEST_LOG': str(log), 'VORSSAINT_UPDATER_APP_PATH': str(app)}
    command = ['/bin/bash', str(WORKER), str(upstream), 'main', str(state)]
    first = subprocess.run(command, env=env, capture_output=True, text=True)
    assert first.returncode == 0, first.stdout + first.stderr
    assert (state / 'installed-commit').read_text().strip() == working_commit
    assert log.read_text().splitlines() == [
        '--test-suite=utilities --test-suite=transient-paste --test-suite=settings', '--dev'
    ]
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    original = (app / 'Contents/MacOS/Test').read_bytes()

    # Same source and an installed app must not build or restart anything.
    log.write_text('')
    unchanged = subprocess.run(command, env=env, capture_output=True, text=True)
    assert unchanged.returncode == 0 and log.read_text() == ''

    # Failed validation must not reach installation or update the marker.
    script.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$UPDATER_TEST_LOG"\nexit 23\n')
    git(upstream, 'add', 'build.sh')
    git(upstream, 'commit', '-m', 'validation fails')
    failed = subprocess.run(command, env=env, capture_output=True, text=True)
    assert failed.returncode == 23, failed.stdout + failed.stderr
    assert (state / 'installed-commit').read_text().strip() == working_commit
    assert (app / 'Contents/MacOS/Test').read_bytes() == original

    # Dirty dedicated checkouts are left untouched.
    checkout = state / 'source'
    (checkout / 'build.sh').write_text('# local edit\n')
    dirty = subprocess.run(command, env=env, capture_output=True, text=True)
    assert dirty.returncode != 0 and (checkout / 'build.sh').read_text() == '# local edit\n'
    git(checkout, 'checkout', '--', 'build.sh')

    # Simulate a damaged candidate after build. Installer must reject it before
    # touching the old app, preserving both the app and success marker.
    script.write_text(working_script + '\nprintf damaged >> "build/stage.noindex/Vorssaint (Developer).app/Contents/MacOS/Test"\n')
    git(upstream, 'add', 'build.sh')
    git(upstream, 'commit', '-m', 'damaged install candidate')
    damaged = subprocess.run(command, env=env, capture_output=True, text=True)
    assert damaged.returncode != 0, damaged.stdout + damaged.stderr
    assert (app / 'Contents/MacOS/Test').read_bytes() == original
    assert (state / 'installed-commit').read_text().strip() == working_commit

print('Personal updater: signed user install, unchanged skip, validation failure, dirty checkout and damaged candidate protection passed.')
