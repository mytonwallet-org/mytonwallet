import UIKit
import UIComponents

private enum AgentMessageTextRendererMetrics {
    static let lineHeight: CGFloat = 20
    static let emptyLineHeight: CGFloat = 12
    static let paragraphSpacing: CGFloat = 8
    /// A heading stands this much further from the text above it than paragraphs do, as Telegram's stand 10 pt from
    /// it where its paragraphs stand 4 pt
    static let headingSpacingBefore: CGFloat = 6
    /// A heading's lines are this many times its size, as Telegram's are
    static let headingLineHeightMultiple: CGFloat = 1.4
    static let headingPattern = #"^ {0,3}#{1,6}[ \t]+\S"#
    /// A heading's marks before its text, perhaps with the marks of its bold start
    static let headingMarksPattern = #"^ {0,3}#{1,6}(?:[ \t]+\*{0,2})?$"#
    /// A code block's lines are this many times its size, as Telegram's are, without gaps between them
    static let codeBlockLineHeightMultiple: CGFloat = 1.5
    static let markdownSeparator = "⸻"
    static let markdownOptions = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace,
        failurePolicy: .returnPartiallyParsedIfPossible
    )
    static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    static let codeSpanPattern = #"`([^`\n]+)`"#
    static let boldPattern = #"\*\*([^*\n]+)\*\*"#
    static let italicPattern = #"(?<!\*)\*([^*\n]+)\*(?!\*)"#
}

extension NSAttributedString.Key {
    /// Marks code, in a line or in a block, which takes the accent the links take
    static let agentCode = NSAttributedString.Key("AgentCode")
    /// Marks the lines of a fenced code block
    static let agentCodeBlock = NSAttributedString.Key("AgentCodeBlock")
}

enum AgentMessageMarkdownProfile: Hashable {
    case legacy
    case agentMarkdownV1
    case plainText
}

@MainActor
enum AgentMessageTextRenderer {
    static var baseFont: UIFont {
        WTypography.uiFont(.body)
    }

    /// The height of a line of an answer's text, whichever markdown profile renders it
    static var answerLineHeight: CGFloat {
        max(AgentMessageTextRendererMetrics.lineHeight, ceil(baseFont.lineHeight))
    }

    /// How far apart paragraphs a blank line apart stand, from one's last line to the next one's first. A heading
    /// stands this far from the text under it.
    nonisolated static let blankLineGap: CGFloat = AgentMessageTextRendererMetrics.paragraphSpacing
        + AgentMessageTextRendererMetrics.emptyLineHeight

    /// A fence that opens code, with or without the code's language
    nonisolated static let codeFenceStartPattern = #"^```[A-Za-z0-9_+-]*\s*$"#

    /// A code block's text is 2 pt under the body's, as Telegram's 14 pt code under its 16 pt body
    static func makeCodeBlockFont(baseFont: UIFont) -> UIFont {
        .monospacedSystemFont(ofSize: baseFont.pointSize - 2, weight: .regular)
    }

    /// A code block's lines: 1.5 times the code's size, without gaps between them, an empty one as tall as the others
    static func makeCodeBlockParagraphStyle(font: UIFont, lineBreakMode: NSLineBreakMode) -> NSParagraphStyle {
        let lineHeight = ceil(font.pointSize * AgentMessageTextRendererMetrics.codeBlockLineHeightMultiple)
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.paragraphSpacing = 0
        style.lineBreakMode = lineBreakMode
        return style
    }

