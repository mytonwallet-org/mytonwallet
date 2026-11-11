import UIKit

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

    @MainActor
    static func make(
        attributedString: NSAttributedString,
        maxWidth: CGFloat,
        measuresCharacters: Bool = true
    ) -> AgentStreamingTextLayout {
        make(
            attributedString: attributedString,
            maxWidth: maxWidth,
            measuresCharacters: measuresCharacters,
            scale: UIScreen.main.scale
        )
    }

    /// Lays out and draws `attributedString`, on any thread. Revealing streamed text needs the frame of every character,
    /// which takes a TextKit query per character, so text shown whole leaves `measuresCharacters` off and has no `lines`.
    static func make(
        attributedString: NSAttributedString,
        maxWidth: CGFloat,
        measuresCharacters: Bool = true,
        scale: CGFloat
    ) -> AgentStreamingTextLayout {
        let textStorage = NSTextStorage(attributedString: attributedString)
        // Hit testing uses the original links; TextKit draws only their explicit color and underline.
        textStorage.removeAttribute(.link, range: NSRange(location: 0, length: textStorage.length))
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: CGSize(width: max(1, maxWidth), height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.maximumNumberOfLines = 0
        layoutManager.addTextContainer(textContainer)
        layoutManager.ensureLayout(for: textContainer)

        let renderBounds = layoutManager.usedRect(for: textContainer).integral
        let coordinateOffset = CGPoint(x: -renderBounds.minX, y: -renderBounds.minY)
        var lines: [Line] = []
        var glyphIndex = 0

        while measuresCharacters, glyphIndex < layoutManager.numberOfGlyphs {
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
                    let lineGlyphIntersection = NSIntersectionRange(glyphRange, lineGlyphRange)
                    guard lineGlyphIntersection.length > 0,
                          let rect = enclosingRect(
                            forGlyphRange: lineGlyphIntersection,
                            layoutManager: layoutManager,
                            textContainer: textContainer
                          ) else {
                        characterRects.append(.zero)
                        continue
                    }
                    characterRects.append(rect.offsetBy(dx: coordinateOffset.x, dy: coordinateOffset.y))
                }
            }

            lines.append(Line(
                frame: lineFragmentRect.offsetBy(dx: coordinateOffset.x, dy: coordinateOffset.y),
                characterRects: characterRects,
                tightHeight: lineUsedRect.height
            ))
            glyphIndex = NSMaxRange(lineGlyphRange)
        }

        let fullSize = renderBounds.size
        let renderedImage = renderImage(
            layoutManager: layoutManager,
            attributedString: attributedString,
            size: fullSize,
            drawingOffset: coordinateOffset,
            scale: scale
        )

        var linkRegions: [LinkRegion] = []
        let fullRange = NSRange(location: 0, length: attributedString.length)
        attributedString.enumerateAttribute(.link, in: fullRange, options: []) { value, charRange, _ in
            guard let url = (value as? URL) ?? (value as? String).flatMap(URL.init) else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, lineGlyphRange, _ in
                let intersection = NSIntersectionRange(glyphRange, lineGlyphRange)
                guard intersection.length > 0 else { return }
                for rect in enclosingRects(
                    forGlyphRange: intersection,
                    layoutManager: layoutManager,
                    textContainer: textContainer
                ) {
                    linkRegions.append(LinkRegion(
                        rect: rect.offsetBy(dx: coordinateOffset.x, dy: coordinateOffset.y),
                        url: url
                    ))
                }
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

    private static func enclosingRect(
        forGlyphRange glyphRange: NSRange,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> CGRect? {
        let rects = enclosingRects(
            forGlyphRange: glyphRange,
            layoutManager: layoutManager,
            textContainer: textContainer
        )
        let enclosingRect = rects.reduce(CGRect.null) { $0.union($1) }
        return enclosingRect.isNull ? nil : enclosingRect
    }

    private static func enclosingRects(
        forGlyphRange glyphRange: NSRange,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> [CGRect] {
        var rects: [CGRect] = []
        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: textContainer
        ) { rect, _ in
            rects.append(rect)
        }
        return rects
    }

    private static func renderImage(
        layoutManager: NSLayoutManager,
        attributedString: NSAttributedString,
        size: CGSize,
        drawingOffset: CGPoint,
        scale: CGFloat
    ) -> CGImage? {
        guard size.width > 0, size.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = scale

        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let range = NSRange(location: 0, length: attributedString.length)
            layoutManager.drawBackground(forGlyphRange: range, at: drawingOffset)
            layoutManager.drawGlyphs(forGlyphRange: range, at: drawingOffset)
        }
        return image.cgImage
    }
}
