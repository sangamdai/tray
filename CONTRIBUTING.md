# Contributing to Tray

Thanks for helping. Tray aims to stay small, fast, and dependable, so contributions are welcome when they keep it that way.

## What's welcome

- **Bug fixes**, especially crashes, paste failures, or wrong clipboard types
- **Performance** improvements with before/after numbers
- **Accessibility** and keyboard improvements
- **Small polish** that fits the existing look

For **new features** or bigger changes, open an issue first so we can agree on the approach before you write code. Tray deliberately stays focused, so some ideas won't make it in. That's not a judgment on the idea.

## Ground rules

- **No third-party dependencies.** Tray uses only Apple frameworks.
- **No network requests.** History never leaves the Mac.
- **Match the existing style.** Colors, sizes, and timings live in `Sources/Theme/TrayTheme.swift`, and icons are [Lucide](https://lucide.dev) (`Sources/Theme/LucideIcons.swift`).
- **Keep it efficient.** Tray runs all day: avoid timers, polling, or work on the main thread that isn't needed.

## Getting started

```bash
swift build                    # build
swift test                     # run tests (must pass)
./Scripts/preview-watch.sh     # live UI preview with sample data; reloads on save
./Scripts/build-app.sh         # build Tray.app into build/
```

Requires macOS 14+ and Xcode 16+.

## Pull requests

- One change per pull request, with a short description of what and why.
- Include screenshots or a short recording for anything visual.
- Add or update tests for storage and clipboard logic.
- CI builds and tests every pull request; it needs to pass before merging.
