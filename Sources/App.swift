import SwiftUI
import AppKit
import WebKit
import Markdown
import UniformTypeIdentifiers

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
    /// Bumped on every (re)load so the web view re-renders even if the HTML is unchanged.
    @Published var contentVersion = 0
    /// Set when images failed to load because the sandbox blocks their folder.
    @Published var folderNeedingAccess: URL?

    weak var window: NSWindow?
    private var accessedURL: URL?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var reloadPending = false

    deinit {
        fileWatcher?.cancel()
        accessedURL?.stopAccessingSecurityScopedResource()
    }

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

    /// Opens `url` in this window, showing an alert if it can't be read.
    @discardableResult
    func open(_ url: URL) -> Bool {
        do {
            try openFile(at: url)
            return true
        } catch {
            Self.presentError(error, opening: url, in: window)
            return false
        }
    }

    static func presentError(_ error: Error, opening url: URL, in window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "\u{201C}\(url.lastPathComponent)\u{201D} couldn\u{2019}t be opened."
        alert.informativeText = (error as NSError).localizedFailureReason ?? error.localizedDescription
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    func openFile(at url: URL) throws {
        // URLs resolved from Recently Read bookmarks are only readable inside
        // the sandbox while access is claimed. Hold it for the window's lifetime.
        let accessing = url.startAccessingSecurityScopedResource()
        let content: String
        do {
            content = try MarkdownFile.read(url)
        } catch {
            if accessing { url.stopAccessingSecurityScopedResource() }
            throw error
        }
        if accessedURL != url {
            accessedURL?.stopAccessingSecurityScopedResource()
            accessedURL = accessing ? url : nil
        } else if accessing {
            url.stopAccessingSecurityScopedResource()
        }

        fileURL = url
        fileName = url.lastPathComponent
        render(content)
        AppState.shared.addToRecentFiles(url)
        window?.title = url.lastPathComponent
        watch(url)
    }

    private func render(_ content: String) {
        let document = Document(parsing: content)
        var converter = HTMLConverter()
        renderedHTML = converter.visit(document)
        folderNeedingAccess = nil
        contentVersion += 1
    }

    /// Re-renders the current file, e.g. after granting access to its images.
    func reload() {
        guard let fileURL, let content = try? MarkdownFile.read(fileURL) else { return }
        render(content)
    }

    // MARK: Live reload

    /// Re-renders when the file changes on disk. Editors often save by
    /// replacing the file, which ends the watch on the old one, so the file
    /// is watched again by path after every change.
    private func watch(_ url: URL) {
        fileWatcher?.cancel()
        fileWatcher = nil
        let descriptor = Darwin.open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.fileDidChange() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        fileWatcher = source
    }

    private func fileDidChange() {
        // Saves often arrive as several events; handle them once the file settles.
        guard !reloadPending else { return }
        reloadPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, let fileURL = self.fileURL else { return }
            self.reloadPending = false
            self.watch(fileURL)
            guard let content = try? MarkdownFile.read(fileURL) else { return }
            let document = Document(parsing: content)
            var converter = HTMLConverter()
            let html = converter.visit(document)
            if html != self.renderedHTML {
                self.render(content)
            }
        }
    }

    /// Called when an image read was denied by the sandbox. Suggests the
    /// smallest folder that covers the document and every blocked image.
    func imageAccessDenied(_ imageURL: URL) {
        guard let fileURL else { return }
        let base = folderNeedingAccess ?? fileURL.deletingLastPathComponent()
        folderNeedingAccess = base.commonAncestor(with: imageURL.deletingLastPathComponent())
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
                        ForEach(appState.recentFiles, id: \.url) { file in
                            Button(file.url.lastPathComponent) {
                                openURL(file.url)
                            }
                        }
                        Divider()
                        Button("Clear Recent Files") {
                            appState.clearRecentFiles()
                        }
                    }
                }
            }
            CommandGroup(replacing: .printItem) {
                Button("Page Setup\u{2026}") {
                    NSPageLayout().runModal()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Print\u{2026}") {
                    appDelegate.printKeyWindow()
                }
                .keyboardShortcut("p")
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
        panel.allowedContentTypes = MarkdownFile.extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            openURL(url)
        }
    }

    private func openURL(_ url: URL) {
        appDelegate.open(url)
    }
}

