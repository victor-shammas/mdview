import AppKit
@preconcurrency import WebKit

/// Lays a document out for printing in a hidden web view, so the window
/// being read never changes, and renders it as one PDF page per sheet of
/// paper (half-inch margins) for the print panel.
final class PrintRenderer: NSObject, WKNavigationDelegate {
    private let paper: CGSize
    private let margin: CGFloat = 36
    private let printWidth: CGFloat
    private let pageHeight: CGFloat
    private let page: String
    private let baseURL: URL?
    private let fileHandler = LocalFileSchemeHandler()
    private let webView: WKWebView
    private let title: String
    private var completion: ((Data?) -> Void)?
    private var links = PageLinks(links: [], anchors: [])

    /// Printed pages are black on white, and code wraps instead of running
    /// past the margin.
    private static let printStyle = """
        <style>
        html, body { transition: none !important; }
        /* The hidden web view has no window, so it would get a classic
           scrollbar that narrows the text column. */
        html { overflow: hidden; }
        body { max-width: none !important; margin: 0 !important; padding: 0 !important; }
        pre { white-space: pre-wrap; overflow-wrap: anywhere; }
        :root {
            --text: #000;
            --bg: #fff;
            --code-bg: #f5f5f7;
            --border: #ccc;
            --link: #000;
            --subtle: #555;
        }
        </style>
        """

    init(html: String, fileURL: URL?, paper: CGSize) {
        self.paper = paper
        title = fileURL?.deletingPathExtension().lastPathComponent ?? ""
        printWidth = (paper.width - 2 * margin).rounded()
        pageHeight = paper.height - 2 * margin

        let appState = AppState.shared
        page = PageTemplate(
            fontSize: appState.fontSize,
            maxWidth: printWidth,
            fontFamily: appState.selectedFont.css,
            appearance: .light,
            textAlignment: appState.textAlignment,
            imageSources: ["\(LocalFileSchemeHandler.scheme):", "https:", "http:", "data:"]
        ).page(body: html + Self.printStyle)
        baseURL = fileURL.flatMap { LocalFileSchemeHandler.pageURL(for: $0.deletingLastPathComponent()) }

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(fileHandler, forURLScheme: LocalFileSchemeHandler.scheme)
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: printWidth, height: pageHeight), configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    /// Calls `completion` with the paginated PDF, or nil if rendering failed.
    func render(completion: @escaping (Data?) -> Void) {
        self.completion = completion
        webView.loadHTMLString(page, baseURL: baseURL)
    }

    private func finish(_ data: Data?) {
        completion?(data)
        completion = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Page breaks go between lines, never through one: merge the
        // boxes of all text lines and images into horizontal bands and
        // break at the last band that starts before the page is full.
        // A heading is kept with the line that follows it.
        let breakJS = """
            (function() {
                var ph = \(pageHeight);
                var sy = window.scrollY;
                var total = Math.ceil(document.body.scrollHeight);
                var boxes = [];
                function add(r) {
                    if (r.height > 0) boxes.push([r.top + sy, r.bottom + sy]);
                }
                var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
                var range = document.createRange();
                while (walker.nextNode()) {
                    if (!walker.currentNode.textContent.trim()) continue;
                    range.selectNodeContents(walker.currentNode);
                    var rects = range.getClientRects();
                    for (var i = 0; i < rects.length; i++) add(rects[i]);
                }
                document.querySelectorAll('img, hr, input').forEach(function(el) {
                    add(el.getBoundingClientRect());
                });
                boxes.sort(function(a, b) { return a[0] - b[0]; });
                var bands = [];
                boxes.forEach(function(b) {
                    var last = bands[bands.length - 1];
                    if (last && b[0] < last[1]) last[1] = Math.max(last[1], b[1]);
                    else bands.push([b[0], b[1]]);
                });
                var avoid = {};
                document.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach(function(h) {
                    var bottom = h.getBoundingClientRect().bottom + sy;
                    for (var i = 0; i < bands.length; i++) {
                        if (bands[i][0] >= bottom - 1) { avoid[i] = true; break; }
                    }
                });
                var breaks = [];
                var start = 0;
                while (total - start > ph) {
                    var limit = start + ph;
                    var best = -1;
                    for (var i = 0; i < bands.length && bands[i][0] <= limit; i++) {
                        if (bands[i][0] > start + 1 && !avoid[i]) best = bands[i][0];
                    }
                    if (best < 0) best = limit;
                    best = Math.floor(best);
                    breaks.push(best);
                    start = best;
                }
                return JSON.stringify({b: breaks, h: total});
            })()
        """

        webView.evaluateJavaScript(breakJS) { [weak self] result, _ in
            guard let self,
                  let json = (result as? String)?.data(using: .utf8),
                  let layout = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
                  let breaks = layout["b"] as? [Double],
                  let total = layout["h"] as? Double else {
                self?.finish(nil)
                return
            }
            let slices = self.slices(breaks: breaks.map { CGFloat($0) }, totalHeight: CGFloat(total))
            webView.evaluateJavaScript(Self.linksJS) { [weak self] result, _ in
                guard let self else { return }
                if let json = (result as? String)?.data(using: .utf8),
                   let links = try? JSONDecoder().decode(PageLinks.self, from: json) {
                    self.links = links
                }
                self.capture(slices: slices)
            }
        }
    }

