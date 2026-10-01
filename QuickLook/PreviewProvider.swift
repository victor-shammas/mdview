import Cocoa
import Markdown
import QuickLookUI
import UniformTypeIdentifiers

/// Renders Markdown files for Quick Look (Space in Finder) with the same
/// converter and styles as the app.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let fileURL = request.fileURL
        let text = try MarkdownFile.read(fileURL)
        var converter = HTMLConverter()
        var body = converter.visit(Document(parsing: text))

        // A preview can't load local images by path. Attach the ones this
        // extension is allowed to read; Quick Look's sandbox usually only
        // grants the previewed file, so the rest become a labeled placeholder
        // instead of a broken-image icon.
        var attachments: [String: QLPreviewReplyAttachment] = [:]
        let folder = fileURL.deletingLastPathComponent()
        for source in Set(converter.imageSources) where !source.contains(":") {
            let imageURL = URL(fileURLWithPath: source.removingPercentEncoding ?? source, relativeTo: folder)
            let tag = "<img src=\"\(HTMLConverter.escape(source))\""
            if let type = UTType(filenameExtension: imageURL.pathExtension), type.conforms(to: .image),
               let data = try? Data(contentsOf: imageURL) {
                let name = "image\(attachments.count)"
                attachments[name] = QLPreviewReplyAttachment(data: data, contentType: type)
                body = body.replacingOccurrences(of: tag, with: "<img src=\"cid:\(name)\"")
            } else {
                body = Self.replaceImageTags(startingWith: tag, in: body)
            }
        }

        let page = PageTemplate(imageSources: ["cid:", "data:", "https:"]).page(body: body + Self.placeholderStyle)
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 900, height: 1100)) { _ in
            Data(page.utf8)
        }
        reply.attachments = attachments
        return reply
    }

    private static let placeholderStyle = """
        <style>
        .image-unavailable {
            display: inline-block;
            padding: 0.4em 0.8em;
            border: 1px dashed var(--border);
            border-radius: 6px;
            color: var(--subtle);
            font-size: 0.9em;
        }
        </style>
        """

    /// Swaps each `<img ...>` tag beginning with `prefix` for a placeholder
    /// showing the image's alt text (or file name).
    private static func replaceImageTags(startingWith prefix: String, in html: String) -> String {
        let pattern = NSRegularExpression.escapedPattern(for: prefix) + "[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        var result = html
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let tag = String(result[range])
            var label = "Image"
            if let altRange = tag.range(of: #"alt="([^"]*)""#, options: .regularExpression) {
                let alt = tag[altRange].dropFirst(5).dropLast()
                if !alt.isEmpty { label = String(alt) }
            }
            result.replaceSubrange(range, with: "<span class=\"image-unavailable\">\u{1F5BC}\u{FE0E} \(label)</span>")
        }
        return result
    }
}
