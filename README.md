# Plainview

A Markdown reader for macOS, not an editor. Plainview opens `.md`, `.markdown` and `.txt` files in a clean, readable window, and that's all it does: no editing, no sidebar, no accounts.

Plainview is coming to the Mac App Store. The source is here under the MIT license, so you can also build it yourself. (Until version 1.2 it was called MDView.)

![Plainview screenshot](screenshot.png)

## Features

- Open files with File > Open, by dragging them onto the window or Dock icon, or by double-clicking them in Finder
- Quick Look: select a Markdown file in Finder and press Space to see it rendered
- Live reload: the document updates when the file changes on disk
- Follows your Mac's light or dark appearance, or switch to dark with Cmd+D
- Five typefaces (System Sans, System Serif, Georgia, Palatino and Charter), zoom, adjustable line width and justified text
- Find in document (Cmd+F)
- Print or Save as PDF (Cmd+P) on the paper size from Page Setup, with page breaks between lines
- File > Export as PDF, keeping links to websites, email addresses and headings clickable
- Links to headings (`[Setup](#setup)`) work, using GitHub's anchor names
- Recently Read list, and a separate window for each file
- Renders headings, tables, code blocks, checklists, quotes, links, images and the rest of standard Markdown

Images stored next to a document are shown after you allow access to their folder once.

## Privacy

Plainview collects no data and has no analytics. Your settings and Recently Read list stay on your Mac. The only time it uses the network is to load images that a document links to on the web.

## Install

Plainview runs on macOS 14 or later. Building it needs Xcode, or Swift 5.9 or later.

**Xcode** (the full app, including the Quick Look extension): open `Plainview.xcodeproj` and run the Plainview scheme.

**Quick install** (builds a universal binary with Swift Package Manager and copies it to `/Applications`, without the Quick Look extension):

```
./install.sh
```

Pass a folder to install somewhere else, e.g. `./install.sh ~/Applications`.

**Build from source** (debug, current architecture only):

```
swift build
.build/debug/plainview
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+O | Open file |
| Cmd+P | Print / Save as PDF |
| Shift+Cmd+P | Page Setup |
| Cmd+F | Find in document |
| Cmd+G | Find next |
| Shift+Cmd+G | Find previous |
| Cmd++ | Zoom in |
| Cmd+- | Zoom out |
| Cmd+0 | Actual size |
| Cmd+] | Wider |
| Cmd+[ | Narrower |
| Cmd+J | Toggle justified text |
| Cmd+D | Toggle dark mode |

## Architecture

The app uses a hybrid SwiftUI + AppKit approach:

- **SwiftUI `App` struct** provides the menu bar and keyboard shortcuts
- **AppKit `NSWindow`s** are managed by the `AppDelegate` for document windows
- **`WKWebView`** renders Markdown converted to HTML via Apple's [swift-markdown](https://github.com/apple/swift-markdown) library
- Preferences (font, zoom, width, appearance, alignment) persist via `UserDefaults`
- `Sources/Shared` (Markdown conversion and the page template) is shared with the **Quick Look extension** in `QuickLook/`
- The app is sandboxed. Images next to a document load through a custom URL scheme, after a one-time permission per folder. The page itself allows no scripts (Content Security Policy), since documents can contain raw HTML
- App identity and version live in `Support/Plainview.xcconfig`, shared by the Xcode project and `install.sh`
- The app icon is drawn by `make_icon.swift` (run `swift make_icon.swift` from the repo root), which writes `AppIcon.icns` and the Xcode asset catalog

## License

[MIT](LICENSE). The icon's lettering uses [Figtree](https://github.com/erikdkennedy/figtree), included in `IconSource/` under the [SIL Open Font License](IconSource/OFL.txt). The font is only used to draw the icon and isn't part of the app.
