# 7Notes — Requirements

## Overview
7Notes is a minimal, always-available rich-text note-taking app with exactly **7 color-coded notes**. It targets **macOS** (menubar popup) and **iOS** (standalone app) from a shared SwiftUI/SwiftData codebase.

---

## Platform Behaviour

### macOS
- Lives in the **menubar** (status bar icon: `note.text`).
- Clicking the icon shows a compact **floating panel** (non-activating, utility window) positioned below the icon.
- The panel must **never show up as a main window** at launch. `AppDelegate` owns all macOS window lifecycle.
- Right-clicking the icon shows a menu with **Quit**.
- The panel can be dismissed by clicking the custom close button (toolbar) or clicking the icon again.
- `SevenNotesApp.body` must return `Settings { EmptyView() }` on macOS (not a `WindowGroup`) so SwiftUI does not auto-create a main window.

### iOS
- Runs as a normal **full-screen app**.
- A horizontal row of 7 color circles at the top acts as the tab bar.

---

## Note Model (`NoteItem`)
- Exactly **7 notes** are maintained at all times (enforced in `ContentView.initializeIfNeeded()`).
- Each note has: `id: Int` (0–6, unique), `colorHex: String` (kept in schema for backwards compatibility, but no longer used for color logic), `rtfData: Data`.
- Persisted via **SwiftData** (`ModelContainer` shared between `AppDelegate` and the scene).

---

## Colors (fixed, in order)

Uses natively adapting SwiftUI colors.
| Index | SwiftUI Color |
|-------|---------------|
| 0     | `.red`        |
| 1     | `.orange`     |
| 2     | `.yellow`     |
| 3     | `.green`      |
| 4     | `.cyan`       |
| 5     | `.blue`       |
| 6     | `.purple`     |

The selected note's color with `.opacity(0.15)` is used as the **background** of the editor area.

---

## UI

### Toolbar (macOS, `.toolbar`)
- **Leading**: custom close button (`xmark.circle.fill`) that hides the panel (`orderOut`).
- **Principal (center)**: row of 7 colored circles (16 pt); selected circle scales to 1.15× with a ring overlay.

### Editor
- Platform-specific rich-text editor (`NSTextView` on macOS, `UITextView` on iOS).
- Font size 18 pt, transparent background, 8 pt text container inset on all sides.
- Content saved as **RTF data** on every text change.
- View is recreated via `.id(note.id)` when the selected note changes (no `updateNSView`/`updateUIView` logic needed).

---

## Architecture Notes
- `SevenNotesApp` uses `@NSApplicationDelegateAdaptor(AppDelegate.self)` on macOS.
- `AppDelegate` creates the panel lazily on first toggle; subsequent toggles show/hide it.
- The panel's `delegate` is `AppDelegate` so `windowShouldClose` can intercept close and hide instead of destroy.
- The tab bar color picker is centralized in `ContentView.swift` as `colorPickerRow` to serve both iOS and macOS natively without code duplication.
- No third-party dependencies.
