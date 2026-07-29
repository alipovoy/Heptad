# Contributing to Heptad

Thanks for your interest in improving Heptad! This guide covers how to build the
apps, run the tests, and submit changes.

By participating in this project you agree to abide by our
[Code of Conduct](./CODE_OF_CONDUCT.md).

## Prerequisites

* macOS 14.0 or later for the macOS app; iOS 17.0 or later for the iOS app
* Xcode with matching macOS 14 and iOS 17 SDKs (verified against Xcode 26.5)
* [XcodeGen](https://github.com/yonaskolb/XcodeGen) for generating the Xcode project
* [SwiftLint](https://github.com/realm/SwiftLint) for linting

Install both with Homebrew:

```bash
brew install xcodegen swiftlint
```

## Project layout

* `Sources/Shared/` — code shared by both apps (SwiftUI views, SwiftData model)
* `Sources/macOS/` — macOS-only code (menu bar, window management, entitlements)
* `Sources/iOS/` — iOS-only code
* `Tests/Shared/` — tests compiled into both test targets
* `Tests/macOS/` — macOS-only tests
* `project.yml` — XcodeGen project definition
* `REQUIREMENTS.md` — behavior blueprint for the app as it exists today

There is no `Tests/iOS/`; the `Heptad-iOSTests` target compiles `Tests/Shared` only.

### `project.yml` is the source of truth

`Heptad.xcodeproj` is **generated** by XcodeGen. It is gitignored, never committed,
and must never be edited by hand — any change made in Xcode's project editor is lost
on the next generate. Make project changes in `project.yml` and regenerate:

```bash
xcodegen generate
```

The per-app `Info.plist` files are likewise generated from `project.yml` and are not
committed.

## Building

```bash
xcodegen generate
xcodebuild -project Heptad.xcodeproj -scheme Heptad-macOS build
xcodebuild -project Heptad.xcodeproj -scheme Heptad-iOS -destination 'generic/platform=iOS Simulator' build
```

You can also open `Heptad.xcodeproj` in Xcode, pick the `Heptad-macOS` or
`Heptad-iOS` scheme, and build and run from there.

## Running tests

```bash
xcodegen generate
xcodebuild -project Heptad.xcodeproj -scheme Heptad-macOS test
xcodebuild -project Heptad.xcodeproj -scheme Heptad-iOS -destination 'platform=iOS Simulator,name=iPhone 17' test
```

`generic/platform=iOS Simulator` is fine for `build`, but `test` needs a concrete
simulator. Substitute one you actually have installed — `iPhone 17` will not exist on
every machine. List yours with:

```bash
xcrun simctl list devices available
```

Please make sure both schemes' tests pass locally before opening a pull request.

## Linting

The project is linted with [SwiftLint](https://github.com/realm/SwiftLint). No shared
configuration is committed yet, so it currently runs with its default rules from the
repository root:

```bash
swiftlint lint
```

Many violations can be fixed automatically with `swiftlint --fix`.

The existing sources do not yet lint clean, so treat the current output as a baseline:
avoid adding new violations rather than expecting a clean run.

## Commit messages

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):
a `type(optional scope): summary` subject, where type is one of `feat`, `fix`, `docs`,
`refactor`, `test`, `chore`, `build`, or `ci`. For example:

```
feat(macos): detach the popover into a floating window
fix: avoid crash when the current event is nil
```

Keep the subject in the imperative mood and under about 72 characters. This convention
will be enforced by CI once the commit-message check lands, so please follow it now.

## Coding guidelines

* Targets are macOS 14.0+ and iOS 17.0+ — do not use APIs newer than that without
  an availability guard.
* Native SwiftUI and SwiftData only. The project has no third-party dependencies and
  intentionally adds none.
* Keep platform-specific code in `Sources/macOS` or `Sources/iOS`, and put anything
  both apps need in `Sources/Shared`.
* Write unit tests for core application logic; only add UI tests when unit tests are
  not possible.

## Pull request workflow

1. Fork the repository and create a topic branch from `main`
   (e.g. `feature/short-description` or `fix/short-description`).
2. Make your change, keeping commits focused and Conventional-Commit formatted.
3. Add or update tests covering your change.
4. Run the build and tests for both schemes and confirm they pass, and check that
   SwiftLint reports no new violations in the code you touched.
5. Open a pull request against `main` describing **what** changed and **why**.
   Link any related issue (e.g. `Closes #123`).

For larger or architectural changes, please open an issue first to discuss the
approach before investing significant work.

## Reporting bugs and requesting features

Use the [GitHub issue tracker](https://github.com/alipovoy/Heptad/issues). For bug
reports, include the platform and OS version, steps to reproduce, what you expected,
and what actually happened. Security issues should **not** be filed as public
issues — see [SECURITY.md](./SECURITY.md).
