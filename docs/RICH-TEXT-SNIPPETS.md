# Rich snippets and arguments — custom Developer build

This custom build adds rich-text snippet editing and argument inputs to upstream
Vorssaint commit `746239b0220571d6694ffacae79f3eb9dcd09193`.

## Install and use

1. Extract `Vorssaint-Developer-rich-snippets.zip` and move **Vorssaint (Developer).app** to Applications.
2. Open the Developer app. It uses separate settings and permissions from the official app.
3. Enable Text Snippets and grant Accessibility access when macOS requests it for expansion.
4. Add or edit a snippet. Paste existing formatted text, or select text and use the toolbar.

The toolbar supports bold, italic, underline, strikethrough, bulleted and numbered
lists, hyperlinks, alignment, font/size selection, and text colour. Select the
link text before using the link button; an empty URL removes an existing link.
Native lists continue when you press Return. The plus button inserts `{argument}`.

Rich snippets use HTML and RTF paste with a plain-text fallback. A destination
must accept rich-text paste to preserve formatting. Text-only fields receive
ordinary text, including visible list markers. The clipboard is restored after
insertion unless you copy something else in the meantime.

## A dropdown example

Use this as a snippet's replacement:

```text
https://portal{argument name="DC" options=".com,.eu"}.example.com/admin/
```

Expanding it opens a DC dropdown. Choosing `.com` inserts
`https://portal.com.example.com/admin/`; choosing `.eu` inserts
`https://portal.eu.example.com/admin/`. These are literal substitutions. The app
does not open either URL, generate content, or call an AI service.

Both typed triggers and insertion from the snippet menu support arguments.

| Placeholder | Behaviour |
| --- | --- |
| `{argument}` | A required text input; each unnamed occurrence gets its own field. |
| `{argument name="Customer"}` | A required named text input; repeated names reuse one value. |
| `{argument name="DC" options=".com,.eu"}` | A required dropdown. |
| `{argument name="DC" options=".com,.eu" default=".eu"}` | A dropdown with a default value. |
| `{argument name="Reference" default=""}` | An optional text input. |
| `{argument name="Value" type="password"}` | A masked text input. |

Values are requested for each insertion and are not saved as argument history.
A default makes an argument optional. Without a default, entering a value is
required. User-entered text is inserted literally; braces or markup in it do not
trigger another expansion. Formatting on a placeholder carries into its value.
The existing `{{date}}`, `{{time}}`, and `{{clipboard}}` syntax remains available.
This implements snippet input fields, not Raycast's extension runtime or all of
Raycast's other placeholders and modifiers.

## Export to another Mac and restore

The upstream app already has a complete local settings backup:

1. On the source Mac, open **Settings → Advanced**.
2. Choose **Export Settings** and save `Vorssaint Settings.plist`.
3. Copy that file to the other Mac by any method you prefer.
4. Install the same custom Developer build on that Mac.
5. Open **Settings → Advanced → Import Settings**, choose the file, and confirm.
   The app replaces its portable settings and relaunches.

This file includes snippets, names, triggers, folders, rich formatting, argument
placeholder definitions, snippet feature switches, shortcuts, feature choices,
and other portable preferences. No cloud service is involved. It also lets you
move the official app's existing settings into the Developer build: export from
the official app and import into the Developer app.

Import is a restore, not a merge. Export the receiving app's current settings
first if you want a way back. Use this custom build on both Macs for the new
formatting and argument behaviour. An older official build cannot interpret the
new argument feature.

macOS permissions, clipboard history, Shelf items, Scratchpad notes, local-file
access grants, and machine-specific runtime state are not transported. Grant
permissions and select local folders again on the receiving Mac where needed.

## Build and scope

The source archive includes the full modified source, resources, license, and
build tools. The patch applies to the upstream commit above. To rebuild on an
Apple Silicon Mac with the command-line developer tools:

```sh
./build.sh --dev
./build/VorssaintDeveloper --selftest
./build.sh --test-suite=utilities --test-suite=transient-paste --test-suite=settings
```

The app is a locally signed Developer build, not an official notarized release.
The official updater stays disabled for this separate Developer build. The
personal upstream workflow and local updater can keep it current while retaining
the custom changes; see [automatic personal updates](PERSONAL-UPDATES.md).

Validation was performed on macOS 26.7.1. Relevant automated suites cover snippet
storage, style/list serialization, argument parsing and literal substitution,
a generic dropdown example, clipboard restoration, and the complete settings-file round
trip. Native editor previews were used to check bold, links, bullets, numbered
list continuation, and the argument dialog. Insertion into your particular email,
browser, or editor apps still needs a trial; the actual second-Mac restore has
not been exercised on a second physical device.
