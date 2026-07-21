# Heptad

Heptad is a minimal, always-available rich-text note-taking app with exactly **7 color-coded notes**. It targets **macOS** (menubar popup) and **iOS** (standalone app) from a shared SwiftUI/SwiftData codebase.

## Features
- **macOS Menu Bar App**: Lives in the status bar for quick access. Can be dragged away into a detached floating window.
- **iOS Standalone App**: Full-screen iPad/iPhone app with a simple 7-color tab bar.
- **Always 7 Notes**: Enforces a strict limit of exactly 7 identifiable notes.
- **SwiftData Storage**: Automatically saves typing locally without a save button.
- **App Sandbox**: Runs securely within the macOS App Sandbox.

## Architecture
- 100% native SwiftUI without third-party dependencies.
- Shared `ContentView` handling UI layout and OS-specific routing to rich text editor implementations (`UITextView` and `NSTextView`).
- Modular architecture with specific managers (`WindowManager`, `EditorShortcutManager`) and shared utilities (`NoteContentSaver`).

## Building & Compilation
To compile the project from the command line, follow these steps:
1. Ensure [Homebrew](https://brew.sh/) is installed.
2. Install XcodeGen via Homebrew (if not already installed):
   ```bash
   brew install xcodegen
   ```
3. Generate the `Heptad.xcodeproj` file from `project.yml`:
   ```bash
   xcodegen generate
   ```
4. Build the macOS app via `xcodebuild`:
   ```bash
   xcodebuild -scheme Heptad-macOS build
   ```
5. Build the iOS app via `xcodebuild`:
   ```bash
   xcodebuild -scheme Heptad-iOS -destination 'generic/platform=iOS Simulator' build
   ```
   Or open `Heptad.xcodeproj` and build via Xcode.
