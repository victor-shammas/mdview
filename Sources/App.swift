import SwiftUI
import AppKit
import Markdown
import UniformTypeIdentifiers

enum ViewFont: String, CaseIterable, Equatable {
    case system = "System Sans"
    case serif = "System Serif"
    case georgia = "Georgia"
    case palatino = "Palatino"
    case charter = "Charter"

    var css: String {
        switch self {
        case .system:  return "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif"
        case .serif:   return "ui-serif, 'New York', Georgia, serif"
        case .georgia: return "Georgia, 'Times New Roman', serif"
        case .palatino: return "Palatino, 'Palatino Linotype', 'Book Antiqua', serif"
        case .charter: return "Charter, 'Bitstream Charter', Georgia, serif"
        }
    }
}

enum Appearance: String, Equatable {
    case auto, light, dark
}

enum TextAlignment: String, Equatable {
    case left, justify

    var css: String {
        switch self {
        case .left:    return "left"
        case .justify: return "justify"
        }
    }
}

// MARK: - Focused Value

struct DocumentStateKey: FocusedValueKey {
    typealias Value = DocumentState
}

extension FocusedValues {
    var documentState: DocumentState? {
        get { self[DocumentStateKey.self] }
        set { self[DocumentStateKey.self] = newValue }
    }
}

// MARK: - Per-Window Document State

class DocumentState: ObservableObject {
    @Published var fileURL: URL?
    @Published var renderedHTML: String?
    @Published var fileName: String?
    @Published var isFindBarVisible = false
    @Published var findQuery = ""
    @Published var findMatchCount = 0
    @Published var findCurrentMatch = 0
    @Published var findBarFocusTrigger = 0

    func showFindBar() {
        isFindBarVisible = true
        findBarFocusTrigger += 1
    }

    func hideFindBar() {
        isFindBarVisible = false
        findQuery = ""
        findMatchCount = 0
        findCurrentMatch = 0
    }

    func findNext() {
        guard findMatchCount > 0 else { return }
        findCurrentMatch = (findCurrentMatch + 1) % findMatchCount
    }

    func findPrevious() {
        guard findMatchCount > 0 else { return }
        findCurrentMatch = (findCurrentMatch - 1 + findMatchCount) % findMatchCount
    }

    func openFile(at url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let document = Document(parsing: content)
        var converter = HTMLConverter()
        let html = converter.visit(document)

        fileURL = url
        fileName = url.lastPathComponent
        renderedHTML = html
        AppState.shared.addToRecentFiles(url)

        DispatchQueue.main.async {
            NSApp.keyWindow?.title = url.lastPathComponent
        }
    }
}

// MARK: - App

@main
struct MDViewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open\u{2026}") {
                    openViaPanel()
                }
                .keyboardShortcut("o")

                Menu("Recently Read") {
                    if appState.recentFiles.isEmpty {
                        Text("No Recent Files")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.recentFiles, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                openURL(url)
                            }
                        }
                        Divider()
                        Button("Clear Recent Files") {
                            appState.clearRecentFiles()
                        }
                    }
                }
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find\u{2026}") {
                    appDelegate.findInKeyWindow()
                }
                .keyboardShortcut("f")

                Button("Find Next") {
                    appDelegate.findNextInKeyWindow()
                }
                .keyboardShortcut("g")

                Button("Find Previous") {
                    appDelegate.findPreviousInKeyWindow()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }
            CommandMenu("View") {
                Button("Zoom In") { appState.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") { appState.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") { appState.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("Wider") { appState.widenContent() }
                    .keyboardShortcut("]", modifiers: .command)

                Button("Narrower") { appState.narrowContent() }
                    .keyboardShortcut("[", modifiers: .command)

                Divider()

                Picker("Font", selection: $appState.selectedFont) {
                    ForEach(ViewFont.allCases, id: \.self) { font in
                        Text(font.rawValue).tag(font)
                    }
                }

                Divider()

                Toggle("Justify Text", isOn: Binding(
                    get: { appState.textAlignment == .justify },
                    set: { appState.textAlignment = $0 ? .justify : .left }
                ))
                .keyboardShortcut("j", modifiers: .command)

                Toggle("Dark Mode", isOn: Binding(
                    get: { appState.appearance == .dark },
                    set: { appState.appearance = $0 ? .dark : .auto }
                ))
                .keyboardShortcut("d", modifiers: .command)
            }
        }
    }

    private func openViaPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            UTType(filenameExtension: "txt"),
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            openURL(url)
        }
    }

    private func openURL(_ url: URL) {
        appDelegate.openInNewWindow(url)
    }
}

