import Foundation

/// A deliberately small block-level markdown splitter. SwiftUI's `Text` only
/// renders inline markdown (bold, italic, code, links) from AttributedString;
/// headings, lists, code fences and tables need laying out as separate views.
/// The UI turns each block into a view and uses AttributedString for inlines.
public enum MarkdownBlock: Hashable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case listItem(indent: Int, marker: String, text: String)
    case quote(String)
    case code(language: String, text: String)
    case table([String])
    case rule
}

public enum MarkdownBlocks {
    public static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: (lang: String, lines: [String])?
        var table: [String] = []

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            if !table.isEmpty { blocks.append(.table(table)) }
            paragraph = []
            table = []
        }

        for rawLine in source.components(separatedBy: "\n") {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if var open = code {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(language: open.lang, text: open.lines.joined(separator: "\n")))
                    code = nil
                } else {
                    open.lines.append(rawLine)
                    code = open
                }
                continue
            }
            if trimmed.hasPrefix("```") {
                flush()
                code = (String(trimmed.dropFirst(3)), [])
                continue
            }
            if trimmed.isEmpty { flush(); continue }
            if trimmed.hasPrefix("|") {
                if !paragraph.isEmpty { flush() }
                table.append(trimmed)
                continue
            }
            if let hashes = trimmed.firstIndex(where: { $0 != "#" }), trimmed.hasPrefix("#"),
               trimmed[hashes] == " " {
                flush()
                let level = trimmed.distance(from: trimmed.startIndex, to: hashes)
                blocks.append(.heading(level: min(level, 6), text: String(trimmed[hashes...]).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flush()
                blocks.append(.rule)
                continue
            }
            if trimmed.hasPrefix(">") {
                flush()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if let item = listItem(line) {
                flush()
                blocks.append(item)
                continue
            }
            // A continuation line under a list item joins that item.
            if paragraph.isEmpty, case .listItem(let indent, let marker, let text)? = blocks.last,
               line.hasPrefix("  ") {
                blocks[blocks.count - 1] = .listItem(indent: indent, marker: marker, text: text + " " + trimmed)
                continue
            }
            paragraph.append(trimmed)
        }
        if let open = code { blocks.append(.code(language: open.lang, text: open.lines.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    static func listItem(_ line: String) -> MarkdownBlock? {
        let indent = line.prefix(while: { $0 == " " }).count
        let rest = line.dropFirst(indent)
        for bullet in ["- [ ] ", "- [x] ", "- ", "* ", "+ "] where rest.hasPrefix(bullet) {
            let marker: String
            switch bullet {
            case "- [ ] ": marker = "☐"
            case "- [x] ": marker = "☑"
            default: marker = "•"
            }
            return .listItem(indent: indent / 2, marker: marker, text: String(rest.dropFirst(bullet.count)))
        }
        let digits = rest.prefix(while: \.isNumber)
        if !digits.isEmpty, rest.dropFirst(digits.count).hasPrefix(". ") {
            return .listItem(indent: indent / 2, marker: "\(digits).", text: String(rest.dropFirst(digits.count + 2)))
        }
        return nil
    }
}
