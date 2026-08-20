# Heptad

Heptad is a minimal Markdown note-taking app with exactly seven colour-coded notes. It runs as a macOS menu bar popup and as a standalone iOS app from one shared SwiftUI/SwiftData codebase, with no third-party dependencies.

There are always seven notes, never more or fewer. They are created on first launch and never added, deleted, or renamed — a note is identified by its colour and its position. Content is saved continuously, with no save button.

On macOS the app lives in the status bar. Left-clicking the icon — or pressing `⌃⌥Space` from any app — opens a floating panel anchored beneath it; the panel dismisses when you click elsewhere. Pinning it converts it into a regular movable window that stays open when you click into another app, and reopens where you left it. Pin from the toggle in the statistics bar, with `⌘P`, or by dragging the panel away. On iOS the same UI runs full-screen with a row of seven coloured circles for switching notes.

## Editing

A note is Markdown source. The editor draws what that source means rather than the source itself — `**bold**` is a bold run, with no asterisks left in the buffer for a caret to stall on or a backspace to break in half. The delimiters are written back when the note is saved, so nothing is stored but the Markdown, and copying a note out gives back its own characters. There is no preview pane: switching a note to plain text is how you read the source.

The vocabulary is small on purpose, and it is exactly what the commands can produce and remove:

| Markdown | Command |
| --- | --- |
| `**bold**`, `_italic_`, `~~strikethrough~~` | `⌘B`, `⌘I`, `⌘⇧X` |
| `[label](url)` | typed, or carried in by `⌘V` |
| `- `, `* `, `1. ` | Return continues the list |
| `- [ ] `, `- [x] ` | `⌘⇧U` flips the box |

Return continues a list, numbering upward and keeping the indent; Return on an empty item removes the marker and ends the list.

Italic is written `_`, not `*`. Every delimiter is disjoint from every other, so `**_both_**` is reachable and reversible, and `*` is left an ordinary character — `2 * 3` and `SELECT *` mean what they say. An underscore inside a word belongs to the word, so `AWS_SECRET_KEY` and `__init__` are never italicised; where a `_` pair could not be read back against a word character, the save spells that run `*` instead. `***both***` is read as bold italic, because that is how Markdown written elsewhere spells it, and rewritten as `**_both_**`.

Bold is drawn in the note's own colour, derived from the colour the window is already wearing and adjusted for light and dark so all seven read at the same weight. It is the second signal that a run is bold, which a proportional font gives away only faintly in one word. Plain-text notes are untinted: the delimiters say it there.

Constructs nest but never span lines, so a stray `**` can spoil at most its own line — the accepted cost of a parser small enough to hold in your head. A note that genuinely contains `**` keeps it: the save puts a backslash in front of anything that would otherwise read back as formatting nobody applied.

Any note can be switched to plain text from the statistics bar: monospaced, with its Markdown left as literal text and the formatting shortcuts turned off — useful for credentials, keys and anything else where a proportional font gets in the way. Switching is a rendering choice and never edits the note, so it is reversible as often as you like. The mode is stored per note.

Pasting converts the clipboard's formatting to Markdown, keeping bold, italic, strikethrough and links, and dropping everything Heptad has no spelling for. In a plain-text note it pastes the characters alone, since that mode turns the formatting commands off. Nothing can enter a note that its own commands cannot take back out.

`⌘C` gives back the note's own characters — its Markdown, not the styling drawn from it — which is what keeps `⌘C` then `⌘V` inside the app exact. `⌘⇧C` copies the selection as rich text instead, for pasting into Mail or a document, where the delimiters are noise and the formatting is the point. It carries bold, italic, strikethrough and links, in no particular colour and at no particular size: the receiving document has its own.

Emptying a note is `⌘A` then `⌫`, one undo step. There is no shortcut of its own: `⌘⌫` is left to `NSTextView`, where it deletes to the beginning of the line as it does in every other editor.

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
| `⌘Z` / `⌘⇧Z` | Undo / redo |
| `⌘C` / `⌘X` | Copy / cut, as the note's own Markdown |
| `⌘⇧C` | Copy as rich text, for pasting into another app (plain-text notes copy the characters) |
| `⌘V` | Paste, converting the clipboard's formatting to Markdown (plain-text notes take the characters alone) |
| `⌘⇧V` | Paste as raw text, dropping the formatting entirely |
| `⌘A` | Select all |
| `⌘W` / `⌘Q` | Close window / quit |

`⌘B`, `⌘I` and `⌘⇧X` turn the trait on over the selection, or off again, so each is its own inverse and they compose in any order; the delimiters are written when the note is saved. They do nothing in a plain-text note, which leaves its Markdown literal.

`⌘+` and `⌘-` set one zoom level for every note rather than sizing a run of text, since font size is the one thing with no Markdown spelling.

Editing, formatting and clipboard shortcuts require a focused editor; note switching, `⌘P`, `⌘W`, and `⌘Q` do not. `⌃⌥Space` is registered system-wide and works while another app is frontmost — it needs no Accessibility permission.

## License

This project is released under the MIT License.

See [LICENSE](./LICENSE) for the full text.
