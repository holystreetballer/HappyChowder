import SwiftUI

struct MarkdownContentView: View {
    let text: String
    let foregroundColor: Color
    private let cachedBlocks: [Block]

    init(_ text: String, foregroundColor: Color = Color(.label)) {
        self.text = text
        self.foregroundColor = foregroundColor
        self.cachedBlocks = Self.parseBlocks(from: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(cachedBlocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    fileprivate enum Block {
        case paragraph(String)
        case codeBlock(language: String?, code: String)
        case heading(level: Int, text: String)
        case unorderedList([String])
        case orderedList([String])
        case blockquote(String)
    }

    private static func parseBlocks(from text: String) -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var paragraph = ""

        func flushParagraph() {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { blocks.append(.paragraph(trimmed)) }
            paragraph = ""
        }

        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("```") {
                flushParagraph()
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }
                blocks.append(.codeBlock(language: lang.isEmpty ? nil : lang, code: code.joined(separator: "\n")))
                continue
            }

            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                if level <= 6, line.count > level, line[line.index(line.startIndex, offsetBy: level)] == " " {
                    flushParagraph()
                    blocks.append(.heading(level: level, text: String(line.dropFirst(level + 1))))
                    i += 1
                    continue
                }
            }

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("- ") || line.trimmingCharacters(in: .whitespaces).hasPrefix("* ") {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("- ") { items.append(String(trimmed.dropFirst(2))) }
                    else if trimmed.hasPrefix("* ") { items.append(String(trimmed.dropFirst(2))) }
                    else { break }
                    i += 1
                }
                blocks.append(.unorderedList(items))
                continue
            }

            let stripped = line.trimmingCharacters(in: .whitespaces)
            if let dotIndex = stripped.firstIndex(of: "."),
               dotIndex != stripped.startIndex,
               Int(stripped[stripped.startIndex..<dotIndex]) != nil,
               stripped.count > stripped.distance(from: stripped.startIndex, to: dotIndex) + 1 {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    let s = lines[i].trimmingCharacters(in: .whitespaces)
                    if let d = s.firstIndex(of: "."), d != s.startIndex, Int(s[s.startIndex..<d]) != nil {
                        items.append(s[s.index(after: d)...].trimmingCharacters(in: .whitespaces))
                    } else { break }
                    i += 1
                }
                blocks.append(.orderedList(items))
                continue
            }

            if line.hasPrefix("> ") {
                flushParagraph()
                var quoteLines: [String] = []
                while i < lines.count && lines[i].hasPrefix("> ") {
                    quoteLines.append(String(lines[i].dropFirst(2)))
                    i += 1
                }
                blocks.append(.blockquote(quoteLines.joined(separator: "\n")))
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            paragraph += (paragraph.isEmpty ? "" : "\n") + line
            i += 1
        }
        flushParagraph()
        return blocks
    }

    @ViewBuilder
    private func renderBlock(_ block: Block) -> some View {
        switch block {
        case .paragraph(let content):
            inlineMarkdown(content)
        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 0) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(Color(.label))
                        .padding(.horizontal, 12)
                        .padding(.vertical, language == nil ? 10 : 6)
                        .padding(.bottom, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        case .heading(let level, let content):
            inlineMarkdown(content).font(.system(size: headingSize(level), weight: .bold))
        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) { Text("•").foregroundStyle(foregroundColor); inlineMarkdown(item) }
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 8) { Text("\(idx + 1).").foregroundStyle(foregroundColor).monospacedDigit(); inlineMarkdown(item) }
                }
            }
        case .blockquote(let content):
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1).fill(Color(.systemGray3)).frame(width: 3)
                inlineMarkdown(content).foregroundStyle(.secondary).padding(.leading, 10)
            }
        }
    }

    @ViewBuilder
    private func inlineMarkdown(_ content: String) -> some View {
        if let attributed = try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed).foregroundStyle(foregroundColor)
        } else {
            Text(content).foregroundStyle(foregroundColor)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level { case 1: return 24; case 2: return 20; case 3: return 18; default: return 17 }
    }
}
