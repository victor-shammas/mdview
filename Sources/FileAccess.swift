import Foundation
import UniformTypeIdentifiers
@preconcurrency import WebKit

// MARK: - Security-Scoped Bookmarks

extension URL {
    /// Creates a security-scoped bookmark so the sandboxed app can reopen this
    /// file or folder after relaunch. Briefly claims access first, which is
    /// required when the URL itself was resolved from an earlier bookmark.
    func securityScopedBookmark() -> Data? {
        let accessing = startAccessingSecurityScopedResource()
        defer { if accessing { stopAccessingSecurityScopedResource() } }
        return try? bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves a security-scoped bookmark, returning the URL and a refreshed
    /// bookmark when the original has gone stale (file moved or renamed).
    static func resolvingSecurityScopedBookmark(_ data: Data) -> (url: URL, bookmark: Data)? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale) else {
            return nil
        }
        let bookmark = stale ? (url.securityScopedBookmark() ?? data) : data
        return (url, bookmark)
    }

    /// The deepest folder containing both URLs.
    func commonAncestor(with other: URL) -> URL {
        let a = standardizedFileURL.pathComponents
        let b = other.standardizedFileURL.pathComponents
        let shared = zip(a, b).prefix { $0 == $1 }.map { $0.0 }
        return URL(fileURLWithPath: NSString.path(withComponents: shared.isEmpty ? ["/"] : shared), isDirectory: true)
    }
}

// MARK: - Local Image Loading

/// Serves images next to the Markdown file through a custom URL scheme.
///
/// Pages are loaded with an `plainview-file:` base URL, so relative paths like
/// `images/foo.png` (and `../foo.png`) resolve to requests that come here. The
/// app reads the file itself, which works under the App Sandbox once the user
/// has granted access to the folder, and reports denied reads so the window
/// can offer to ask for that access.
final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "plainview-file"

    var onAccessDenied: ((URL) -> Void)?
    /// Tasks still waiting on a file read, so stopped ones can be skipped.
    private var pendingTasks: [ObjectIdentifier: WKURLSchemeTask] = [:]

    static func pageURL(for fileURL: URL) -> URL? {
        var components = URLComponents(url: fileURL, resolvingAgainstBaseURL: false)
        components?.scheme = scheme
        return components?.url
    }

    static func fileURL(for pageURL: URL) -> URL? {
        guard pageURL.scheme == scheme else { return nil }
        var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)
        components?.scheme = "file"
        components?.fragment = nil
        components?.query = nil
        return components?.url
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let requestURL = task.request.url,
              let fileURL = Self.fileURL(for: requestURL) else {
            task.didFailWithError(CocoaError(.fileReadInvalidFileName))
            return
        }
        // Only images: the page never needs anything else from disk, and this
        // keeps raw HTML in a document from pulling arbitrary files.
        guard let type = UTType(filenameExtension: fileURL.pathExtension), type.conforms(to: .image) else {
            task.didFailWithError(CocoaError(.fileReadUnsupportedScheme))
            return
        }

        let id = ObjectIdentifier(task)
        pendingTasks[id] = task
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try Data(contentsOf: fileURL) }
            DispatchQueue.main.async {
                guard let self, let task = self.pendingTasks.removeValue(forKey: id) else { return }
                switch result {
                case .success(let data):
                    let response = URLResponse(
                        url: requestURL,
                        mimeType: type.preferredMIMEType ?? "application/octet-stream",
                        expectedContentLength: data.count,
                        textEncodingName: nil
                    )
                    task.didReceive(response)
                    task.didReceive(data)
                    task.didFinish()
                case .failure(let error):
                    if (error as? CocoaError)?.code == .fileReadNoPermission {
                        self.onAccessDenied?(fileURL)
                    }
                    task.didFailWithError(error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        pendingTasks.removeValue(forKey: ObjectIdentifier(task))
    }
}