// MARK: - Shared App State (preferences only)

class AppState: ObservableObject {
    static let shared = AppState()

    private let defaults = UserDefaults.standard

    var commandLineHandled = false
    var defaultWindowHasContent = false
    @Published var pendingOpenURL: URL?

    struct RecentFile {
        let url: URL
        let bookmark: Data
    }

    @Published private(set) var recentFiles: [RecentFile] = []
    /// Bumped when the user grants access to a folder, so windows with
    /// blocked images can reload.
    @Published private(set) var folderAccessVersion = 0
    private var grantedFolders: [RecentFile] = []

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
                URL.resolvingSecurityScopedBookmark(data).map { RecentFile(url: $0.url, bookmark: $0.bookmark) }
            }
        }

        // Folders the user allowed for images stay accessible while the app runs.
        if let bookmarks = d.array(forKey: "grantedFolders") as? [Data] {
            grantedFolders = bookmarks.compactMap { data in
                guard let resolved = URL.resolvingSecurityScopedBookmark(data),
                      resolved.url.startAccessingSecurityScopedResource() else { return nil }
                return RecentFile(url: resolved.url, bookmark: resolved.bookmark)
            }
        }
    }

    func addToRecentFiles(_ url: URL) {
        // Only bookmark the file being opened: the app can't create bookmarks
        // for older entries it isn't currently accessing, so keep theirs as is.
        let existing = recentFiles.first { $0.url.path == url.path }
        recentFiles.removeAll { $0.url.path == url.path }
        if let bookmark = url.securityScopedBookmark() ?? existing?.bookmark {
            recentFiles.insert(RecentFile(url: url, bookmark: bookmark), at: 0)
        }
        if recentFiles.count > 10 {
            recentFiles = Array(recentFiles.prefix(10))
        }
        defaults.set(recentFiles.map(\.bookmark), forKey: "recentFiles")
    }

    func removeFromRecentFiles(_ url: URL) {
        recentFiles.removeAll { $0.url.path == url.path }
        defaults.set(recentFiles.map(\.bookmark), forKey: "recentFiles")
    }

    func clearRecentFiles() {
        recentFiles = []
        defaults.removeObject(forKey: "recentFiles")
    }

    /// Asks the user to pick a folder (pre-selecting `suggested`) so images in
    /// it can be shown, and remembers the choice across launches.
    func requestFolderAccess(suggested: URL, for window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.message = "Choose a folder to let MDView show the images stored in it."
        panel.prompt = "Allow"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = suggested

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.grantFolderAccess(url)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    private func grantFolderAccess(_ url: URL) {
        guard let bookmark = url.securityScopedBookmark() else { return }
        grantedFolders.removeAll { $0.url.path == url.path }
        _ = url.startAccessingSecurityScopedResource()
        grantedFolders.insert(RecentFile(url: url, bookmark: bookmark), at: 0)
        defaults.set(grantedFolders.map(\.bookmark), forKey: "grantedFolders")
        folderAccessVersion += 1
    }

    func zoomIn() { fontSize = min(fontSize + 2, 32) }
    func zoomOut() { fontSize = max(fontSize - 2, 10) }
    func resetZoom() { fontSize = 16 }

    func widenContent() { maxWidth = min(maxWidth + 80, 1400) }
    func narrowContent() { maxWidth = max(maxWidth - 80, 480) }
}

// MARK: - PDF Print View

class PDFPrintView: NSView {
    private let document: CGPDFDocument

