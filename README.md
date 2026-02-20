# 7Notes

7Notes is a minimal, always-available rich-text note-taking app with exactly **7 color-coded notes**. It targets **macOS** (menubar popup) and **iOS** (standalone app) from a shared SwiftUI/SwiftData codebase.

## Features
- **macOS Menu Bar App**: Lives in the status bar for quick access.
- **iOS Standalone App**: Full-screen iPad/iPhone app with a simple 7-color tab bar.
- **Always 7 Notes**: Enforces a strict limit of exactly 7 identifiable notes.
- **SwiftData Storage**: Automatically saves typing locally without a save button.

## Architecture
- 100% native SwiftUI without third-party dependencies.
- Shared logic with platform-specific rich text editor implementations (`UITextView` and `NSTextView`).
