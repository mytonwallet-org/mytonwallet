import UIKit

private enum AgentMessageTextRendererMetrics {
    static let font = UIFont.systemFont(ofSize: 17, weight: .regular)
    static let lineHeight: CGFloat = 20
    static let paragraphSpacing: CGFloat = 8
    static let markdownSeparator = "⸻"
    static let markdownOptions = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace,
        failurePolicy: .returnPartiallyParsedIfPossible
    )
    static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
}

enum AgentMessageTextRenderer {
    static var baseFont: UIFont {
        AgentMessageTextRendererMetrics.font
    }

    static func makeAttributedText(
        _ text: String,
        textColor: UIColor,
        rendersMarkdown: Bool,
        detectsLinks: Bool = true
    ) -> NSAttributedString {
        let normalizedText = normalizedMessageSource(text)
        let attributedText: NSMutableAttributedString

        if rendersMarkdown,
           let attributedString = try? AttributedString(
                markdown: normalizedMarkdownSource(normalizedText),
                options: AgentMessageTextRendererMetrics.markdownOptions
           ) {
            attributedText = NSMutableAttributedString(attributedString)
        } else {
            attributedText = NSMutableAttributedString(attributedString: makePlainText(normalizedText, color: textColor))
        }

        let fullRange = NSRange(location: 0, length: attributedText.length)
        guard fullRange.length > 0 else { return attributedText }

        attributedText.addAttribute(.foregroundColor, value: textColor, range: fullRange)
        attributedText.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let font = normalizedMarkdownFont(from: value as? UIFont)
            attributedText.addAttribute(.font, value: font, range: range)
        }
        attributedText.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
            let paragraphStyle = normalizedParagraphStyle(from: value as? NSParagraphStyle)
            attributedText.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        }
        if detectsLinks {
            applyDetectedLinks(to: attributedText)
        }

        return attributedText
    }

    private static func normalizedMessageSource(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func normalizedMarkdownSource(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { line in
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                guard !trimmedLine.isEmpty else { return "" }

                if isHorizontalRuleLine(trimmedLine) {
                    return AgentMessageTextRendererMetrics.markdownSeparator
                }

                if let headingText = headingText(from: trimmedLine) {
                    return escapingMarkdownTildes(in: "**\(headingText)**")
                }

                return escapingMarkdownTildes(in: line)
            }
            .joined(separator: "\n")
    }

    private static func makePlainText(_ text: String, color: UIColor) -> NSAttributedString {
        let attributedText = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: AgentMessageTextRendererMetrics.font,
                .foregroundColor: color
            ]
        )
        let fullRange = NSRange(location: 0, length: attributedText.length)
        if fullRange.length > 0 {
            attributedText.addAttribute(
                .paragraphStyle,
                value: normalizedParagraphStyle(from: nil),
                range: fullRange
            )
        }
        return attributedText
    }

    private static func applyDetectedLinks(to attributedText: NSMutableAttributedString) {
        guard attributedText.length > 0,
              let linkDetector = AgentMessageTextRendererMetrics.linkDetector else { return }

        let fullRange = NSRange(location: 0, length: attributedText.length)
        for match in linkDetector.matches(in: attributedText.string, options: [], range: fullRange) {
            guard let url = match.url, match.range.length > 0 else { continue }
            guard attributedText.attribute(.link, at: match.range.location, effectiveRange: nil) == nil else { continue }
            attributedText.addAttribute(.link, value: url, range: match.range)
        }
    }

    private static func normalizedMarkdownFont(from font: UIFont?) -> UIFont {
        guard let font else { return AgentMessageTextRendererMetrics.font }

        let traits = font.fontDescriptor.symbolicTraits
        let isMonospaced = traits.contains(.traitMonoSpace)
        let weight: UIFont.Weight = traits.contains(.traitBold) ? .semibold : .regular

        if isMonospaced {
            return .monospacedSystemFont(ofSize: AgentMessageTextRendererMetrics.font.pointSize, weight: weight)
        }

        if traits.contains(.traitItalic) {
            let baseFont = UIFont.systemFont(ofSize: AgentMessageTextRendererMetrics.font.pointSize, weight: weight)
            guard let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic) else {
                return baseFont
            }
            return UIFont(descriptor: descriptor, size: AgentMessageTextRendererMetrics.font.pointSize)
        }

        return .systemFont(ofSize: AgentMessageTextRendererMetrics.font.pointSize, weight: weight)
    }

    private static func normalizedParagraphStyle(from style: NSParagraphStyle?) -> NSParagraphStyle {
        let paragraphStyle = (style?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = AgentMessageTextRendererMetrics.lineHeight
        paragraphStyle.maximumLineHeight = AgentMessageTextRendererMetrics.lineHeight
        paragraphStyle.paragraphSpacing = AgentMessageTextRendererMetrics.paragraphSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping
        return paragraphStyle
    }

    private static func isHorizontalRuleLine(_ line: String) -> Bool {
        let collapsedLine = line.replacingOccurrences(of: " ", with: "")
        guard collapsedLine.count >= 3 else { return false }
        return collapsedLine.allSatisfy { $0 == "-" }
            || collapsedLine.allSatisfy { $0 == "*" }
            || collapsedLine.allSatisfy { $0 == "_" }
    }

    private static func headingText(from line: String) -> String? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }

        let remainder = line.dropFirst(hashes.count)
        guard remainder.first == " " else { return nil }

        return remainder.trimmingCharacters(in: .whitespaces)
    }

    private static func escapingMarkdownTildes(in text: String) -> String {
        var escapedText = ""
        escapedText.reserveCapacity(text.count)
        var consecutiveBackslashes = 0

        for character in text {
            if character == "~" {
                if consecutiveBackslashes.isMultiple(of: 2) {
                    escapedText.append("\\")
                }
                escapedText.append(character)
                consecutiveBackslashes = 0
                continue
            }

            escapedText.append(character)
            consecutiveBackslashes = character == "\\" ? consecutiveBackslashes + 1 : 0
        }

        return escapedText
    }
}
