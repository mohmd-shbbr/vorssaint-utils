# NotchCraft 1.0.0-beta.3

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

## Updated in beta.3

- Bitwarden login and secure-note search, with a direct Control-Option-B
  shortcut configurable in Command Bar settings. Requires the official
  Bitwarden CLI; detects an existing Raycast-managed CLI when available.
- Separate Bitwarden sign-in profile. Unlock sessions are saved in macOS
  Keychain with Vault Timeout: Never, including sleep and app restarts.
  The master password is not saved. Use Lock to revoke the session.
- Protected items retain master-password re-prompt checks. Copies close the
  search window, are concealed from clipboard history, and expire after
  30 seconds unless replaced by another copy.
- Secure notes show both note text and custom fields. Failed retrieval no
  longer clears the search results.
- Screenshot previews dismiss on click-away, app switching, or Escape after
  focus moves elsewhere, while preserving active sharing and sheets.
- Reopen Last Screenshot Editor keeps annotations and undo/redo after
  Copy, Save or Shelf output. The retained session lasts until explicit
  discard, a newer capture, feature teardown or app exit; it is not written
  to disk. The existing Last Capture shortcut also resumes that session,
  or opens an unedited capture in edit mode. Its default binding is now
  Option-S; enable the shortcut in Screenshot settings if it is off.

Bitwarden first use: open its search window, sign in through the Terminal
button, then unlock. TOTP retrieval requires an eligible Bitwarden plan.
Vault data, session keys and CLI profiles are not included in settings exports
or this release. A Raycast-managed CLI remains an external dependency; choose
an independently installed CLI before removing Raycast's extension files.

## Updated in beta.2

- Command-bar currency conversion: `19 USD` defaults to INR; `19 USD to EUR`
  uses an explicit target. Supports common currency names and symbols.
- Daily exchange rates from Frankfurter, with rate dates and persistent offline
  cache. Only currency codes are sent to the rate service, never amounts.
- Verdana 10-point default for rich-text snippets. Existing personal snippets
  are not bundled or automatically rewritten by this release.

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

Snippet rich text uses Verdana 10 points by default. Destination apps may
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
