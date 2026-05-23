# MDView

A lightweight Markdown viewer for macOS. Opens `.md`, `.markdown`, and `.txt` files in a clean, readable window with no editing — just reading.

![MDView screenshot](screenshot.png)

## Features

- Open files via File > Open, drag-and-drop, or double-click from Finder
- Multiple windows (each file gets its own window)
- Find in document (Cmd+F)
- Print / Save as PDF (Cmd+P) with smart page breaks
- Recently Read file list
- Zoom in/out and content width adjustment
- Font selection: System Sans, System Serif, Georgia, Palatino, Charter
- Dark mode toggle
- Justified text option
- Renders tables, code blocks, headings, links, images, and other standard Markdown

## Install

Requires Swift 5.9+ and macOS 12+.

**Quick install** (builds a universal binary and copies to `/Applications`):

```
./install.sh
```

**Build from source** (debug, current architecture only):

```
swift build
.build/debug/mdview
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+O | Open file |
| Cmd+P | Print / Save as PDF |
| Cmd+F | Find in document |
| Cmd+G | Find next |
| Shift+Cmd+G | Find previous |
| Cmd++ | Zoom in |
| Cmd+- | Zoom out |
| Cmd+0 | Actual size |
| Cmd+] | Wider |
| Cmd+[ | Narrower |
| Cmd+J | Toggle justify |
| Cmd+D | Toggle dark mode |

## Architecture

The app uses a hybrid SwiftUI + AppKit approach:

- **SwiftUI `App` struct** provides the menu bar and keyboard shortcuts
- **AppKit `NSWindow`s** are managed by the `AppDelegate` for document windows
- **`WKWebView`** renders Markdown converted to HTML via Apple's [swift-markdown](https://github.com/apple/swift-markdown) library
- Preferences (font, zoom, width, appearance, alignment) persist via `UserDefaults`

## License

[MIT](LICENSE)
