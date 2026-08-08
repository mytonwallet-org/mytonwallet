import UIKit

@MainActor
struct AgentStreamingTextLayout {
    struct Line {
        let frame: CGRect
        let characterRects: [CGRect]
        let tightHeight: CGFloat
    }

    struct LinkRegion {
        let rect: CGRect
        let url: URL
    }

    let attributedString: NSAttributedString
    let lines: [Line]
    let linkRegions: [LinkRegion]
    let fullSize: CGSize
    let totalCharacterCount: Int
    let renderedImage: CGImage?

    static func make(attributedString: NSAttributedString, maxWidth: CGFloat) -> AgentStreamingTextLayout {
        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: CGSize(width: max(1, maxWidth), height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.maximumNumberOfLines = 0
        layoutManager.addTextContainer(textContainer)
        layoutManager.ensureLayout(for: textContainer)

        var lines: [Line] = []
        var glyphIndex = 0

        while glyphIndex < layoutManager.numberOfGlyphs {
            var lineGlyphRange = NSRange()
            let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphRange)
            let characterRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)

            let lineUsedRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)

            var characterRects: [CGRect] = []
            if characterRange.length > 0 {
                for index in characterRange.location..<NSMaxRange(characterRange) {
                    let glyphRange = layoutManager.glyphRange(
                        forCharacterRange: NSRange(location: index, length: 1),
                        actualCharacterRange: nil
                    )
                    guard glyphRange.length > 0, glyphRange.location < NSMaxRange(lineGlyphRange) else {
                        characterRects.append(.zero)
                        continue
                    }
                    let startX = layoutManager.location(forGlyphAt: glyphRange.location).x
                    let endX: CGFloat
                    let nextGlyphIndex = NSMaxRange(glyphRange)
                    if nextGlyphIndex < NSMaxRange(lineGlyphRange) {
                        endX = layoutManager.location(forGlyphAt: nextGlyphIndex).x
                    } else {
                        endX = lineUsedRect.maxX - lineFragmentRect.minX
                    }
                    let rect = CGRect(
                        x: lineFragmentRect.minX + startX,
                        y: lineFragmentRect.minY,
                        width: max(0, endX - startX),
                        height: lineFragmentRect.height
                    )
                    characterRects.append(rect)
                }
            }

            lines.append(Line(frame: lineFragmentRect, characterRects: characterRects, tightHeight: lineUsedRect.height))
            glyphIndex = NSMaxRange(lineGlyphRange)
        }

        let usedRect = layoutManager.usedRect(for: textContainer)
        let fullSize = CGSize(width: ceil(usedRect.width), height: ceil(usedRect.height))
        let renderedImage = renderImage(
            layoutManager: layoutManager,
            textContainer: textContainer,
            attributedString: attributedString,
            size: fullSize
        )

        var linkRegions: [LinkRegion] = []
        let fullRange = NSRange(location: 0, length: attributedString.length)
        attributedString.enumerateAttribute(.link, in: fullRange, options: []) { value, charRange, _ in
            guard let url = (value as? URL) ?? (value as? String).flatMap(URL.init) else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, lineGlyphRange, _ in
                let intersection = NSIntersectionRange(glyphRange, lineGlyphRange)
                guard intersection.length > 0 else { return }
                let rect = layoutManager.boundingRect(forGlyphRange: intersection, in: textContainer)
                linkRegions.append(LinkRegion(rect: rect, url: url))
            }
        }

        return AgentStreamingTextLayout(
            attributedString: attributedString,
            lines: lines,
            linkRegions: linkRegions,
            fullSize: fullSize,
            totalCharacterCount: attributedString.length,
            renderedImage: renderedImage
        )
    }

    func size(forCharacterCount characterCount: Int) -> CGSize {
        guard characterCount > 0 else { return .zero }
        guard !lines.isEmpty else { return fullSize }

        var remaining = characterCount
        var height: CGFloat = 0
        var width: CGFloat = 0

        for line in lines {
            if remaining <= 0 { break }

            let lineCount = line.characterRects.count
            if lineCount == 0 { continue }

            let revealedCountOnLine = min(remaining, lineCount)
            if revealedCountOnLine >= lineCount {
                height = line.frame.maxY
            } else {
                height = line.frame.minY + line.tightHeight
            }

            var revealedWidth: CGFloat = 0
            for index in 0..<revealedCountOnLine {
                revealedWidth = max(revealedWidth, line.characterRects[index].maxX)
            }
            width = max(width, ceil(revealedWidth))
            remaining -= lineCount
        }

        return CGSize(width: max(width, 1), height: max(ceil(height), 1))
    }

    func characterRect(at index: Int) -> CGRect? {
        var lineStartIndex = 0
        for line in lines {
            let lineCount = line.characterRects.count
            if index < lineStartIndex + lineCount {
                let rect = line.characterRects[index - lineStartIndex]
                return CGRect(x: rect.minX, y: line.frame.minY, width: rect.width, height: line.frame.height)
            }
            lineStartIndex += lineCount
        }
        return nil
    }

    func link(at point: CGPoint) -> URL? {
        linkRegions.first(where: { $0.rect.contains(point) })?.url
    }

    private static func renderImage(
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        attributedString: NSAttributedString,
        size: CGSize
    ) -> CGImage? {
        guard size.width > 0, size.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = UIScreen.main.scale

        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let range = NSRange(location: 0, length: attributedString.length)
            layoutManager.drawBackground(forGlyphRange: range, at: .zero)
            layoutManager.drawGlyphs(forGlyphRange: range, at: .zero)
        }
        return image.cgImage
    }
}
