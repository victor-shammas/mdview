import Foundation

enum MarkdownFile {
    static let extensions = ["md", "markdown", "mdown", "mkd", "txt"]

    static func canOpen(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    /// Reads a text file as UTF-8, falling back to whatever encoding Foundation
    /// detects (UTF-16 with a BOM, Windows-1252, Latin-1, ...) for older files.
    static func read(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        var text: String
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else {
            var converted: NSString?
            let encoding = NSString.stringEncoding(
                for: data,
                encodingOptions: [
                    .suggestedEncodingsKey: [String.Encoding.windowsCP1252.rawValue],
                    .allowLossyKey: false,
                ],
                convertedString: &converted,
                usedLossyConversion: nil
            )
            guard encoding != 0, let converted else {
                throw CocoaError(.fileReadInapplicableStringEncoding, userInfo: [
                    NSURLErrorKey: url,
                    NSLocalizedFailureReasonErrorKey: "It doesn\u{2019}t look like a text file.",
                ])
            }
            text = converted as String
        }
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        return text
    }
}
