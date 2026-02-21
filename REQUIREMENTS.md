# 7Notes — Requirements

## Overview
7Notes is a minimal, always-available rich-text note-taking app with exactly **7 color-coded notes**. It targets **macOS** (menubar popup) and **iOS** (standalone app) from a shared SwiftUI/SwiftData codebase.

## Product Requirements

### macOS Behavior
- **Menubar App**: Lives in the status bar (icon: `square.and.pencil`).
- **Toggle**: Left-clicking the icon toggles a floating window. Right-clicking shows a Quit menu.
- **Pinned Mode (Default)**:
  - Opens as a floating panel anchored below the status bar icon.
  - Behaves as a non-activating utility window (no Dock icon, no main menu).
  - Auto-dismisses when clicking outside the panel.
- **Unpinned Mode**:
  - Dragging the panel away from its anchor point converts it into a regular, movable window.
  - Behaves as a standard macOS window (Dock icon and main menu become visible).
  - Remains open when clicking outside.
- **App Lifecycle**: The app should never show a default main window at launch. The custom window lifecycle is entirely managed by the app delegate.

### iOS Behavior
- Runs as a standard full-screen app.
- Features a horizontal row of 7 colored circles at the top, acting as a tab bar to switch between notes.

### Core Features
- **Data Model**: Exactly 7 notes are maintained at all times.
- **Properties**: Each note has a unique identifier (0–6), a fixed color, and rich-text content.
- **Persistence**: Notes are persisted continuously using SwiftData.
- **Editor**: Platform-specific rich-text editor (`NSTextView` on macOS, `UITextView` on iOS). Re-renders instantly when switching notes.
- **Colors**: Fixed order: Red, Orange, Yellow, Green, Cyan, Blue, Purple. The selected note's color (at 15% opacity) is used as the editor's background.
- **Toolbar**:
  - Center: Row of 7 colored circles. The selected circle scales up slightly with a ring overlay.
  - Leading (macOS only): A custom close button to dismiss the window.

### macOS Text Formatting & Hotkeys
Since the app can run without a standard menu bar (in Pinned Mode), it must explicitly support common text editing shortcuts:
- **Clipboard**: ⌘C (Copy), ⌘V (Paste), ⌘X (Cut), ⌘A (Select All).
- **History**: ⌘Z (Undo), ⌘⇧Z (Redo).
- **Formatting**: ⌘B (Bold), ⌘I (Italic), ⌘+ (Increase Font Size), ⌘− (Decrease Font Size).
- **System**: ⌘Q (Quit).

## Technical Constraints
- **Data Sync**: The rich-text data must sync flawlessly between the pinned panel, unpinned window, and storage without data loss or UI state glitches when transitioning window modes.
- **No Third-Party Dependencies**: The app must be built entirely using native Apple frameworks (SwiftUI, SwiftData, AppKit, UIKit).
