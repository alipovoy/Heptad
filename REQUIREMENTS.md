# 7Notes — Requirements

## Overview
7Notes is a minimal, always-available rich-text note-taking app with exactly **7 color-coded notes**. It targets **macOS** (menubar popup) and **iOS** (standalone app) from a shared SwiftUI/SwiftData codebase.

## Product Requirements

### macOS Behavior
- **Menubar App**: Lives in the status bar (icon: `square.and.pencil`).
- **Toggle**: Left-clicking the icon toggles a floating window. Right-clicking shows a Quit menu.
- **Single Window Architecture**: Uses a dynamically reconfigurable single window (`NSPanel`) transitioning between two states:
  - **Attached State**: Opens anchored below the status bar icon. Behaves as a non-activating panel (no Dock icon, no main menu). Auto-dismisses when clicking outside.
  - **Detached State**: Dragging the window away converts it into a regular, movable window. Dock icon and main menu become visible. Remains open when clicking outside. Custom size is saved and restored.
- **App Lifecycle**: The app should never show a default main window at launch. The custom window lifecycle is entirely managed by a dedicated `WindowManager`.

### iOS Behavior
- Runs as a standard full-screen app.
- Features a horizontal row of 7 colored circles at the top, acting as a tab bar to switch between notes.

### Core Features
- **Data Model**: Exactly 7 notes are maintained at all times.
- **Properties**: Each note has a unique identifier (0–6), a fixed color, and rich-text content.
- **Persistence**: Notes are persisted continuously using SwiftData and a centralized `NoteContentSaver`.
- **Editor**: Platform-specific rich-text editor (`NSTextView` on macOS, `UITextView` on iOS). Re-renders instantly when switching notes, and focuses automatically for immediate typing. Undo history is isolated per note.
- **Colors**: Fixed order: Red, Orange, Yellow, Green, Cyan, Blue, Purple. The selected note's color (at 15% opacity) is used as the editor's background. Color circles include gradients and empty states.
- **Toolbar**:
  - Center: Row of 7 colored circles. The selected circle scales up slightly with a ring overlay.
  - Leading (macOS only): A custom close button to dismiss the window.

### macOS Text Formatting & Hotkeys
Since the app can run without a standard menu bar (in Attached State), it must explicitly support common text editing shortcuts:
- **Clipboard**: ⌘C (Copy), ⌘V (Paste), ⌘X (Cut), ⌘A (Select All).
- **History**: ⌘Z (Undo), ⌘⇧Z (Redo).
- **Formatting**: ⌘B (Bold), ⌘I (Italic), ⌘+ (Increase Font Size), ⌘− (Decrease Font Size).
- **System**: ⌘Q (Quit).

## Technical Constraints
- **Window State Transitions**: The single window must smoothly transition between attached and detached states, preserving editor state, cursor position, and undo history seamlessly.
- **No Third-Party Dependencies**: The app must be built entirely using native Apple frameworks (SwiftUI, SwiftData, AppKit, UIKit).
- **Security**: The application is configured to run fully sandboxed on macOS.
