import Foundation

/// The HTML page a rendered document is shown in. Shared by the app and the
/// Quick Look extension so both look the same.
struct PageTemplate {
    var fontSize: CGFloat = 16
    var maxWidth: CGFloat = 800
    var fontFamily: String = ViewFont.system.css
    var appearance: Appearance = .auto
    var textAlignment: TextAlignment = .left
    /// Where images may load from (Content-Security-Policy sources).
    var imageSources: [String] = ["data:"]

    /// Documents may contain raw HTML, so the page allows no scripts, frames,
    /// forms or `<base>` of its own. Only images and inline styles load.
    var contentSecurityPolicy: String {
        "default-src 'none'; img-src \(imageSources.joined(separator: " ")); style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"
    }

    func page(body: String) -> String {
        let themeAttr: String
        switch appearance {
        case .auto:  themeAttr = ""
        case .light: themeAttr = " data-theme=\"light\""
        case .dark:  themeAttr = " data-theme=\"dark\""
        }

        return """
        <!DOCTYPE html>
        <html\(themeAttr)>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <style>
        :root {
            --base-font-size: \(fontSize)px;
            --max-width: \(Int(maxWidth))px;
            --font-family: \(fontFamily);
            --text-align: \(textAlignment.css);
            --text: #1d1d1f;
            --bg: #ffffff;
            --code-bg: #f5f5f7;
            --border: #d2d2d7;
            --link: #0066cc;
            --subtle: #86868b;
        }
        @media (prefers-color-scheme: dark) {
            :root:not([data-theme="light"]) {
                --text: #f5f5f7;
                --bg: #1d1d1f;
                --code-bg: #2c2c2e;
                --border: #48484a;
                --link: #6cb4ff;
                --subtle: #98989d;
            }
        }
        :root[data-theme="dark"] {
            --text: #f5f5f7;
            --bg: #1d1d1f;
            --code-bg: #2c2c2e;
            --border: #48484a;
            --link: #6cb4ff;
            --subtle: #98989d;
        }
        html {
            font-size: var(--base-font-size);
            transition: font-size 0.12s ease;
        }
        body {
            font-family: var(--font-family);
            line-height: 1.7;
            color: var(--text);
            background: var(--bg);
            max-width: var(--max-width);
            margin: 0 auto;
            padding: 48px 32px;
            -webkit-font-smoothing: antialiased;
            word-wrap: break-word;
            transition: max-width 0.2s ease;
        }
        h1, h2, h3, h4, h5, h6 { line-height: 1.25; scroll-margin-top: 24px; }
        h1 { font-size: 2em; margin: 1.4em 0 0.6em; font-weight: 700; }
        h2 { font-size: 1.5em; margin: 1.4em 0 0.5em; font-weight: 600; }
        h3 { font-size: 1.25em; margin: 1.3em 0 0.5em; font-weight: 600; }
        h4, h5, h6 { font-size: 1em; margin: 1.2em 0 0.4em; font-weight: 600; }
        body > *:first-child { margin-top: 0; }
        p { margin: 0 0 1em; text-align: var(--text-align); }
        li { text-align: var(--text-align); }
        a { color: var(--link); text-decoration: none; }
        a:hover { text-decoration: underline; }
        strong { font-weight: 600; }
        code {
            font-family: "SF Mono", Menlo, Consolas, monospace;
            font-size: 0.88em;
            background: var(--code-bg);
            padding: 0.15em 0.35em;
            border-radius: 4px;
        }
        pre {
            background: var(--code-bg);
            padding: 16px 20px;
            border-radius: 8px;
            overflow-x: auto;
            margin: 0 0 1em;
            line-height: 1.5;
        }
        pre code {
            background: none;
            padding: 0;
            font-size: 0.85em;
        }
        blockquote {
            border-left: 3px solid var(--border);
            margin: 0 0 1em;
            padding: 0.1em 0 0.1em 20px;
            color: var(--subtle);
        }
        blockquote p:last-child { margin-bottom: 0; }
        ul, ol { margin: 0 0 1em; padding-left: 1.5em; }
        li { margin-bottom: 0.25em; }
        li > p:first-child { margin-top: 0; }
        li > p:last-child { margin-bottom: 0; }
        hr {
            border: none;
            border-top: 1px solid var(--border);
            margin: 2em 0;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 0 0 1em;
            font-size: 0.95em;
        }
        th, td {
            padding: 8px 12px;
            border: 1px solid var(--border);
            text-align: left;
        }
        th { background: var(--code-bg); font-weight: 600; }
        img { max-width: 100%; height: auto; border-radius: 4px; }
        .task-item { list-style: none; margin-left: -1.5em; }
        .task-item input[type="checkbox"] {
            margin-right: 0.4em;
            pointer-events: none;
        }
        del { color: var(--subtle); }
        mark.find-hl { background: rgba(255, 230, 0, 0.45); color: inherit; padding: 1px 0; border-radius: 2px; }
        mark.find-hl.find-cur { background: rgba(255, 150, 50, 0.7); }
        @media print {
            :root, :root:not([data-theme="light"]), :root[data-theme="dark"] {
                --text: #000 !important;
                --bg: #fff !important;
                --code-bg: #f5f5f7 !important;
                --border: #ccc !important;
                --link: #000 !important;
                --subtle: #555 !important;
            }
            body {
                padding: 0;
                max-width: none;
                color: #000 !important;
                background: #fff !important;
                -webkit-print-color-adjust: exact;
            }
            mark.find-hl { background: none !important; }
        }
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }
}
