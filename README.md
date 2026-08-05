# Heptad

Heptad is a minimal rich-text note-taking app with exactly seven colour-coded notes. It runs as a macOS menu bar popup and as a standalone iOS app from one shared SwiftUI/SwiftData codebase, with no third-party dependencies.

There are always seven notes, never more or fewer. They are created on first launch and never added, deleted, or renamed — a note is identified by its colour and its position. Content is saved continuously, with no save button.

On macOS the app lives in the status bar. Left-clicking the icon — or pressing `⌃⌥Space` from any app — opens a floating panel anchored beneath it; the panel dismisses when you click elsewhere. Pinning it converts it into a regular movable window that stays open when you click into another app, and reopens where you left it. Pin from the toggle in the statistics bar, with `⌘P`, or by dragging the panel away. On iOS the same UI runs full-screen with a row of seven coloured circles for switching notes.

## Editing

Return continues a list — `- `, `* `, `1. `, and the checkbox forms `- [ ] ` and `- [x] ` — numbering upward and keeping the indent. Return on an empty item removes the marker and ends the list. On macOS `⌘⇧U` flips the checkbox on the current line. This is not Markdown: there is no parser, no preview pane, and nothing about how notes are stored changes.

Any note can be switched to plain text from the statistics bar. That flattens its formatting to a single monospaced font, makes paste unstyled, and turns the formatting shortcuts off for that note — useful for credentials, keys and anything else where a proportional font gets in the way. The text itself is kept; only the styling goes. The mode is stored per note.

On macOS `⌘⌫` clears the selected note, and the editor's context menu carries the same action. It is a single undo step, so `⌘Z` brings the note back.

## Titles and statistics

The bar beneath the editor shows the selected note's first line, its line, word and character counts, and when it was last edited. That first line is also the tooltip on each colour circle, so you can tell which note holds what without opening all seven. Empty notes read "Empty". In a narrow window the title gives way to the counts.

## Snapshots

The app keeps rotating local backups of all seven notes in Application Support: at most one every ten minutes while running, plus one when it quits, keeping the twenty most recent. Restore from the clock button in the statistics bar — restoring replaces all seven notes at once, so it asks first.

Plain JSON, no entitlements, invisible in normal use. It is a safety net for an accidental clear, not a sync folder and not a version browser.

## Status

Personal project. No signed or notarized builds, no releases — build it from source.

## Requirements

* macOS 14.0 or later, iOS 17.0 or later
* Xcode with matching SDKs — verified on Xcode 26.5
* [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build

**`project.yml` is the source of truth. `Heptad.xcodeproj` is XcodeGen output and is not committed** — a fresh clone has no Xcode project, so generate it first.

```bash
brew install xcodegen
xcodegen generate
```

Then build from the command line, or open `Heptad.xcodeproj` and pick the `Heptad-macOS` or `Heptad-iOS` scheme.

```bash
xcodebuild -project Heptad.xcodeproj -scheme Heptad-macOS build
xcodebuild -project Heptad.xcodeproj -scheme Heptad-iOS \
  -destination 'generic/platform=iOS Simulator' build
```

Tests and contribution details are in [CONTRIBUTING.md](./CONTRIBUTING.md).

## Keyboard shortcuts (macOS)

| Shortcut | Action |
| --- | --- |
| `⌃⌥Space` | Show / hide the window, from any app |
| `⌘P` | Pin / unpin the window |
| `⌘1`–`⌘7` | Select note 1–7 |
| `⌘0` | Select the first empty note |
| `⌘B` / `⌘I` / `⌘⇧X` | Bold / italic / strikethrough |
| `⌘+` / `⌘-` | Increase / decrease font size |
| `⌘⇧U` | Toggle the checkbox on the current line |
| `⌘⌫` | Clear the selected note |
| `⌘Z` / `⌘⇧Z` | Undo / redo |
| `⌘C` / `⌘X` / `⌘V` | Copy / cut / paste |
| `⌘⇧V` | Paste without formatting |
| `⌘A` | Select all |
| `⌘W` / `⌘Q` | Close window / quit |

`⌘B`, `⌘I` and `⌘⇧X` do nothing in a plain-text note, which is one uniform font by definition.

Editing, formatting and clipboard shortcuts require a focused editor; note switching, `⌘P`, `⌘W`, and `⌘Q` do not. `⌃⌥Space` is registered system-wide and works while another app is frontmost — it needs no Accessibility permission.

## License

This project is released under the MIT License.

See [LICENSE](./LICENSE) for the full text.
