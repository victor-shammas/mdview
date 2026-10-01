import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let contentVersion: Int
    let fileURL: URL?
    let fontSize: CGFloat
    let maxWidth: CGFloat
    let fontFamily: String
    let appearance: Appearance
    let textAlignment: TextAlignment
    let findQuery: String
    let findMatchIndex: Int
    var onFindResults: ((Int) -> Void)?
    var onImageAccessDenied: ((URL) -> Void)?

    /// Local paths resolve through `LocalFileSchemeHandler` rather than file://,
    /// so images keep working under the App Sandbox.
    private var pageBaseURL: URL? {
        fileURL.flatMap { LocalFileSchemeHandler.pageURL(for: $0.deletingLastPathComponent()) }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(context.coordinator.fileHandler, forURLScheme: LocalFileSchemeHandler.scheme)
        config.userContentController.addUserScript(
            WKUserScript(source: Self.findScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.onFindResults = onFindResults
        context.coordinator.fileHandler.onAccessDenied = onImageAccessDenied
        context.coordinator.snapshot = Snapshot(fileURL: fileURL, html: html, contentVersion: contentVersion, fontSize: fontSize, maxWidth: maxWidth, fontFamily: fontFamily, appearance: appearance, textAlignment: textAlignment, findQuery: findQuery, findMatchIndex: findMatchIndex)
        context.coordinator.load(buildPage(), baseURL: pageBaseURL, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let prev = context.coordinator.snapshot!
        let cur = Snapshot(fileURL: fileURL, html: html, contentVersion: contentVersion, fontSize: fontSize, maxWidth: maxWidth, fontFamily: fontFamily, appearance: appearance, textAlignment: textAlignment, findQuery: findQuery, findMatchIndex: findMatchIndex)
        context.coordinator.snapshot = cur
        context.coordinator.onFindResults = onFindResults
        context.coordinator.fileHandler.onAccessDenied = onImageAccessDenied

        if prev.html != cur.html || prev.contentVersion != cur.contentVersion {
            if !cur.findQuery.isEmpty {
                context.coordinator.pendingFindQuery = cur.findQuery
                context.coordinator.pendingFindIndex = cur.findMatchIndex
            }
            let page = buildPage()
            let baseURL = pageBaseURL
            let coordinator = context.coordinator
            guard prev.fileURL == cur.fileURL, coordinator.isLoaded else {
                coordinator.isLoaded = false
                coordinator.load(page, baseURL: baseURL, in: webView)
                return
            }
            // Same file re-rendered (edited on disk, or images allowed): keep
            // the reader's place.
            coordinator.isLoaded = false
            webView.evaluateJavaScript("window.scrollY") { result, _ in
                coordinator.pendingScrollY = result as? Double
                coordinator.load(page, baseURL: baseURL, in: webView)
            }
            return
        }

        var js = ""
        if prev.fontSize != cur.fontSize {
            js += "document.documentElement.style.setProperty('--base-font-size','\(cur.fontSize)px');"
        }
        if prev.maxWidth != cur.maxWidth {
            js += "document.documentElement.style.setProperty('--max-width','\(Int(cur.maxWidth))px');"
        }
        if prev.fontFamily != cur.fontFamily {
            js += "document.documentElement.style.setProperty('--font-family',\"\(cur.fontFamily)\");"
        }
        if prev.textAlignment != cur.textAlignment {
            js += "document.documentElement.style.setProperty('--text-align','\(cur.textAlignment.css)');"
        }
        if prev.appearance != cur.appearance {
            switch cur.appearance {
            case .auto:  js += "document.documentElement.removeAttribute('data-theme');"
            case .light: js += "document.documentElement.setAttribute('data-theme','light');"
            case .dark:  js += "document.documentElement.setAttribute('data-theme','dark');"
            }
        }
        if !js.isEmpty {
            webView.evaluateJavaScript(js)
        }

        if prev.findQuery != cur.findQuery {
            if cur.findQuery.isEmpty {
                context.coordinator.pendingFindQuery = nil
                if context.coordinator.isLoaded {
                    webView.evaluateJavaScript("clearFind()")
                }
                DispatchQueue.main.async {
                    context.coordinator.onFindResults?(0)
                }
            } else if !context.coordinator.isLoaded {
                // Page is still loading (e.g. a large file). Defer the search
                // until didFinish so it doesn't run against an empty/partial DOM
                // and silently report "No matches".
                context.coordinator.pendingFindQuery = cur.findQuery
                context.coordinator.pendingFindIndex = cur.findMatchIndex
            } else {
                let escaped = cur.findQuery
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "'", with: "\\'")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\r", with: "\\r")
                let coordinator = context.coordinator
                webView.evaluateJavaScript("performFind('\(escaped)')") { result, _ in
                    DispatchQueue.main.async {
                        let count = (result as? Int) ?? 0
                        coordinator.onFindResults?(count)
                        if count > 0 {
                            webView.evaluateJavaScript("scrollToMatch(0)")
                        }
                    }
                }
            }
        } else if prev.findMatchIndex != cur.findMatchIndex && !cur.findQuery.isEmpty && context.coordinator.isLoaded {
            webView.evaluateJavaScript("scrollToMatch(\(cur.findMatchIndex))")
        }
    }

    /// Find-in-page functions, injected by the app so the page's content
    /// security policy (no scripts) doesn't apply to them.
    static let findScript = """
        var findMatches = [];
        // Cap on highlighted matches. Large enough to cover any realistic word
        // search even in a long document, but bounded so a pathological query
        // (e.g. a single common letter) can't freeze the renderer wrapping
        // hundreds of thousands of nodes.
        var FIND_CAP = 10000;
        function clearFind() {
            var marks = document.querySelectorAll('mark.find-hl');
            for (var i = 0; i < marks.length; i++) {
                marks[i].replaceWith(marks[i].textContent);
            }
            if (marks.length) document.body.normalize();
            findMatches = [];
        }
        function performFind(q) {
            clearFind();
            if (!q) return 0;
            var lower = q.toLowerCase();
            var qlen = q.length;
            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
            var nodes = [];
            while (walker.nextNode()) nodes.push(walker.currentNode);
            var total = 0;
            // Rebuild each matching text node once via a fragment instead of
            // mutating the live DOM per match (the old per-match Range +
            // surroundContents triggered O(matches) layout invalidations and
            // could pin the renderer for minutes on large documents).
            for (var i = 0; i < nodes.length && total < FIND_CAP; i++) {
                var node = nodes[i];
                if (!node.parentNode) continue;
                var text = node.textContent;
                var hay = text.toLowerCase();
                if (hay.indexOf(lower) === -1) continue;
                var frag = document.createDocumentFragment();
                var last = 0;
                var idx;
                while (total < FIND_CAP && (idx = hay.indexOf(lower, last)) !== -1) {
                    if (idx > last) frag.appendChild(document.createTextNode(text.slice(last, idx)));
                    var m = document.createElement('mark');
                    m.className = 'find-hl';
                    m.appendChild(document.createTextNode(text.slice(idx, idx + qlen)));
                    frag.appendChild(m);
                    last = idx + qlen;
                    total++;
                }
                if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
                node.parentNode.replaceChild(frag, node);
            }
            findMatches = document.querySelectorAll('mark.find-hl');
            return findMatches.length;
        }
        function scrollToMatch(i) {
            findMatches.forEach(function(m) { m.classList.remove('find-cur'); });
            if (i >= 0 && i < findMatches.length) {
                findMatches[i].classList.add('find-cur');
                findMatches[i].scrollIntoView({behavior: 'smooth', block: 'center'});
            }
        }
        """

    private func buildPage() -> String {
        PageTemplate(
            fontSize: fontSize,
            maxWidth: maxWidth,
            fontFamily: fontFamily,
            appearance: appearance,
            textAlignment: textAlignment,
            imageSources: ["\(LocalFileSchemeHandler.scheme):", "https:", "http:", "data:"]
        ).page(body: html)
    }

    struct Snapshot {
        let fileURL: URL?
        let html: String
        let contentVersion: Int
        let fontSize: CGFloat
        let maxWidth: CGFloat
        let fontFamily: String
        let appearance: Appearance
        let textAlignment: TextAlignment
        let findQuery: String
        let findMatchIndex: Int
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var snapshot: Snapshot?
        let fileHandler = LocalFileSchemeHandler()
        var onFindResults: ((Int) -> Void)?
        var pendingFindQuery: String?
        var pendingFindIndex: Int = 0
        var isLoaded = false
        var pendingScrollY: Double?
        /// The URL the current page was loaded with; the only main-frame
        /// navigation allowed besides same-page anchor links.
        private var pageURL: URL?

        func load(_ page: String, baseURL: URL?, in webView: WKWebView) {
            pageURL = baseURL ?? URL(string: "about:blank")
            webView.loadHTMLString(page, baseURL: baseURL)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            if let y = pendingScrollY {
                pendingScrollY = nil
                webView.evaluateJavaScript("window.scrollTo(0, \(y))")
            }
            guard let query = pendingFindQuery, !query.isEmpty else { return }
            pendingFindQuery = nil
            let escaped = query
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            let idx = pendingFindIndex
            webView.evaluateJavaScript("performFind('\(escaped)')") { [weak self] result, _ in
                DispatchQueue.main.async {
                    let count = (result as? Int) ?? 0
                    self?.onFindResults?(count)
                    if count > 0 {
                        webView.evaluateJavaScript("scrollToMatch(\(min(idx, count - 1)))")
                    }
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                if let fileURL = LocalFileSchemeHandler.fileURL(for: url) {
                    // Same-page anchors scroll in place.
                    if url.fragment != nil, let current = webView.url,
                       LocalFileSchemeHandler.fileURL(for: current) == fileURL {
                        decisionHandler(.allow)
                        return
                    }
                    Self.openLocalLink(fileURL)
                } else if ["http", "https", "mailto"].contains(url.scheme?.lowercased()) {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
            } else if navigationAction.targetFrame?.isMainFrame == true,
                      navigationAction.request.url == pageURL {
                decisionHandler(.allow)
            } else {
                // Anything the document itself tries, like <meta http-equiv="refresh">.
                decisionHandler(.cancel)
            }
        }

        /// Markdown links open in Plainview and documents in their default app.
        /// Anything else, such as an app or a script, is only shown in Finder,
        /// so clicking a link in a file can't run it.
        static func openLocalLink(_ fileURL: URL) {
            let type = UTType(filenameExtension: fileURL.pathExtension)
            if MarkdownFile.canOpen(fileURL) {
                NSWorkspace.shared.open([fileURL], withApplicationAt: Bundle.main.bundleURL, configuration: NSWorkspace.OpenConfiguration())
            } else if let type, [UTType.pdf, .image, .audiovisualContent].contains(where: type.conforms(to:)) {
                NSWorkspace.shared.open(fileURL)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
        }
    }
}