    init?(document: CGPDFDocument) {
        guard document.numberOfPages > 0,
              let firstPage = document.page(at: 1) else { return nil }
        self.document = document
        super.init(frame: firstPage.getBoxRect(.mediaBox))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: document.numberOfPages)
        return true
    }

    override func rectForPage(_ pageNum: Int) -> NSRect {
        guard let page = document.page(at: pageNum) else {
            return NSRect(origin: .zero, size: NSPrintInfo.shared.paperSize)
        }
        return page.getBoxRect(.mediaBox)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext,
              let op = NSPrintOperation.current,
              let page = document.page(at: op.currentPage) else { return }
        ctx.drawPDFPage(page)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var openWindows: [NSWindow] = []
    private var windowDocuments: [ObjectIdentifier: DocumentState] = [:]
    private var cascadePoint = NSPoint.zero
    private var printRenderer: PrintRenderer?

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

        // Files opened from Finder arrive before this runs. Otherwise show an
        // empty window to drop a file on, rather than just a menu bar.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.openWindows.isEmpty else { return }
            self.makeWindow(for: DocumentState())
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where MarkdownFile.canOpen(url) {
            open(url)
        }
    }

    /// Opens `url` in an empty window if there is one, otherwise a new window.
    func open(_ url: URL) {
        if let window = openWindows.first(where: { windowDocuments[ObjectIdentifier($0)]?.fileURL == nil }),
           let document = windowDocuments[ObjectIdentifier(window)] {
            if document.open(url) {
                window.makeKeyAndOrderFront(nil)
            }
            return
        }

        let document = DocumentState()
        do {
            try document.openFile(at: url)
        } catch {
            if (error as? CocoaError)?.code == .fileReadNoSuchFile {
                AppState.shared.removeFromRecentFiles(url)
            }
            DocumentState.presentError(error, opening: url, in: nil)
            return
        }
        makeWindow(for: document)
    }

    private func makeWindow(for document: DocumentState) {
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
        window.title = document.fileName ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "MDView")
        document.window = window

        // Reuse the last size the user chose; otherwise a reading-width window
        // most of the screen tall. Later windows cascade from the first.
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let saved = NSSizeFromString(UserDefaults.standard.string(forKey: "windowSize") ?? "")
        let size = saved.width >= 500 && saved.height >= 400 ? saved : NSSize(width: 960, height: visible.height * 0.9)
        window.setContentSize(NSSize(width: min(size.width, visible.width), height: min(size.height, visible.height)))
        if openWindows.isEmpty {
            window.center()
            cascadePoint = .zero
        }
        cascadePoint = window.cascadeTopLeft(from: cascadePoint)

        windowDocuments[ObjectIdentifier(window)] = document
        openWindows.append(window)
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let size = window.contentRect(forFrameRect: window.frame).size
        UserDefaults.standard.set(NSStringFromSize(size), forKey: "windowSize")
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

    func printKeyWindow() {
        if let window = NSApp.keyWindow { print(window) }
    }

    private func print(_ window: NSWindow) {
        guard printRenderer == nil,
              let document = windowDocuments[ObjectIdentifier(window)],
              let html = document.renderedHTML else { return }

        let renderer = PrintRenderer(html: html, fileURL: document.fileURL, paper: NSPrintInfo.shared.paperSize)
        printRenderer = renderer
        renderer.render { [weak self] pdfData in
            self?.printRenderer = nil
            guard let pdfData,
                  let provider = CGDataProvider(data: pdfData as CFData),
                  let pdf = CGPDFDocument(provider),
                  let printView = PDFPrintView(document: pdf) else { return }

            let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
            printInfo.topMargin = 0
            printInfo.bottomMargin = 0
            printInfo.leftMargin = 0
            printInfo.rightMargin = 0
            printInfo.horizontalPagination = .clip
            printInfo.verticalPagination = .clip
            let op = NSPrintOperation(view: printView, printInfo: printInfo)
            op.showsPrintPanel = true
            op.showsProgressPanel = true
            op.run()
        }
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
        // Clicking the Dock icon with no windows open shows an empty one;
        // with only minimized windows, AppKit restores one as usual.
        if openWindows.isEmpty {
            makeWindow(for: DocumentState())
            return false
        }
        return true
    }
}
