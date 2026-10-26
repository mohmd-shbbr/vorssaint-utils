# NotchCraft 1.0.0-beta.1

NotchCraft is an independent, unofficial fork of
[Vorssaint](https://github.com/vorssaint/vorssaint-utils), licensed under
GPL-3.0-or-later. It is not endorsed by the original maintainer. Original
copyright notices are retained. Its app name, icon, bundle identity and signing
identity differ from official Vorssaint.

## Requirements and installation

- Apple silicon Mac (M1 or newer), macOS 14 or later. Some features require
  newer macOS versions or particular hardware. Intel builds are not included.
- Download the DMG from this fork's GitHub Releases, open it, and drag
  **NotchCraft.app** into **Applications**.
- This community build is self-signed, not signed with an Apple Developer ID
  and not notarized by Apple. macOS may block the first launch. If you trust
  this source, attempt to open the app, then use **System Settings → Privacy &
  Security → Open Anyway**. Do not disable Gatekeeper globally.
- Grant only the macOS permissions needed for the features you enable.

## Added in this fork

- Rich text snippets: hyperlinks, bold, italic, underline and lists.
- Named snippet arguments with configurable choices and native editing.
- Immediate trigger matching with a one-second pause before expansion,
  allowing overlapping trigger names.
- Local settings and snippet export/import, without cloud sync.
- Menu-bar world clock and compact Dynamic Island time comparison, using
  the timer ruler and trackpad haptics. Edit either tile's date and time to
  update both zones, including daylight saving changes.
- Calendar selection shared by Dynamic Island and upcoming meeting display
  in the menu bar.

Snippet rich text uses Verdana 10 CSS px by default. Destination apps may
choose their own paste formatting.

## Privacy and updates

The downloadable app is built from tracked source in a clean checkout. It
does not contain the maintainer's snippets, trigger words, calendars, accounts,
preferences, recordings, Raycast backup, clipboard history or credentials.
Each installation starts with its own settings under
`io.github.mohmd-shbbr.notchcraft`; no personal import is performed.

The original application's local utilities and integrations remain available;
this is not a claim that every optional integration operates offline. Personal
calendar content is read on your Mac after permission is granted. Settings
exports you create can contain private data; share those only deliberately.

Updates for this public build are manual downloads from
[this fork's Releases](https://github.com/mohmd-shbbr/vorssaint-utils/releases).
It never installs official upstream releases over the fork. The maintainer's
private local updater is not included or installed by this download.

## Source and validation

The release tag identifies the corresponding GPL source. A source archive is
attached alongside the DMG and checksums. Build with `./build.sh --community`.
Without a community signing certificate, a local build is ad-hoc signed;
protected fan control requires a certificate-backed signature.

The app self-test and the focused snippet, settings, calendar and world-clock
checks were run during development. A clipboard-history virtualization UI test
is intermittent on both the pre-change baseline and the modified source; it
is not treated as a passing full-suite result.
