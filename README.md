# Heptad

Heptad is a minimal Markdown note-taking app with exactly seven colour-coded notes. It runs as a macOS menu bar popup and as a standalone iOS app from one shared SwiftUI/SwiftData codebase, with no third-party dependencies.

There are always seven notes, never more or fewer. They are created on first launch and never added, deleted, or renamed — a note is identified by its colour and its position. Content is saved continuously, with no save button.

On macOS the app lives in the status bar. Left-clicking the icon — or pressing `⌃⌥Space` from any app — opens a floating panel anchored beneath it; the panel dismisses when you click elsewhere. Pinning it converts it into a regular movable window that stays open when you click into another app, and reopens where you left it. Pin from the toggle in the statistics bar, with `⌘P`, or by dragging the panel away. On iOS the same UI runs full-screen with a row of seven coloured circles for switching notes.

## Editing

A note is Markdown source. The editor holds the literal text — `**bold**`, `[label](url)` — and styles it in place, dimming the delimiters rather than hiding them, so the caret can move through everything that is there. There is no preview pane and no second representation: what the note stores is what you see, and copying one out gives back the same characters.

The vocabulary is small on purpose, and it is exactly what the commands can produce and remove:

| Markdown | Command |
| --- | --- |
| `**bold**`, `*italic*`, `~~strikethrough~~` | `⌘B`, `⌘I`, `⌘⇧X` |
| `[label](url)` | typed, or carried in by `⌘V` |
| `- `, `* `, `1. ` | Return continues the list |
| `- [ ] `, `- [x] ` | `⌘⇧U` flips the box |

Return continues a list, numbering upward and keeping the indent; Return on an empty item removes the marker and ends the list.

Constructs do not nest and do not span lines, and there are no backslash escapes — a note that genuinely contains `**` will show it styled. That is the accepted cost of a parser small enough to hold in your head.

Any note can be switched to plain text from the statistics bar: monospaced, with its Markdown left as literal text and the formatting shortcuts turned off — useful for credentials, keys and anything else where a proportional font gets in the way. Switching is a rendering choice and never edits the note, so it is reversible as often as you like. The mode is stored per note.

Pasting converts the clipboard's formatting to Markdown, keeping bold, italic, strikethrough and links, and dropping everything Heptad has no spelling for. Nothing can enter a note that its own commands cannot take back out.

On macOS `⌘⌫` clears the selected note, and the editor's context menu carries the same action. It is a single undo step, so `⌘Z` brings the note back.

## Statistics

The bar beneath the editor shows the selected note's line, word and character counts and when it was last edited, on the left; the plain-text and pin controls sit on the right. In a narrow window the counts truncate and the controls stay put.

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
| `⌘+` / `⌘-` | Increase / decrease the editor's zoom |
| `⌘⇧U` | Toggle the checkbox on the current line |
| `⌘⌫` | Clear the selected note |
| `⌘Z` / `⌘⇧Z` | Undo / redo |
| `⌘C` / `⌘X` | Copy / cut |
| `⌘V` | Paste, converting the clipboard's formatting to Markdown |
| `⌘⇧V` | Paste as raw text, dropping the formatting entirely |
| `⌘A` | Select all |
| `⌘W` / `⌘Q` | Close window / quit |

`⌘B`, `⌘I` and `⌘⇧X` wrap the selection in delimiters, and each is its own inverse: pressing it again on the text it wrapped takes them off. They do nothing in a plain-text note, which leaves its Markdown literal.

`⌘+` and `⌘-` set one zoom level for every note rather than sizing a run of text, since font size is the one thing with no Markdown spelling.

Editing, formatting and clipboard shortcuts require a focused editor; note switching, `⌘P`, `⌘W`, and `⌘Q` do not. `⌃⌥Space` is registered system-wide and works while another app is frontmost — it needs no Accessibility permission.

## License

This project is released under the MIT License.

See [LICENSE](./LICENSE) for the full text.
