<p align="center">
  <img src="Resources/AppIcon.png" width="96" alt="Tray icon">
</p>

<h1 align="center">Tray</h1>

<p align="center">Clipboard history in your menu bar. Free, open source, and lightweight.</p>

---

Press **⌘⇧V** anywhere to open your clipboard history at the cursor, pick an item, and it's pasted into the app you were in.

## Features

- **Instant history** of text, links, images, colors, files, and tables
- **Paste anywhere** with ⌘⇧V, arrow keys, and Return
- **Previews** of images, long text, and colors after hovering a row
- **Pin** items to keep them at the top and safe from "Clear all"
- **Hide** sensitive items behind a name of your choice
- **Private by default**: skips passwords and other content apps mark as concealed or temporary
- **Choose how much to keep**: 50, 100, or 200 items
- Stays out of the way: no Dock icon, no window, ~1MB app

## Install

1. Download `Tray.zip` from [Releases](../../releases) and unzip it.
2. Move `Tray.app` to `/Applications` and open it.
3. Grant **Accessibility** access when asked (System Settings → Privacy & Security → Accessibility). Tray needs it to paste into other apps.

Requires macOS 14 or later.

## Keyboard

| Key | Action |
| --- | --- |
| ⌘⇧V | Open Tray |
| ↑ ↓ | Move selection |
| Return | Paste |
| → or ⌘O | Actions (pin, hide, delete) |
| ⌘P | Pin / unpin |
| ⌘H | Hide / unhide |
| ⌫ | Delete |
| Tab | Jump between pinned and recent |
| Esc | Close |

## Build from source

```bash
swift build                    # debug build
swift test                     # run tests
./Scripts/build-app.sh         # release Tray.app in build/
./Scripts/release.sh           # build/Tray.zip for a GitHub release
./Scripts/preview-watch.sh     # live UI preview: rebuilds and reopens on every save
```

## Privacy

Your history stays on your Mac, in `~/Library/Application Support/Tray`. Tray makes no network requests.

## License

[MIT](LICENSE)
