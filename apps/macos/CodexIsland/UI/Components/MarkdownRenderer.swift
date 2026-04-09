//
//  MarkdownRenderer.swift
//  CodexIsland
//
//  Markdown renderer using swift-markdown for efficient parsing
//

import Foundation
import Markdown
import SwiftUI

enum MarkdownListItemRenderer {
    static func renderableChildren(for item: ListItem) -> [Markup] {
        item.children.compactMap { child in
            if let paragraph = child as? Paragraph {
                let text = paragraph.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
            }
            return child
        }
    }
}

private struct MarkdownListMarker {
    let text: String
    let width: CGFloat
    let alignment: Alignment
}

// MARK: - Document Cache

/// Caches parsed markdown documents to avoid re-parsing
private final class DocumentCache: @unchecked Sendable {
    static let shared = DocumentCache()
    private var cache: [String: Document] = [:]
    private let lock = NSLock()
    private let maxSize = 100

    func document(for text: String) -> Document {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[text] {
            return cached
        }

        let document = Document(parsing: text, options: [.parseBlockDirectives, .parseSymbolLinks])
        if cache.count >= maxSize {
            cache.removeAll()
        }
        cache[text] = document
        return document
    }
}

// MARK: - Markdown Text View

struct MarkdownText: View {
    let text: String
    let baseColor: Color
    let fontSize: CGFloat

    private let document: Document

    init(_ text: String, color: Color = .white.opacity(0.9), fontSize: CGFloat = 13) {
        self.text = text
        self.baseColor = color
        self.fontSize = fontSize
        self.document = DocumentCache.shared.document(for: text)
    }

    var body: some View {
        let children = Array(document.children)
        if children.isEmpty {
            SwiftUI.Text(text)
                .foregroundColor(baseColor)
                .font(.system(size: fontSize))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    BlockRenderer(markup: child, baseColor: baseColor, fontSize: fontSize)
                }
            }
        }
    }
}

// MARK: - Block Renderer

private struct BlockRenderer: View {
    let markup: Markup
    let baseColor: Color
    let fontSize: CGFloat

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        if let paragraph = markup as? Paragraph {
            inlineRenderer(for: paragraph.inlineChildren)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        } else if let heading = markup as? Heading {
            headingView(heading)
        } else if let codeBlock = markup as? CodeBlock {
            CodeBlockView(code: codeBlock.code)
        } else if let blockQuote = markup as? BlockQuote {
            blockQuoteView(blockQuote)
        } else if let unorderedList = markup as? UnorderedList {
            listView(for: Array(unorderedList.listItems)) { _ in
                MarkdownListMarker(text: "•", width: 12, alignment: .center)
            }
        } else if let orderedList = markup as? OrderedList {
            listView(for: Array(orderedList.listItems)) { index in
                MarkdownListMarker(text: "\(index + 1).", width: 20, alignment: .trailing)
            }
        } else if markup is ThematicBreak {
            Divider()
                .background(baseColor.opacity(0.3))
                .padding(.vertical, 4)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func headingView(_ heading: Heading) -> some View {
        let text = inlineRenderer(for: heading.inlineChildren).asText()
        switch heading.level {
        case 1:
            text.bold().italic().underline()
        case 2:
            text.bold()
        default:
            text.bold().foregroundColor(baseColor.opacity(0.7))
        }
    }

    @ViewBuilder
    private func blockQuoteView(_ blockQuote: BlockQuote) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(baseColor.opacity(0.4))
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(blockQuote.children.enumerated()), id: \.offset) { _, child in
                    childView(child, color: baseColor.opacity(0.7), italicParagraphs: true)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func inlineRenderer<S: Sequence>(
        for children: S,
        color: Color? = nil
    ) -> InlineRenderer where S.Element == InlineMarkup {
        InlineRenderer(
            children: Array(children),
            baseColor: color ?? baseColor,
            fontSize: fontSize
        )
    }

    private func renderableChildren(from listItems: [ListItem]) -> [[Markup]] {
        listItems.compactMap { item in
            let children = MarkdownListItemRenderer.renderableChildren(for: item)
            return children.isEmpty ? nil : children
        }
    }

    @ViewBuilder
    private func listView(
        for listItems: [ListItem],
        marker: @escaping (Int) -> MarkdownListMarker
    ) -> some View {
        let items = renderableChildren(from: listItems)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, itemChildren in
                let listMarker = marker(index)
                HStack(alignment: .top, spacing: 6) {
                    SwiftUI.Text(listMarker.text)
                        .font(.system(size: fontSize))
                        .foregroundColor(baseColor.opacity(0.6))
                        .frame(width: listMarker.width, alignment: listMarker.alignment)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(itemChildren.enumerated()), id: \.offset) { _, child in
                            childView(child)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func childView(
        _ child: Markup,
        color: Color? = nil,
        italicParagraphs: Bool = false
    ) -> some View {
        if let paragraph = child as? Paragraph {
            let renderer = inlineRenderer(for: paragraph.inlineChildren, color: color)
            if italicParagraphs {
                renderer.asText().italic()
            } else {
                renderer
            }
        } else {
            BlockRenderer(markup: child, baseColor: color ?? baseColor, fontSize: fontSize)
        }
    }
}

// MARK: - Inline Renderer

private struct InlineRenderer: View {
    let children: [InlineMarkup]
    let baseColor: Color
    let fontSize: CGFloat

    var body: some View {
        asText()
    }

    func asText() -> SwiftUI.Text {
        children.reduce(SwiftUI.Text("")) { partialResult, child in
            partialResult + renderInline(child)
        }
    }

    private func renderInline(_ inline: InlineMarkup) -> SwiftUI.Text {
        if let text = inline as? Markdown.Text {
            return styledText(text.string)
        } else if let strong = inline as? Strong {
            return styledText(strong.plainText)
                .fontWeight(.bold)
        } else if let emphasis = inline as? Emphasis {
            return styledText(emphasis.plainText)
                .italic()
        } else if let code = inline as? InlineCode {
            return styledText(code.code)
                .font(.system(size: fontSize, design: .monospaced))
        } else if let link = inline as? Markdown.Link {
            return styledText(link.plainText, color: .blue)
                .underline()
        } else if let strike = inline as? Strikethrough {
            return styledText(strike.plainText)
                .strikethrough()
        } else if inline is SoftBreak {
            return SwiftUI.Text(" ")
        } else if inline is LineBreak {
            return SwiftUI.Text("\n")
        } else {
            return styledText(inline.plainText)
        }
    }

    private func styledText(_ text: String, color: Color? = nil) -> SwiftUI.Text {
        SwiftUI.Text(text).foregroundColor(color ?? baseColor)
    }
}

// MARK: - Code Block View

private struct CodeBlockView: View {
    let code: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            SwiftUI.Text(code)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