    /// Where the links and heading anchors are, so the PDF can keep them
    /// clickable: web and mail links open, `#heading` links jump in the PDF.
    private static let linksJS = """
        (function() {
            var sx = window.scrollX, sy = window.scrollY;
            var links = [];
            document.querySelectorAll('a[href]').forEach(function(a) {
                var href = a.getAttribute('href');
                var target;
                if (href.charAt(0) === '#') target = {anchor: decodeURIComponent(href.slice(1))};
                else if (/^(https?|mailto):/i.test(a.href)) target = {url: a.href};
                else return;
                var rects = [];
                Array.from(a.getClientRects()).forEach(function(r) {
                    if (r.width > 0 && r.height > 0) rects.push([r.left + sx, r.top + sy, r.width, r.height]);
                });
                if (rects.length) links.push({target: target, rects: rects});
            });
            var anchors = [];
            document.querySelectorAll('[id]').forEach(function(el) {
                anchors.push({id: el.id, y: el.getBoundingClientRect().top + sy});
            });
            return JSON.stringify({links: links, anchors: anchors});
        })()
        """

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Only the page itself; nothing the document tries on its own.
        let url = navigationAction.request.url
        decisionHandler(url == baseURL || url?.absoluteString == "about:blank" ? .allow : .cancel)
    }

    /// Each printed page is one slice of the laid-out document.
    private func slices(breaks: [CGFloat], totalHeight: CGFloat) -> [PrintSlice] {
        let allBreaks = [CGFloat(0)] + breaks + [totalHeight]
        var slices: [PrintSlice] = []
        for i in 0..<(allBreaks.count - 1) {
            var yStart = allBreaks[i]
            let yEnd = min(allBreaks[i + 1], totalHeight)
            while yEnd - yStart > pageHeight {
                slices.append(PrintSlice(start: yStart, end: yStart + pageHeight))
                yStart += pageHeight
            }
            if yEnd > yStart {
                slices.append(PrintSlice(start: yStart, end: yEnd))
            }
        }
        return slices
    }

    /// Captures each slice as its own PDF page. Capturing larger runs and
    /// clipping would leave the neighbouring lines' text hidden in the page
    /// margins, where PDF search and copy still find it (and WebKit cuts a
    /// single capture off at 14,400 points, the PDF page size limit).
    private func capture(slices: [PrintSlice]) {
        var captures: [(document: CGPDFDocument, slice: PrintSlice)] = []
        func captureNextSlice() {
            guard captures.count < slices.count else {
                finish(compose(captures))
                return
            }
            let slice = slices[captures.count]
            let config = WKPDFConfiguration()
            config.rect = CGRect(x: 0, y: slice.start, width: printWidth, height: slice.end - slice.start)
            webView.createPDF(configuration: config) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard case .success(let data) = result,
                          let provider = CGDataProvider(data: data as CFData),
                          let document = CGPDFDocument(provider),
                          document.numberOfPages > 0 else {
                        self.finish(nil)
                        return
                    }
                    captures.append((document, slice))
                    captureNextSlice()
                }
            }
        }
        captureNextSlice()
    }

    /// Lays the captured slices out one per sheet, inside the margins.
    private func compose(_ captures: [(document: CGPDFDocument, slice: PrintSlice)]) -> Data? {
        let pageData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pageData) else { return nil }
        var pageBox = CGRect(origin: .zero, size: paper)
        let info = [kCGPDFContextTitle: title, kCGPDFContextCreator: "Plainview"] as CFDictionary
        guard let ctx = CGContext(consumer: consumer, mediaBox: &pageBox, info) else { return nil }
        let anchorIDs = Set(links.anchors.map(\.id))

        for (document, slice) in captures {
            guard let source = document.page(at: 1) else { continue }
            ctx.beginPage(mediaBox: &pageBox)
            ctx.saveGState()
            ctx.translateBy(x: margin, y: paper.height - margin - source.getBoxRect(.mediaBox).height)
            ctx.drawPDFPage(source)
            ctx.restoreGState()
            addLinks(to: ctx, for: slice, anchorIDs: anchorIDs)
            ctx.endPage()
        }
        ctx.closePDF()
        return pageData as Data
    }
}

extension PrintRenderer {
    /// Converts a point in the laid-out document to the page showing `slice`.
    private func pageY(_ y: CGFloat, in slice: PrintSlice) -> CGFloat {
        paper.height - margin - (y - slice.start)
    }

    private func addLinks(to ctx: CGContext, for slice: PrintSlice, anchorIDs: Set<String>) {
        for anchor in links.anchors where anchor.y >= slice.start && anchor.y < slice.end {
            ctx.addDestination(anchor.id as CFString, at: CGPoint(x: margin, y: pageY(anchor.y, in: slice)))
        }
        for link in links.links {
            for r in link.rects where r.count == 4 {
                let top = max(r[1], slice.start)
                let bottom = min(r[1] + r[3], slice.end)
                guard bottom > top else { continue }
                let rect = CGRect(x: margin + r[0], y: pageY(bottom, in: slice), width: r[2], height: bottom - top)
                if let url = link.target.url.flatMap(URL.init(string:)) {
                    ctx.setURL(url as CFURL, for: rect)
                } else if let anchor = link.target.anchor, anchorIDs.contains(anchor) {
                    ctx.setDestination(anchor as CFString, for: rect)
                }
            }
        }
    }
}

/// Links and heading anchors in the laid-out document, in page pixels.
private struct PageLinks: Decodable {
    struct Link: Decodable {
        struct Target: Decodable {
            var url: String?
            var anchor: String?
        }
        var target: Target
        var rects: [[CGFloat]]
    }
    struct Anchor: Decodable {
        var id: String
        var y: CGFloat
    }
    var links: [Link]
    var anchors: [Anchor]
}

/// A vertical slice of the laid-out document that becomes one printed page.
struct PrintSlice {
    let start: CGFloat
    let end: CGFloat
}