    static func makeAttributedText(
        _ text: String,
        textColor: UIColor,
        rendersMarkdown: Bool,
        detectsLinks: Bool = true,
        markdownProfile: AgentMessageMarkdownProfile = .legacy,
        isStreaming: Bool = false,
        baseFont: UIFont = WTypography.uiFont(.body),
        linkColor: UIColor = .tintColor
    ) -> NSAttributedString {
        let normalizedText = normalizedMessageSource(text)
        if markdownProfile == .plainText {
            return makePlainText(normalizedText, color: textColor, font: baseFont)
        }
        let attributedText: NSMutableAttributedString

        if rendersMarkdown, markdownProfile == .agentMarkdownV1 {
            attributedText = makeAgentMarkdownText(
                normalizedText,
                isStreaming: isStreaming,
                textColor: textColor,
                baseFont: baseFont
            )
        } else if rendersMarkdown,
                  let attributedString = try? AttributedString(
                    markdown: normalizedMarkdownSource(normalizedText),
                    options: AgentMessageTextRendererMetrics.markdownOptions
                  ) {
            attributedText = NSMutableAttributedString(attributedString)
        } else {
            attributedText = NSMutableAttributedString(
                attributedString: makePlainText(normalizedText, color: textColor, font: baseFont)
            )
        }

        let fullRange = NSRange(location: 0, length: attributedText.length)
        guard fullRange.length > 0 else { return attributedText }

        attributedText.addAttribute(.foregroundColor, value: textColor, range: fullRange)
        // Code is in the accent and on no background, as Telegram draws it
        attributedText.enumerateAttribute(.agentCode, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            attributedText.addAttribute(.foregroundColor, value: linkColor, range: range)
        }
        attributedText.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            // A heading's runs keep their heading's size and weight
            attributedText.enumerateAttribute(.accessibilityTextHeadingLevel, in: range) { level, textRange, _ in
                guard level == nil else { return }
                let font = normalizedMarkdownFont(from: value as? UIFont, baseFont: baseFont)
                attributedText.addAttribute(.font, value: font, range: textRange)
            }
        }
        attributedText.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
            let paragraphStyle = normalizedParagraphStyle(
                from: value as? NSParagraphStyle,
                lineHeight: markdownProfile == .agentMarkdownV1
                    ? ceil(baseFont.lineHeight)
                    : AgentMessageTextRendererMetrics.lineHeight
            )
            attributedText.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        }
        applyEmptyLineHeights(to: attributedText, baseFont: baseFont)
        applyHeadingStyles(to: attributedText)
        applyHeadingSpacing(to: attributedText)
        applyCodeBlockStyles(to: attributedText, baseFont: baseFont)
        if detectsLinks {
            applyDetectedLinks(to: attributedText)
        } else {
            attributedText.removeAttribute(.link, range: fullRange)
        }
        // Answer links are checked when they are marked, so they apply whether or not other links are detected
        AgentTextLinks.resolve(in: attributedText, linkColor: linkColor)
        let linkAttributes = linkTextAttributes(color: linkColor)
        attributedText.enumerateAttribute(.link, in: NSRange(location: 0, length: attributedText.length)) { value, range, _ in
            guard value != nil else { return }
            attributedText.addAttributes(linkAttributes, range: range)
        }

        return attributedText
    }

    static func linkTextAttributes(color linkColor: UIColor) -> [NSAttributedString.Key: Any] {
        let isMonochrome = [UIUserInterfaceStyle.light, .dark].contains { style in
            let color = linkColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            return color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                && red == green && green == blue && (red == 0 || red == 1) && alpha == 1
        }
        return [
            .foregroundColor: linkColor,
            .underlineStyle: isMonochrome ? NSUnderlineStyle.single.rawValue : 0,
        ]
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

    /// While `isStreaming`, the last line is still arriving and renders as it will once its open markers close
    private static func makeAgentMarkdownText(
        _ text: String,
        isStreaming: Bool,
        textColor: UIColor,
        baseFont: UIFont
    ) -> NSMutableAttributedString {
        let lines = text.components(separatedBy: "\n")
        var renderedLines: [NSAttributedString] = []
        var index = 0

        while index < lines.count {
            if isAgentCodeFenceStart(lines[index]) {
                var codeLines: [String] = []
                index += 1
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces) != "```" {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count {
                    index += 1
                }
                renderedLines.append(makeAgentCodeBlock(
                    codeLines.joined(separator: "\n"),
                    textColor: textColor,
                    baseFont: baseFont
                ))
                continue
            }

            renderedLines.append(makeAgentMarkdownLine(
                lines[index],
                isArriving: isStreaming && index == lines.count - 1,
                textColor: textColor,
                baseFont: baseFont
            ))
            index += 1
        }

        let result = NSMutableAttributedString()
        for (lineIndex, line) in renderedLines.enumerated() {
            if lineIndex > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            result.append(line)
        }
        return result
    }

    private static func makeAgentMarkdownLine(
        _ line: String,
        isArriving: Bool,
        textColor: UIColor,
        baseFont: UIFont
    ) -> NSAttributedString {
        if isArriving, line.range(of: #"^[-+*]$"#, options: .regularExpression) != nil {
            return NSAttributedString()
        }
        // A heading's marks still arriving wait for its text, as a list item's marker does
        if isArriving, line.range(of: AgentMessageTextRendererMetrics.headingMarksPattern, options: .regularExpression) != nil {
            return NSAttributedString()
        }
        if let heading = agentHeading(in: line) {
            let headingText = NSMutableAttributedString(attributedString: parseAgentInlineMarkdown(
                heading.content,
                isArriving: isArriving,
                textColor: textColor,
                baseFont: makeHeadingFont(level: heading.level, baseFont: baseFont)
            ))
            headingText.addAttribute(
                .accessibilityTextHeadingLevel,
                value: heading.level,
                range: NSRange(location: 0, length: headingText.length)
            )
            return headingText
        }
        let itemContent = isArriving ? "" : #"\S"#
        let unorderedPrefix = line.range(
            of: #"^[-+*]\s+"# + itemContent,
            options: .regularExpression
        )
        let orderedPrefix = line.range(
            of: #"^\d+[.)]\s+"# + itemContent,
            options: .regularExpression
        )

        let prefix: String?
        let content: String
        if unorderedPrefix != nil {
            prefix = "•\t"
            content = line.replacingOccurrences(
                of: #"^[-+*]\s+"#,
                with: "",
                options: .regularExpression
            )
        } else if orderedPrefix != nil,
                  let markerRange = line.range(of: #"^\d+[.)]"#, options: .regularExpression) {
            prefix = "\(line[markerRange].dropLast()).\t"
            content = line.replacingOccurrences(
                of: #"^\d+[.)]\s+"#,
                with: "",
                options: .regularExpression
            )
        } else {
            prefix = nil
            content = line
        }

        let parsed = parseAgentInlineMarkdown(
            content,
            isArriving: isArriving,
            textColor: textColor,
            baseFont: baseFont
        )
        guard let prefix else { return parsed }
        // A list item still arriving shows once its text does, not as a marker on its own
        if isArriving, parsed.length == 0 {
            return NSAttributedString()
        }

        let listLine = NSMutableAttributedString(
            string: prefix,
            attributes: [
                .font: baseFont,
                .foregroundColor: textColor
            ]
        )
        listLine.append(parsed)
        let paragraphStyle = NSMutableParagraphStyle()
        let contentIndent = ceil(baseFont.pointSize * 1.5)
        paragraphStyle.firstLineHeadIndent = 0
        paragraphStyle.headIndent = contentIndent
        paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: contentIndent)]
        listLine.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: listLine.length)
        )
        return listLine
    }

    private static func parseAgentInlineMarkdown(
        _ text: String,
        isArriving: Bool,
        textColor: UIColor,
        baseFont: UIFont
    ) -> NSAttributedString {
        var escapedCharacters: [String] = []
        let escapedText = replaceMatches(
            in: text,
            pattern: #"\\([\\|`*_{}\[\]()#+.!~-])"#,
            replacement: { match, source in
                guard match.numberOfRanges == 2,
                      let characterRange = Range(match.range(at: 1), in: source) else { return nil }
                let index = escapedCharacters.count
                escapedCharacters.append(String(source[characterRange]))
                return "\u{E002}\(index)\u{E003}"
            }
        )
        let passiveLinks = passiveAgentLinks(in: escapedText)
        var arrivedText = passiveLinks
        if isArriving {
            arrivedText = droppingTrailingMarkers(from: arrivedText)
            arrivedText = closingOpenMarker("`", in: arrivedText, pattern: AgentMessageTextRendererMetrics.codeSpanPattern)
                ?? arrivedText
        }
        var codeSpans: [String] = []
        var protectedText = replaceMatches(
            in: arrivedText,
            pattern: AgentMessageTextRendererMetrics.codeSpanPattern,
            replacement: { match, source in
                guard match.numberOfRanges == 2,
                      let contentRange = Range(match.range(at: 1), in: source) else { return nil }
                let index = codeSpans.count
                codeSpans.append(String(source[contentRange]))
                return "\u{E000}\(index)\u{E001}"
            }
        )
        if isArriving {
            protectedText = closingOpenMarker("**", in: protectedText, pattern: AgentMessageTextRendererMetrics.boldPattern)
                ?? closingOpenMarker("*", in: protectedText, pattern: AgentMessageTextRendererMetrics.italicPattern)
                ?? protectedText
        }
        let result = NSMutableAttributedString(
            string: protectedText,
            attributes: [
                .font: baseFont,
                .foregroundColor: textColor
            ]
        )

        applyInlineTrait(
            to: result,
            pattern: AgentMessageTextRendererMetrics.boldPattern,
            markerLength: 2,
            trait: .traitBold
        )
        applyInlineTrait(
            to: result,
            pattern: AgentMessageTextRendererMetrics.italicPattern,
            markerLength: 1,
            trait: .traitItalic
        )

        guard let placeholders = try? NSRegularExpression(
            pattern: "\u{E000}(\\d+)\u{E001}"
        ) else {
            return result
        }
        for match in placeholders.matches(
            in: result.string,
            range: NSRange(location: 0, length: result.length)
        ).reversed() {
            guard match.numberOfRanges == 2,
                  let placeholderRange = Range(match.range(at: 1), in: result.string),
                  let index = Int(result.string[placeholderRange]),
                  codeSpans.indices.contains(index) else { continue }
            result.replaceCharacters(
                in: match.range,
                with: NSAttributedString(
                    string: codeSpans[index],
                    attributes: [
                        .font: UIFont.monospacedSystemFont(
                            ofSize: baseFont.pointSize,
                            weight: .regular
                        ),
                        .foregroundColor: textColor,
                        .agentCode: true
                    ]
                )
            )
        }
        guard let escapedPlaceholders = try? NSRegularExpression(
            pattern: "\u{E002}(\\d+)\u{E003}"
        ) else {
            return result
        }
        for match in escapedPlaceholders.matches(
            in: result.string,
            range: NSRange(location: 0, length: result.length)
        ).reversed() {
            guard match.numberOfRanges == 2,
                  let placeholderRange = Range(match.range(at: 1), in: result.string),
                  let index = Int(result.string[placeholderRange]),
                  escapedCharacters.indices.contains(index) else { continue }
            let attributes = result.attributes(at: match.range.location, effectiveRange: nil)
            result.replaceCharacters(
                in: match.range,
                with: NSAttributedString(
                    string: escapedCharacters[index],
                    attributes: attributes
                )
            )
        }
        return result
    }

    /// Markers at the end of an arriving line may still open or close a run, so they wait for the next characters
    /// `text` without the markers at its end, and the spaces after them, which wait for the text they open: asterisks
    /// and backticks, and underscores that open a word
    private static func droppingTrailingMarkers(from text: String) -> String {
        var core = Substring(text)
        while core.last?.isWhitespace == true {
            core.removeLast()
        }
        let markersEnd = core.endIndex
        while true {
            if core.last == "*" || core.last == "`" {
                core.removeLast()
                continue
            }
            let underscores = core.reversed().prefix { $0 == "_" }.count
            let beforeUnderscores = core.dropLast(underscores).last
            guard underscores > 0, beforeUnderscores?.isWhitespace ?? true else { break }
            core.removeLast(underscores)
        }
        return core.endIndex == markersEnd ? text : String(core)
    }

    /// `text` followed by `marker`, when that closes a run that `text` opens with a non-space character after its marker
    private static func closingOpenMarker(_ marker: String, in text: String, pattern: String) -> String? {
        let closedText = text + marker
        let length = (closedText as NSString).length
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.matches(in: closedText, range: NSRange(location: 0, length: length)).last,
              NSMaxRange(match.range) == length,
              let contentRange = Range(match.range(at: 1), in: closedText),
              closedText[contentRange].first?.isWhitespace == false else { return nil }
        return closedText
    }

    private static func applyInlineTrait(
        to text: NSMutableAttributedString,
        pattern: String,
        markerLength: Int,
        trait: UIFontDescriptor.SymbolicTraits
    ) {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = expression.matches(
            in: text.string,
            range: NSRange(location: 0, length: text.length)
        )

        for match in matches.reversed() {
            guard match.range.length > markerLength * 2 else { continue }
            let contentLength = match.range.length - markerLength * 2
            text.deleteCharacters(in: NSRange(
                location: match.range.location + markerLength + contentLength,
                length: markerLength
            ))
            text.deleteCharacters(in: NSRange(
                location: match.range.location,
                length: markerLength
            ))
            let contentRange = NSRange(location: match.range.location, length: contentLength)
            text.enumerateAttribute(.font, in: contentRange) { value, range, _ in
                let font = (value as? UIFont) ?? baseFont
                let traits = font.fontDescriptor.symbolicTraits.union(trait)
                guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return }
                text.addAttribute(
                    .font,
                    value: UIFont(descriptor: descriptor, size: font.pointSize),
                    range: range
                )
            }
        }
    }

    /// A `#`–`######` line's level and text, without a closing run of `#`. Only the marks make no heading.
    private static func agentHeading(in line: String) -> (level: Int, content: String)? {
        guard line.range(of: AgentMessageTextRendererMetrics.headingPattern, options: .regularExpression) != nil else {
            return nil
        }
        let marks = line.drop { $0 == " " }
        let level = marks.prefix { $0 == "#" }.count
        var content = marks.dropFirst(level).trimmingCharacters(in: .whitespaces)
        if let closingMarks = content.range(of: #"\s+#+$"#, options: .regularExpression) {
            content.removeSubrange(closingMarks)
        }
        return (level, content)
    }

    /// Telegram's headings, semibold from 6 pt over its body size for the first level down to 1 pt for the sixth.
    /// The system font takes its semibold weight; another face, as Persian's, its bold one.
    private static func makeHeadingFont(level: Int, baseFont: UIFont) -> UIFont {
        let size = baseFont.pointSize + CGFloat(7 - level)
        let traits = baseFont.fontDescriptor.symbolicTraits.union(.traitBold)
        guard !baseFont.fontName.hasPrefix("."),
              let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) else {
            return .systemFont(ofSize: size, weight: .semibold)
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func makeAgentCodeBlock(
        _ code: String,
        textColor: UIColor,
        baseFont: UIFont
    ) -> NSAttributedString {
        NSAttributedString(
            string: code,
            attributes: [
                .font: makeCodeBlockFont(baseFont: baseFont),
                .foregroundColor: textColor,
                .agentCode: true,
                .agentCodeBlock: true
            ]
        )
    }

    private static func isAgentCodeFenceStart(_ line: String) -> Bool {
        line.range(of: codeFenceStartPattern, options: .regularExpression) != nil
    }

    private static func passiveAgentLinks(in text: String) -> String {
        replaceMatches(
            in: replaceMatches(
                in: text,
                pattern: #"\[([^\]]+)\]\((https?://[^)]+)\)"#,
                replacement: { match, source in
                    guard match.numberOfRanges == 3,
                          let labelRange = Range(match.range(at: 1), in: source),
                          let urlRange = Range(match.range(at: 2), in: source) else { return nil }
                    return "\(source[labelRange]) (\(source[urlRange]))"
                }
            ),
            pattern: #"\[([^\]]+)\]\((mtw://[^)]+)\)"#,
            replacement: { match, source in
                guard match.numberOfRanges == 3,
                      let labelRange = Range(match.range(at: 1), in: source) else { return nil }
                return String(source[labelRange])
            }
        )
    }

    private static func replaceMatches(
        in text: String,
        pattern: String,
        replacement: (NSTextCheckingResult, String) -> String?
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let matches = expression.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result),
                  let replacement = replacement(match, result) else { continue }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    private static func makePlainText(_ text: String, color: UIColor, font: UIFont) -> NSAttributedString {
        let attributedText = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
        let fullRange = NSRange(location: 0, length: attributedText.length)
        if fullRange.length > 0 {
            attributedText.addAttribute(
                .paragraphStyle,
                value: normalizedParagraphStyle(from: nil, lineHeight: ceil(font.lineHeight)),
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

    private static func normalizedMarkdownFont(from font: UIFont?, baseFont: UIFont) -> UIFont {
        guard let font else { return baseFont }

        let traits = font.fontDescriptor.symbolicTraits
        let isMonospaced = traits.contains(.traitMonoSpace)
        if isMonospaced {
            let weight: UIFont.Weight = traits.contains(.traitBold) ? .semibold : .regular
            return .monospacedSystemFont(ofSize: baseFont.pointSize, weight: weight)
        }

        let resolvedTraits = baseFont.fontDescriptor.symbolicTraits.union(
            traits.intersection([.traitBold, .traitItalic])
        )
        guard let descriptor = baseFont.fontDescriptor.withSymbolicTraits(resolvedTraits) else {
            return baseFont
        }
        return UIFont(descriptor: descriptor, size: baseFont.pointSize)
    }

    private static func normalizedParagraphStyle(
        from style: NSParagraphStyle?,
        lineHeight: CGFloat
    ) -> NSParagraphStyle {
        let paragraphStyle = (style?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = lineHeight
        paragraphStyle.maximumLineHeight = lineHeight
        paragraphStyle.paragraphSpacing = AgentMessageTextRendererMetrics.paragraphSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping
        return paragraphStyle
    }

    private static func emptyLineParagraphStyle() -> NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = AgentMessageTextRendererMetrics.emptyLineHeight
        paragraphStyle.maximumLineHeight = AgentMessageTextRendererMetrics.emptyLineHeight
        paragraphStyle.paragraphSpacing = 0
        paragraphStyle.lineBreakMode = .byWordWrapping
        return paragraphStyle
    }

    private static func applyEmptyLineHeights(
        to attributedText: NSMutableAttributedString,
        baseFont: UIFont
    ) {
        let string = attributedText.string as NSString
        let fullRange = NSRange(location: 0, length: string.length)
        guard fullRange.length > 0 else { return }

        let emptyStyle = emptyLineParagraphStyle()
        string.enumerateSubstrings(in: fullRange, options: [.byParagraphs, .substringNotRequired]) { _, substringRange, enclosingRange, _ in
            let paragraphContent: String
            if substringRange.length > 0 {
                paragraphContent = string.substring(with: substringRange)
            } else {
                paragraphContent = ""
            }
            guard paragraphContent.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            guard enclosingRange.length > 0 else { return }
            attributedText.addAttribute(.paragraphStyle, value: emptyStyle, range: enclosingRange)
            attributedText.addAttribute(.font, value: baseFont, range: enclosingRange)
        }
    }

    /// A `#` heading's lines are as tall as Telegram's for its size, and it stands further from the text above it than
    /// paragraphs do, unless it opens the text. The text under it follows it as paragraphs follow each other.
    private static func applyHeadingStyles(to attributedText: NSMutableAttributedString) {
        let string = attributedText.string as NSString
        var hasTextAbove = false
        string.enumerateSubstrings(
            in: NSRange(location: 0, length: string.length),
            options: [.byParagraphs, .substringNotRequired]
        ) { _, range, enclosingRange, _ in
            defer { hasTextAbove = hasTextAbove || !isBlank(range, in: string) }
            guard range.length > 0,
                  attributedText.attribute(.accessibilityTextHeadingLevel, at: range.location, effectiveRange: nil) != nil,
                  let font = attributedText.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont else { return }
            let style = (attributedText.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?
                .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            let lineHeight = ceil(font.pointSize * AgentMessageTextRendererMetrics.headingLineHeightMultiple)
            style.minimumLineHeight = lineHeight
            style.maximumLineHeight = lineHeight
            style.paragraphSpacingBefore = hasTextAbove ? AgentMessageTextRendererMetrics.headingSpacingBefore : 0
            attributedText.addAttribute(.paragraphStyle, value: style, range: enclosingRange)
        }
    }

    /// A code block's lines keep their code's size and line height, without the gaps between paragraphs
    private static func applyCodeBlockStyles(to attributedText: NSMutableAttributedString, baseFont: UIFont) {
        let string = attributedText.string as NSString
        let font = makeCodeBlockFont(baseFont: baseFont)
        attributedText.enumerateAttribute(.agentCodeBlock, in: NSRange(location: 0, length: string.length)) { value, range, _ in
            guard value != nil else { return }
            attributedText.addAttribute(.font, value: font, range: range)
        }
        let style = makeCodeBlockParagraphStyle(font: font, lineBreakMode: .byWordWrapping)
        string.enumerateSubstrings(
            in: NSRange(location: 0, length: string.length),
            options: [.byParagraphs, .substringNotRequired]
        ) { _, _, enclosingRange, _ in
            guard enclosingRange.length > 0,
                  attributedText.attribute(.agentCodeBlock, at: enclosingRange.location, effectiveRange: nil) != nil else { return }
            attributedText.addAttribute(.paragraphStyle, value: style, range: enclosingRange)
        }
    }

    /// A heading, a line in bold on its own, stands as far from the text right under it as paragraphs a blank line
    /// apart do
    private static func applyHeadingSpacing(to attributedText: NSMutableAttributedString) {
        let string = attributedText.string as NSString
        var paragraphs: [(content: NSRange, enclosing: NSRange)] = []
        string.enumerateSubstrings(
            in: NSRange(location: 0, length: string.length),
            options: [.byParagraphs, .substringNotRequired]
        ) { _, range, enclosingRange, _ in
            paragraphs.append((range, enclosingRange))
        }
        for (index, paragraph) in paragraphs.enumerated().dropLast() {
            guard isHeading(paragraph.content, in: attributedText),
                  !isBlank(paragraphs[index + 1].content, in: string) else { continue }
            attributedText.enumerateAttribute(.paragraphStyle, in: paragraph.enclosing) { value, range, _ in
                let style = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                style.paragraphSpacing = blankLineGap
                attributedText.addAttribute(.paragraphStyle, value: style, range: range)
            }
        }
    }

    private static func isHeading(_ range: NSRange, in attributedText: NSAttributedString) -> Bool {
        let string = attributedText.string as NSString
        guard range.length > 0, !isBlank(range, in: string),
              attributedText.attribute(.accessibilityTextHeadingLevel, at: range.location, effectiveRange: nil) == nil else {
            return false
        }
        var isBold = true
        attributedText.enumerateAttribute(.font, in: range) { value, runRange, stop in
            guard !isBlank(runRange, in: string) else { return }
            if (value as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) != true {
                isBold = false
                stop.pointee = true
            }
        }
        return isBold
    }

    private static func isBlank(_ range: NSRange, in string: NSString) -> Bool {
        string.substring(with: range).trimmingCharacters(in: .whitespaces).isEmpty
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
