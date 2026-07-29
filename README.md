# Heptad

Heptad is a minimal rich-text note-taking app with exactly seven colour-coded notes. It runs as a macOS menu bar popup and as a standalone iOS app from one shared SwiftUI/SwiftData codebase, with no third-party dependencies.

There are always seven notes, never more or fewer. They are created on first launch and never added, deleted, or renamed — a note is identified by its colour and its position. Content is saved continuously, with no save button.

On macOS the app lives in the status bar. Left-clicking the icon opens a floating panel anchored beneath it; the panel dismisses when you click elsewhere. Dragging it away converts it into a regular movable window that stays open. On iOS the same UI runs full-screen with a row of seven coloured circles for switching notes.

## Status

Personal project. No signed or notarized builds, no releases — build it from source.

## Screenshots

Not captured yet.

<!--
TODO: add two screenshots —
  1. macOS: the attached menu bar popup anchored under the status item.
  2. iOS: the seven-circle note switcher.
-->

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

## Design notes

* **One window, reconfigured.** Attaching and detaching mutate a single `NSPanel` rather than swapping between two windows, so the text, cursor, selection, and undo stack survive the transition intact.
* **One `ContentView`, two native editors.** Shared SwiftUI routes to `NSTextView` on macOS and `UITextView` on iOS. The editors are the system text views, unmodified — no rich-text engine was written for this app.
* **Undo is isolated per note.** Each note keeps its own editor view and undo manager, so undo never crosses note boundaries.
* **Shortcuts are handled explicitly on macOS.** The app is an accessory app with no main menu at any point, so a key monitor is the single source of truth for shortcuts.
* **Persistence is continuous.** Edits are debounced and written to SwiftData as RTF, with explicit flushes on backgrounding and termination so nothing is lost on quit.

## Keyboard shortcuts (macOS)

| Shortcut | Action |
| --- | --- |
| `⌘1`–`⌘7` | Select note 1–7 |
| `⌘0` | Select the first empty note |
| `⌘B` / `⌘I` / `⌘⇧X` | Bold / italic / strikethrough |
| `⌘+` / `⌘-` | Increase / decrease font size |
| `⌘Z` / `⌘⇧Z` | Undo / redo |
| `⌘C` / `⌘X` / `⌘V` | Copy / cut / paste |
| `⌘⇧V` | Paste without formatting |
| `⌘A` | Select all |
| `⌘W` / `⌘Q` | Close window / quit |

Formatting and clipboard shortcuts require a focused editor; note switching, `⌘W`, and `⌘Q` do not.

## AI Assistance

This project was developed with AI assistance.

Different coding assistants and model providers were used over time, including tools such as GitHub Copilot, Anthropic Claude models, Google Gemini models, OpenAI ChatGPT models and locally run models through Ollama. The exact mix changed during development.

## License

This project is released under the MIT License.

See [LICENSE](./LICENSE) for the full text.
