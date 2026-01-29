import Foundation
import SwiftUI

struct MarkdownRenderer: View {
    let text: String

    var body: some View {
        let blocks = MarkdownParser.parse(text)

        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                switch block.kind {
                case .heading(let level, let content):
                    inlineText(content)
                        .font(headingFont(level: level))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                case .paragraph(let content):
                    inlineText(content)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)

                case .unorderedList(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(AppTheme.mutedInk)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 7)

                                inlineText(item)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                case .orderedList(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(idx + 1).")
                                    .font(.subheadline)
                                    .foregroundColor(AppTheme.mutedInk)
                                    .frame(minWidth: 18, alignment: .leading)

                                inlineText(item)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                case .codeBlock(let content):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(content)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(AppTheme.ink)
                            .padding(12)
                    }
                    .background(AppTheme.surfaceAlt)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func inlineText(_ content: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )

        if let attributed = try? AttributedString(markdown: content, options: options) {
            return Text(attributed)
        }

        return Text(content)
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:
            return .title3
        case 2:
            return .headline
        default:
            return .subheadline
        }
    }
}

private enum MarkdownBlockKind {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case unorderedList(items: [String])
    case orderedList(items: [String])
    case codeBlock(text: String)
}

private struct MarkdownBlock: Identifiable {
    let id = UUID()
    let kind: MarkdownBlockKind
}

private enum MarkdownListType {
    case unordered
    case ordered
}

private enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalized.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)

        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var listItems: [String] = []
        var listType: MarkdownListType? = nil
        var codeLines: [String] = []
        var inCodeBlock = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(MarkdownBlock(kind: .paragraph(text: paragraph.joined(separator: "\n"))))
            paragraph.removeAll()
        }

        func flushList() {
            guard !listItems.isEmpty, let type = listType else { return }
            switch type {
            case .unordered:
                blocks.append(MarkdownBlock(kind: .unorderedList(items: listItems)))
            case .ordered:
                blocks.append(MarkdownBlock(kind: .orderedList(items: listItems)))
            }
            listItems.removeAll()
            listType = nil
        }

        func flushAll() {
            flushParagraph()
            flushList()
        }

        for raw in lines {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if inCodeBlock {
                if trimmed.hasPrefix("```") {
                    blocks.append(MarkdownBlock(kind: .codeBlock(text: codeLines.joined(separator: "\n"))))
                    codeLines.removeAll()
                    inCodeBlock = false
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flushAll()
                inCodeBlock = true
                continue
            }

            if trimmed.isEmpty {
                flushAll()
                continue
            }

            if let heading = parseHeading(from: trimmed) {
                flushAll()
                blocks.append(MarkdownBlock(kind: .heading(level: heading.level, text: heading.text)))
                continue
            }

            if let item = parseUnorderedListItem(from: trimmed) {
                flushParagraph()
                if listType != .unordered {
                    flushList()
                    listType = .unordered
                }
                listItems.append(item)
                continue
            }

            if let item = parseOrderedListItem(from: trimmed) {
                flushParagraph()
                if listType != .ordered {
                    flushList()
                    listType = .ordered
                }
                listItems.append(item)
                continue
            }

            if isContinuationLine(line), listType != nil {
                if let last = listItems.last {
                    listItems[listItems.count - 1] = last + "\n" + trimmed
                }
                continue
            }

            paragraph.append(line)
        }

        if inCodeBlock {
            blocks.append(MarkdownBlock(kind: .codeBlock(text: codeLines.joined(separator: "\n"))))
        }

        flushAll()
        return blocks
    }

    private static func parseHeading(from trimmed: String) -> (level: Int, text: String)? {
        for level in 1...3 {
            let prefix = String(repeating: "#", count: level) + " "
            if trimmed.hasPrefix(prefix) {
                let content = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                return (level, String(content))
            }
        }
        return nil
    }

    private static func parseUnorderedListItem(from trimmed: String) -> String? {
        if trimmed.hasPrefix("- ") {
            return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        if trimmed.hasPrefix("* ") {
            return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        if trimmed.hasPrefix("+ ") {
            return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func parseOrderedListItem(from trimmed: String) -> String? {
        let parts = trimmed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, Int(parts[0]) != nil else { return nil }
        let remainder = parts[1].trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty else { return nil }
        return remainder
    }

    private static func isContinuationLine(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        return first == " " || first == "\t"
    }
}
