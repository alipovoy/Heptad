# Heptad

Heptad is a minimal rich-text note-taking app with exactly seven colour-coded notes. It runs as a macOS menu bar popup and as a standalone iOS app from one shared SwiftUI/SwiftData codebase, with no third-party dependencies.

There are always seven notes, never more or fewer. They are created on first launch and never added, deleted, or renamed — a note is identified by its colour and its position. Content is rich text, saved continuously, with no save button and no document model.

On macOS the app lives in the status bar. Left-clicking the icon opens a floating panel anchored beneath it; the panel dismisses when you click elsewhere. Dragging it away converts it into a regular movable window that stays open. On iOS the same UI runs full-screen with a row of seven coloured circles at the top for switching notes.

## Status

Personal project, developed in the open. There are no signed or notarized builds, no releases, and no distribution — build it from source. It is not on the App Store and is not intended for it.

## Screenshots

Not captured yet.

<!--
TODO: add two screenshots —
  1. macOS: the attached menu bar popup anchored under the status item.
  2. iOS: the seven-circle note switcher.
-->

## Requirements

* macOS 14.0 or later (macOS target)
* iOS 17.0 or later (iOS target)
* Xcode with matching SDKs — verified on Xcode 26.5
* [XcodeGen](https://github.com/yonaskolb/XcodeGen) for generating the Xcode project

No package manager step: the app uses only Apple frameworks (SwiftUI, SwiftData, AppKit, UIKit).

## Build

**`project.yml` is the source of truth. `Heptad.xcodeproj` is XcodeGen output, is gitignored, and is not committed — a fresh clone has no Xcode project at all.** Generate it before doing anything else, including before opening the project in Xcode.

### Install XcodeGen

```bash
brew install xcodegen
```

### Generate the project

From the repository root:

```bash
xcodegen generate
```

This creates `Heptad.xcodeproj` locally, with the schemes `Heptad-macOS` and `Heptad-iOS`. Re-run it after any change to `project.yml` or after adding or removing source files.

### Build from the command line

```bash
xcodebuild -project Heptad.xcodeproj -scheme Heptad-macOS build
```

```bash
xcodebuild -project Heptad.xcodeproj -scheme Heptad-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Substitute a simulator you actually have installed. To list them:

```bash
xcrun simctl list devices available
```

### Build in Xcode

Generate the project, open `Heptad.xcodeproj`, select the `Heptad-macOS` or `Heptad-iOS` scheme, and run.

Test targets, workflow, and contribution details are in [CONTRIBUTING.md](./CONTRIBUTING.md).

## Design notes

The decisions worth knowing before reading the source.

### One window, reconfigured — not two windows

`WindowManager` creates a single `NSPanel` on first open and keeps it for the app's lifetime. Attaching and detaching mutate that one panel's style — detaching inserts `.miniaturizable` and clears `isFloatingPanel`; re-attaching restores `.nonactivatingPanel` — rather than closing one window and opening another.

The reason is state. The panel's content is a single lazily-created `NSHostingView` wrapping `ContentView`. Because the view hierarchy is never torn down and rebuilt, the `NSTextView` for the current note survives the transition intact, and with it the text, the insertion point, the selection, and the undo stack. A two-window design would have to serialize and restore all of that, and undo history in particular does not survive a round trip through storage.

Unpinning is deliberately not instantaneous: `windowDidMove` measures the drag distance from the anchor point, and once it exceeds 20 points it installs a one-shot monitor that waits for mouse-up before converting the panel. The window does not change identity underneath a drag in progress.

The app is an accessory app (`LSUIElement`) in both states. It has no Dock icon and no main menu at any point.

### One `ContentView`, two native editors

`ContentView` is shared and owns everything platform-independent: the seven-circle picker, the note-tinted background, the statistics bar, and the save-flush lifecycle hooks. It routes to `MacRichTextEditor` (an `NSViewRepresentable` over `NSTextView`) or `IOSRichTextEditor` (a `UIViewRepresentable` over `UITextView`) behind `#if os(macOS)`.

Both wrap the same base class, `NoteEditorCoordinator`, which holds the logic that is genuinely shared — caching one editor view and one saver per note, swapping the visible one into the container, and routing text changes to persistence and statistics. The platform subclasses supply only view creation, focus handling, and text access. The editors are the system text views, unmodified; no rich-text engine was written for this app.

Statistics (lines, words, characters) are computed in a `Task.detached` so counting does not run inline on the main actor while typing, then delivered back to `MainActor`.

### Per-note undo isolation

Because the coordinator caches one editor view per note rather than reusing a single view and swapping its contents, each note keeps its own live text view — so undo cannot cross note boundaries.

On macOS this is enforced explicitly: `IsolatedUndoTextView` overrides `undoManager` to return a private `UndoManager` instead of the window's shared one. Loading a note's saved content is wrapped in `disableUndoRegistration()` / `enableUndoRegistration()` followed by `removeAllActions()`, so restoring content from disk is not itself an undoable edit.

On iOS the text view uses UIKit's own undo manager, with `removeAllActions()` after loading content. The isolation there is a consequence of the per-note view cache rather than an explicit override.

On ownership: the coordinator holds its container view weakly, owns the per-note editor views and savers, and captures `self` weakly in the detached statistics task, so the cached views do not keep the coordinator alive.

### Explicit keyboard-shortcut handling on macOS

There is no main menu. The macOS target is `LSUIElement` and the SwiftUI `App` provides a `Settings` scene rather than a `WindowGroup`, specifically so no default window and no menu appear at launch. That is a deliberate constraint, not an oversight: a populated `NSApp.mainMenu` would intercept `⌘Z`, `⌘C`, `⌘V`, and `⌘X` through `performKeyEquivalent` before they ever reach `NSTextView`'s key bindings.

So `EditorShortcutManager` installs a local `keyDown` monitor and is the single source of truth for shortcuts. It handles `⌘` combinations without Option or Control, consumes the events it acts on, and passes everything else through — including digits outside the note range, so they are not silently swallowed.

### Continuous persistence

Each note gets its own `NoteContentSaver`. A text change snapshots the attributed string on the main thread and starts a 300 ms debounced task; a further change cancels and replaces it. When the task fires, the snapshot is encoded to RTF and written to SwiftData. Encoding failure keeps the previous data rather than overwriting it with nothing, and an encode that matches what is already stored skips the write entirely.

Debouncing alone would lose the last few hundred milliseconds of typing on quit. `ContentView` therefore posts a `flushPendingSaves` notification when the scene phase becomes `background` or `inactive`, and again on `willTerminate`; every saver observes it and writes its pending snapshot immediately.

RTF is the single storage format — `NoteItem` stores `rtfData` and nothing else, and both editors and the saver go through the same encode/decode helpers. Content that is empty or whitespace-only is stored as empty data, which is what `ColorPickerRow` reads to render an unused note as a grey circle rather than a coloured one.

## Keyboard shortcuts (macOS)

Derived from `EditorShortcutManager`.

| Shortcut | Action |
| --- | --- |
| `⌘1`–`⌘7` | Select note 1–7 |
| `⌘0` | Select the first empty note |
| `⌘B` | Bold |
| `⌘I` | Italic |
| `⌘⇧X` | Strikethrough |
| `⌘+` / `⌘=` | Increase font size |
| `⌘-` | Decrease font size |
| `⌘Z` | Undo |
| `⌘⇧Z` | Redo |
| `⌘C` | Copy |
| `⌘X` | Cut |
| `⌘V` | Paste |
| `⌘⇧V` | Paste without formatting |
| `⌘A` | Select all |
| `⌘W` | Close the window |
| `⌘Q` | Quit |

`⌘Q`, `⌘W`, and the note-switching shortcuts are handled before the monitor looks for a focused editor, so they do not require one. The formatting and clipboard shortcuts act on the text view and are ignored unless it is first responder. `⌘+` is accepted as `⌘⇧=`, since that is what the key produces on a US layout.

## Project notes

The behaviour blueprint is documented in [REQUIREMENTS.md](./REQUIREMENTS.md).

The Xcode project definition lives in [project.yml](./project.yml) — targets, deployment targets, entitlements, and the bundle identifiers `dev.lipovoy.heptad.mac` and `dev.lipovoy.heptad.ios`. The macOS app runs sandboxed with the hardened runtime enabled.

## AI Assistance

This project was developed with AI assistance.

Different coding assistants and model providers were used over time, including tools such as GitHub Copilot, Anthropic Claude models, Google Gemini models, OpenAI ChatGPT models and locally run models through Ollama. The exact mix changed during development.

## License

This project is released under the MIT License.

See [LICENSE](./LICENSE) for the full text.
