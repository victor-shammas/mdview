import Foundation
import Markdown

struct HTMLConverter: MarkupVisitor {
    typealias Result = String

    private var inTableHead = false

    mutating func defaultVisit(_ markup: any Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    mutating func visitDocument(_ document: Document) -> String {
        document.children.map { visit($0) }.joined()
    }

    // MARK: Block elements

    mutating func visitHeading(_ heading: Heading) -> String {
        let content = heading.children.map { visit($0) }.joined()
        return "<h\(heading.level)>\(content)</h\(heading.level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        let content = paragraph.children.map { visit($0) }.joined()
        return "<p>\(content)</p>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let lang = codeBlock.language ?? ""
        let cls = lang.isEmpty ? "" : " class=\"language-\(lang.escaped)\""
        return "<pre><code\(cls)>\(codeBlock.code.escaped)</code></pre>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        "<blockquote>\n\(blockQuote.children.map { visit($0) }.joined())</blockquote>\n"
    }

    mutating func visitUnorderedList(_ list: UnorderedList) -> String {
        "<ul>\n\(list.children.map { visit($0) }.joined())</ul>\n"
    }

    mutating func visitOrderedList(_ list: OrderedList) -> String {
        let start = list.startIndex
        let attr = start == 1 ? "" : " start=\"\(start)\""
        return "<ol\(attr)>\n\(list.children.map { visit($0) }.joined())</ol>\n"
    }

    mutating func visitListItem(_ item: ListItem) -> String {
        let content = item.children.map { visit($0) }.joined()
        if let checkbox = item.checkbox {
            let checked = checkbox == .checked ? " checked" : ""
            return "<li class=\"task-item\"><input type=\"checkbox\"\(checked) disabled>\(content)</li>\n"
        }
        return "<li>\(content)</li>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        html.rawHTML.sanitizedHTML
    }

    // MARK: Inline elements

    mutating func visitText(_ text: Text) -> String {
        text.string.escaped
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(strong.children.map { visit($0) }.joined())</strong>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(emphasis.children.map { visit($0) }.joined())</em>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(inlineCode.code.escaped)</code>"
    }

    mutating func visitLink(_ link: Link) -> String {
        let content = link.children.map { visit($0) }.joined()
        let href = (link.destination ?? "").escaped
        return "<a href=\"\(href)\">\(content)</a>"
    }

    mutating func visitImage(_ image: Image) -> String {
        let alt = image.children.map { visit($0) }.joined()
        let src = (image.source ?? "").escaped
        let title = image.title.map { " title=\"\($0.escaped)\"" } ?? ""
        return "<img src=\"\(src)\" alt=\"\(alt)\"\(title)>\n"
    }

    mutating func visitInlineHTML(_ html: InlineHTML) -> String {
        html.rawHTML.sanitizedHTML
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        "\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        "<br>\n"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>\(strikethrough.children.map { visit($0) }.joined())</del>"
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) -> String {
        "<code>\((symbolLink.destination ?? "").escaped)</code>"
    }

    // MARK: Tables

    mutating func visitTable(_ table: Table) -> String {
        "<table>\n\(table.children.map { visit($0) }.joined())</table>\n"
    }

    mutating func visitTableHead(_ head: Table.Head) -> String {
        inTableHead = true
        let cells = head.children.map { visit($0) }.joined()
        inTableHead = false
        return "<thead>\n<tr>\(cells)</tr>\n</thead>\n"
    }

    mutating func visitTableBody(_ body: Table.Body) -> String {
        "<tbody>\n\(body.children.map { visit($0) }.joined())</tbody>\n"
    }

    mutating func visitTableRow(_ row: Table.Row) -> String {
        "<tr>\(row.children.map { visit($0) }.joined())</tr>\n"
    }

    mutating func visitTableCell(_ cell: Table.Cell) -> String {
        let tag = inTableHead ? "th" : "td"
        let content = cell.children.map { visit($0) }.joined()
        return "<\(tag)>\(content)</\(tag)>"
    }
}

private extension String {
    var escaped: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    var sanitizedHTML: String {
        var result = self
        let dangerousTags = ["script", "iframe", "object", "embed", "form", "style"]
        for tag in dangerousTags {
            let pattern = "(?i)<\(tag)[^>]*>.*?</\(tag)\\s*>"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
            }
            let selfClosing = "(?i)<\(tag)[^>]*/\\s*>"
            if let regex = try? NSRegularExpression(pattern: selfClosing) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
            }
            let openOnly = "(?i)<\(tag)[^>]*>"
            if let regex = try? NSRegularExpression(pattern: openOnly) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
            }
        }
        if let onHandler = try? NSRegularExpression(pattern: "(?i)\\s+on\\w+\\s*=\\s*(\"[^\"]*\"|'[^']*'|\\S+)", options: []) {
            result = onHandler.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        if let jsURL = try? NSRegularExpression(pattern: "(?i)(href|src|action)\\s*=\\s*([\"'])\\s*javascript:", options: []) {
            result = jsURL.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$1=$2")
        }
        return result
    }
}
