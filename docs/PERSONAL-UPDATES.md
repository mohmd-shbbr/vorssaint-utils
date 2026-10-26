# Keeping the personal fork up to date

This fork preserves the custom rich-text snippets and argument inputs while
following stable Vorssaint releases. It does not use the official app updater.

## GitHub side

The `Personal fork — validated upstream sync` workflow checks the latest stable
upstream release daily at 03:17 UTC. It merges the release into
`feature/rich-snippets-and-arguments` in a temporary checkout, runs the full
upstream tests plus the personal updater tests, builds the app, and runs its
self-test. Only a passing merge is pushed to the personal branch.

A merge conflict, failed test, failed build, or concurrent branch change stops
publication. GitHub Actions shows the failure; the installed app remains on its
last working version. Changes are never force-pushed. The workflow does not
post issues or comments or publish an official-looking app release.

If upstream later implements rich snippets, the overlapping custom code needs a
review before it is retired. The workflow intentionally does not guess whether a
new native implementation covers your formatting, dropdowns and backup needs.

## Your Mac

Run this once from a checkout of the personal branch:

```sh
./Tools/personal-updater.sh --install-service
```

A user LaunchAgent checks the personal GitHub branch every six hours while the
Mac is awake and once at login. When the source changes, it runs the relevant
snippet/settings tests, builds the separate Developer app, runs its self-test,
and installs its verified, locally signed bundle in
`/Applications/Vorssaint (Developer).app` when that folder is writable, or
`~/Applications/Vorssaint (Developer).app` otherwise, using a reversible swap.
The chosen path is recorded in the LaunchAgent so later checks use the same app.

The per-user installation needs no administrator access. The build uses this Mac's stable local signing identity. No signing key is
uploaded to GitHub. Your Developer app's settings and rich snippets stay in the
same preference domain. The official Vorssaint app remains separate.

The dedicated source checkout is at
`~/Library/Application Support/VorssaintPersonalUpdater/source`; logs are at
`~/Library/Logs/VorssaintPersonalUpdater/`. The last successful source revision is
recorded only after installation succeeds. Local edits in this dedicated checkout
stop the updater instead of being discarded. Normal settings and snippets are
stored separately by the app.

This requires Apple's command-line developer tools and an Apple Silicon Mac.
It compiles updates locally rather than downloading a notarized custom binary.
The app can restart when an update installs. No cloud sync of your settings is
involved.

To check GitHub connectivity without building or installing:

```sh
./Tools/personal-updater.sh --check
```

To stop automatic updates, retaining the app, settings, source and logs:

```sh
./Tools/personal-updater.sh --uninstall-service
```

On a second Mac, install the same custom branch and its updater service there,
then restore your settings file under **Settings → Advanced → Import Settings**.
Each Mac keeps its own local signing identity and macOS permissions.

## Controls

The personal workflow can also be run manually under GitHub **Actions**.
Scheduled workflows on forks need GitHub Actions enabled; inactive public
repositories may need the schedule re-enabled through GitHub later. The local
updater cannot create a new upstream merge while the GitHub workflow is disabled.