// MARK: - Shared App State (preferences only)

class AppState: ObservableObject {
    static let shared = AppState()

    private let defaults = UserDefaults.standard

    var commandLineHandled = false
    var defaultWindowHasContent = false
    @Published var pendingOpenURL: URL?

    @Published var recentFiles: [URL] = []

    @Published var fontSize: CGFloat {
        didSet { defaults.set(fontSize, forKey: "fontSize") }
    }
    @Published var maxWidth: CGFloat {
        didSet { defaults.set(maxWidth, forKey: "maxWidth") }
    }
    @Published var selectedFont: ViewFont {
        didSet { defaults.set(selectedFont.rawValue, forKey: "selectedFont") }
    }
    @Published var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: "appearance") }
    }
    @Published var textAlignment: TextAlignment {
        didSet { defaults.set(textAlignment.rawValue, forKey: "textAlignment") }
    }

    private init() {
        let d = UserDefaults.standard
        let fs = d.double(forKey: "fontSize")
        fontSize = fs >= 10 && fs <= 32 ? fs : 16

        let mw = d.double(forKey: "maxWidth")
        maxWidth = mw >= 480 && mw <= 1400 ? mw : 800

        if let fontName = d.string(forKey: "selectedFont"),
           let font = ViewFont(rawValue: fontName) {
            selectedFont = font
        } else {
            selectedFont = .system
        }

        if let appName = d.string(forKey: "appearance"),
           let app = Appearance(rawValue: appName) {
            appearance = app
        } else {
            appearance = .auto
        }

        if let alignName = d.string(forKey: "textAlignment"),
           let align = TextAlignment(rawValue: alignName) {
            textAlignment = align
        } else {
            textAlignment = .left
        }

        if let bookmarks = d.array(forKey: "recentFiles") as? [Data] {
            recentFiles = bookmarks.compactMap { data in
                var stale = false
                return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale)
            }
        }
    }

    func addToRecentFiles(_ url: URL) {
        recentFiles.removeAll { $0.path == url.path }
        recentFiles.insert(url, at: 0)
        if recentFiles.count > 10 {
            recentFiles = Array(recentFiles.prefix(10))
        }
        let bookmarks = recentFiles.compactMap { try? $0.bookmarkData(options: .withSecurityScope) }
        defaults.set(bookmarks, forKey: "recentFiles")
    }

    func clearRecentFiles() {
        recentFiles = []
        defaults.removeObject(forKey: "recentFiles")
    }

    func zoomIn() { fontSize = min(fontSize + 2, 32) }
    func zoomOut() { fontSize = max(fontSize - 2, 10) }
    func resetZoom() { fontSize = 16 }

    func widenContent() { maxWidth = min(maxWidth + 80, 1400) }
    func narrowContent() { maxWidth = max(maxWidth - 80, 480) }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var openWindows: [NSWindow] = []
    private var windowDocuments: [ObjectIdentifier: DocumentState] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53,
               let doc = self?.documentForKeyWindow(),
               doc.isFindBarVisible {
                doc.hideFindBar()
                return nil
            }
            return event
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Filter valid files
        let validURLs = urls.filter {
            let ext = $0.pathExtension.lowercased()
            return ["md", "markdown", "mdown", "mkd", "txt"].contains(ext)
        }
    
        // Just open everything as a new window immediately
        for url in validURLs {
            openInNewWindow(url)
        }
    }

    func openInNewWindow(_ url: URL) {
        let document = DocumentState()
        document.openFile(at: url)

        let rootView = ContentView()
            .environmentObject(AppState.shared)
            .environmentObject(document)
            .focusedSceneValue(\.documentState, document)
            .frame(minWidth: 500, minHeight: 400)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: rootView)
        window.title = url.lastPathComponent

        window.setFrame(NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700), display: true)

        windowDocuments[ObjectIdentifier(window)] = document
        openWindows.append(window)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            openWindows.removeAll { $0 === window }
            windowDocuments.removeValue(forKey: ObjectIdentifier(window))
        }
    }

    func documentForKeyWindow() -> DocumentState? {
        guard let window = NSApp.keyWindow else { return nil }
        return windowDocuments[ObjectIdentifier(window)]
    }

    func findInKeyWindow() {
        documentForKeyWindow()?.showFindBar()
    }

    func findNextInKeyWindow() {
        documentForKeyWindow()?.findNext()
    }

    func findPreviousInKeyWindow() {
        documentForKeyWindow()?.findPrevious()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }
}
