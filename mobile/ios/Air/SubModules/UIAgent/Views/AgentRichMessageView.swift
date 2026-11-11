import UIKit
import UIComponents

private enum AgentRichMessageMetrics {
    static let blockSpacing: CGFloat = 8
    static let captionSpacing: CGFloat = 6
    static let cellHorizontalPadding: CGFloat = 10
    static let cellVerticalPadding: CGFloat = 8
    static let minimumColumnWidth: CGFloat = 72
    static let maximumColumnWidth: CGFloat = 220
    static let minimumRowHeight: CGFloat = 36
    static let tableCornerRadius: CGFloat = 8
    static let tableBorderWidth: CGFloat = 1
    static let maximumRenderedRows = 200
    static let maximumRenderedCells = 1_000
}

enum AgentMessageTableRenderer {
    static func limitedForRendering(_ table: AgentMessageTable) -> AgentMessageTable {
        var retainedRows: [[AgentMessageTableCell]] = []
        var remainingCells = AgentRichMessageMetrics.maximumRenderedCells

        for row in table.rows.prefix(AgentRichMessageMetrics.maximumRenderedRows) {
            guard remainingCells > 0 else { break }
            let retainedRow = Array(row.prefix(remainingCells))
            retainedRows.append(retainedRow)
            remainingCells -= retainedRow.count
        }

        let isTruncated = retainedRows.count < table.rows.count
            || retainedRows.indices.contains(where: { retainedRows[$0].count < table.rows[$0].count })
        guard isTruncated else { return table }

        let clampedRows = retainedRows.enumerated().map { rowIndex, row in
            row.map { cell in
                AgentMessageTableCell(
                    text: cell.text,
                    isHeader: cell.isHeader,
                    isPlainText: cell.isPlainText,
                    alignment: cell.alignment,
                    verticalAlignment: cell.verticalAlignment,
                    columnSpan: cell.columnSpan,
                    rowSpan: min(cell.rowSpan, retainedRows.count - rowIndex)
                )
            }
        }
        let retainedTable = AgentMessageTable(
            rows: clampedRows,
            title: table.title,
            isBordered: table.isBordered,
            isStriped: table.isStriped
        )
        let columnCount = max(AgentMessageBlockParser.resolveGrid(retainedTable).columnCount, 1)
        let truncationRow = [
            AgentMessageTableCell(
                text: "…",
                alignment: .center,
                columnSpan: columnCount
            ),
        ]
        return AgentMessageTable(
            rows: clampedRows + [truncationRow],
            title: table.title,
            isBordered: table.isBordered,
            isStriped: table.isStriped
        )
    }
}

@MainActor
final class AgentRichMessageView: UIStackView {
    private(set) var displayText = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .vertical
        alignment = .fill
        spacing = AgentRichMessageMetrics.blockSpacing
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        source: String,
        textColor: UIColor,
        maximumContentWidth: CGFloat,
        detectsLinks: Bool,
        markdownProfile: AgentMessageMarkdownProfile,
        onURLTap: ((URL) -> Void)?
    ) {
        configure(
            blocks: AgentMessageBlockParser.parse(source),
            textColor: textColor,
            maximumContentWidth: maximumContentWidth,
            detectsLinks: detectsLinks,
            markdownProfile: markdownProfile,
            onURLTap: onURLTap
        )
    }

    /// `isStreaming`: the answer is still arriving, at the end of its last block, where a marker not yet closed waits
    /// for its text rather than showing
    func configure(
        blocks: [AgentMessageBlock],
        textColor: UIColor,
        maximumContentWidth: CGFloat,
        detectsLinks: Bool,
        markdownProfile: AgentMessageMarkdownProfile,
        baseFont: UIFont = AgentMessageTextRenderer.baseFont,
        isStreaming: Bool = false,
        onURLTap: ((URL) -> Void)?
    ) {
        arrangedSubviews.forEach { view in
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        displayText = blocks.map { block in
            switch block {
            case .text(let text):
                return AgentTextLinks.copyText(text)
            case .table(let table):
                return ([table.title] + table.rows.flatMap { $0.map(\.text) })
                    .compactMap { $0 }
                    .joined(separator: "\n")
            case .code(let code):
                return code.text
            }
        }.joined(separator: "\n")

        for (index, block) in blocks.enumerated() {
            let view: UIView
            switch block {
            case .text(let text):
                view = makeTextView(
                    text: text,
                    textColor: textColor,
                    detectsLinks: detectsLinks,
                    markdownProfile: markdownProfile,
                    baseFont: baseFont,
                    isArriving: isStreaming && index == blocks.count - 1,
                    onURLTap: onURLTap
                )
            case .table(let table):
                let tableView = AgentTableBlockView()
                tableView.configure(
                    table: table,
                    textColor: textColor,
                    maximumContentWidth: maximumContentWidth,
                    detectsLinks: detectsLinks,
                    markdownProfile: markdownProfile,
                    baseFont: baseFont,
                    onURLTap: onURLTap
                )
                view = tableView
            case .code(let code):
                let codeView = AgentCodeBlockView()
                codeView.configure(code: code, baseFont: baseFont)
                codeView.onCopy = { AgentClipboard.copy(code.text) }
                // A code block spans the text's full width, whatever its lines' lengths
                let fullWidth = codeView.widthAnchor.constraint(equalToConstant: maximumContentWidth)
                fullWidth.priority = .defaultHigh
                fullWidth.isActive = true
                view = codeView
            }
            addArrangedSubview(view)
            view.widthAnchor.constraint(lessThanOrEqualToConstant: maximumContentWidth).isActive = true
        }
    }

    private func makeTextView(
        text: String,
        textColor: UIColor,
        detectsLinks: Bool,
        markdownProfile: AgentMessageMarkdownProfile,
        baseFont: UIFont,
        isArriving: Bool,
        onURLTap: ((URL) -> Void)?
    ) -> AgentRichTextView {
        let textView = AgentRichTextView()
        textView.configure(
            text: text,
            textColor: textColor,
            detectsLinks: detectsLinks,
            markdownProfile: markdownProfile,
            baseFont: baseFont,
            isArriving: isArriving,
            onURLTap: onURLTap
        )
        return textView
    }
}

@MainActor
private final class AgentRichTextView: UITextView, UITextViewDelegate {
    private var onURLTap: ((URL) -> Void)?
    private var linkMenu: AgentLinkMenu?

    override var canBecomeFirstResponder: Bool { false }

    override var selectedTextRange: UITextRange? {
        get { nil }
        set { }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        backgroundColor = .clear
        isEditable = false
        isScrollEnabled = false
        dataDetectorTypes = []
        textContainerInset = .zero
        self.textContainer.lineFragmentPadding = 0
        self.textContainer.maximumNumberOfLines = 0
        self.textContainer.lineBreakMode = .byWordWrapping
        textDragInteraction?.isEnabled = false
        delegate = self
        linkMenu = AgentLinkMenu(source: self, linkAt: { [weak self] point in
            self?.linkValue(at: point) as? URL
        }, open: { [weak self] url in self?.onURLTap?(url) })
        linkTextAttributes = AgentMessageTextRenderer.linkTextAttributes(color: tintColor)
        setContentCompressionResistancePriority(UILayoutPriority(999), for: .vertical)
        setContentHuggingPriority(UILayoutPriority(999), for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        text: String,
        textColor: UIColor,
        detectsLinks: Bool,
        markdownProfile: AgentMessageMarkdownProfile,
        rendersMarkdown: Bool = true,
        baseFont: UIFont = AgentMessageTextRenderer.baseFont,
        isHeader: Bool = false,
        alignment: AgentMessageTableAlignment = .start,
        isArriving: Bool = false,
        onURLTap: ((URL) -> Void)?
    ) {
        self.onURLTap = onURLTap
        let isInteractive = detectsLinks || AgentTextLinks.containsLinks(text)
        isSelectable = isInteractive
        isUserInteractionEnabled = isInteractive

        let attributedText = NSMutableAttributedString(
            attributedString: AgentMessageTextRenderer.makeAttributedText(
                text,
                textColor: textColor,
                rendersMarkdown: rendersMarkdown,
                detectsLinks: detectsLinks,
                markdownProfile: markdownProfile,
                isStreaming: isArriving,
                baseFont: baseFont,
                linkColor: tintColor
            )
        )
        let fullRange = NSRange(location: 0, length: attributedText.length)
        if isHeader, fullRange.length > 0 {
            // A header is semibold, as Telegram's are, and a face without that weight, as Persian's, takes its bold
            attributedText.enumerateAttribute(.font, in: fullRange) { value, range, _ in
                let font = (value as? UIFont) ?? baseFont
                let traits = font.fontDescriptor.symbolicTraits
                let headerFont: UIFont
                if font.fontName.hasPrefix("."), !traits.contains(.traitMonoSpace) {
                    headerFont = .systemFont(ofSize: font.pointSize, weight: traits.contains(.traitBold) ? .bold : .semibold)
                } else if let descriptor = font.fontDescriptor.withSymbolicTraits(traits.union(.traitBold)) {
                    headerFont = UIFont(descriptor: descriptor, size: font.pointSize)
                } else {
                    return
                }
                attributedText.addAttribute(.font, value: headerFont, range: range)
            }
        }
        if fullRange.length > 0 {
            attributedText.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
                let paragraphStyle = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
                    ?? NSMutableParagraphStyle()
                paragraphStyle.alignment = alignment.textAlignment
                attributedText.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
            }
        }
        self.attributedText = attributedText
        accessibilityLabel = attributedText.string
        if isHeader {
            accessibilityTraits.insert(.header)
        } else {
            accessibilityTraits.remove(.header)
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        false
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        linkTextAttributes = AgentMessageTextRenderer.linkTextAttributes(color: tintColor)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event) else { return false }
        return linkValue(at: point) != nil
    }

    func textView(
        _ textView: UITextView,
        shouldInteractWith url: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        guard interaction == .invokeDefaultAction else { return false }
        onURLTap?(url)
        return false
    }

    func textView(_ textView: UITextView, shouldInteractWith url: URL, in characterRange: NSRange) -> Bool {
        onURLTap?(url)
        return false
    }

    private func linkValue(at point: CGPoint) -> Any? {
        guard textStorage.length > 0 else { return nil }
        let containerPoint = CGPoint(
            x: point.x - textContainerInset.left,
            y: point.y - textContainerInset.top
        )
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        guard glyphRect.contains(containerPoint) else { return nil }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else { return nil }
        return textStorage.attribute(.link, at: characterIndex, effectiveRange: nil)
    }
}

private extension AgentMessageTableAlignment {
    var textAlignment: NSTextAlignment {
        switch self {
        case .start: .natural
        case .center: .center
        case .end: .right
        }
    }
}

@MainActor
private final class AgentTableBlockView: UIStackView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .vertical
        alignment = .fill
        spacing = AgentRichMessageMetrics.captionSpacing
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        table: AgentMessageTable,
        textColor: UIColor,
        maximumContentWidth: CGFloat,
        detectsLinks: Bool,
        markdownProfile: AgentMessageMarkdownProfile,
        baseFont: UIFont,
        onURLTap: ((URL) -> Void)?
    ) {
        if let title = table.title, !title.isEmpty {
            let caption = AgentRichTextView()
            caption.configure(
                text: title,
                textColor: textColor,
                detectsLinks: detectsLinks,
                markdownProfile: markdownProfile,
                baseFont: baseFont,
                isHeader: true,
                onURLTap: onURLTap
            )
            caption.accessibilityTraits.insert(.header)
            addArrangedSubview(caption)
        }

        let scrollView = AgentTableScrollView()
        scrollView.configure(
            table: table,
            textColor: textColor,
            maximumContentWidth: maximumContentWidth,
            detectsLinks: detectsLinks,
            markdownProfile: markdownProfile,
            baseFont: baseFont,
            onURLTap: onURLTap
        )
        addArrangedSubview(scrollView)
    }
}

@MainActor
private final class AgentTableScrollView: UIScrollView {
    private let tableView = AgentTableGridView()
    private var maximumContentWidth: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        alwaysBounceHorizontal = false
        alwaysBounceVertical = false
        isDirectionalLockEnabled = true
        delaysContentTouches = false
        addSubview(tableView)
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let tableSize = tableView.intrinsicContentSize
        return CGSize(
            width: min(tableSize.width, maximumContentWidth),
            height: tableSize.height
        )
    }

    func configure(
        table: AgentMessageTable,
        textColor: UIColor,
        maximumContentWidth: CGFloat,
        detectsLinks: Bool,
        markdownProfile: AgentMessageMarkdownProfile,
        baseFont: UIFont,
        onURLTap: ((URL) -> Void)?
    ) {
        self.maximumContentWidth = maximumContentWidth
        tableView.configure(
            table: table,
            textColor: textColor,
            detectsLinks: detectsLinks,
            markdownProfile: markdownProfile,
            baseFont: baseFont,
            onURLTap: onURLTap
        )
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let tableSize = tableView.intrinsicContentSize
        tableView.frame = CGRect(origin: .zero, size: tableSize)
        contentSize = tableSize
        alwaysBounceHorizontal = tableSize.width > bounds.width + 0.5
    }
}

/// A table's colors over the answer's bubble, as Telegram's incoming tables: the header row darker by black in the light
/// theme and lighter by white in the dark one, and the borders likewise
enum AgentTableColors {
    static let headerFill = UIColor.label.withAlphaComponent(0.05)
    static let border = UIColor.label.withAlphaComponent(0.12)
}

@MainActor
private final class AgentTableGridView: UIView {
    private struct RenderedCell {
        let view: AgentTableCellView
        let placement: AgentPlacedTableCell
    }

    private var renderedCells: [RenderedCell] = []
    private var tableSize = CGSize(width: 1, height: 1)
    private var isBordered = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        clipsToBounds = true
        layer.cornerRadius = AgentRichMessageMetrics.tableCornerRadius
        layer.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize { tableSize }

    func configure(
        table: AgentMessageTable,
        textColor: UIColor,
        detectsLinks: Bool,
        markdownProfile: AgentMessageMarkdownProfile,
        baseFont: UIFont,
        onURLTap: ((URL) -> Void)?
    ) {
        subviews.forEach { $0.removeFromSuperview() }
        renderedCells.removeAll(keepingCapacity: true)

        let table = AgentMessageTableRenderer.limitedForRendering(table)
        let grid = AgentMessageBlockParser.resolveGrid(table)
        isBordered = table.isBordered

        for placement in grid.cells {
            let cellView = AgentTableCellView(
                verticalAlignment: placement.cell.verticalAlignment
            )
            cellView.configure(
                cell: placement.cell,
                textColor: textColor,
                detectsLinks: detectsLinks,
                markdownProfile: markdownProfile,
                baseFont: baseFont,
                onURLTap: onURLTap
            )
            addSubview(cellView)
            renderedCells.append(RenderedCell(view: cellView, placement: placement))
        }
        applyGridLayout(grid: grid)
        setNeedsDisplay()
        invalidateIntrinsicContentSize()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        UIBezierPath(
            roundedRect: bounds,
            cornerRadius: AgentRichMessageMetrics.tableCornerRadius
        ).addClip()

        // Telegram's grey table: the header row a shade off the bubble, the other rows on the bubble itself
        AgentTableColors.headerFill.setFill()
        for renderedCell in renderedCells where renderedCell.placement.cell.isHeader {
            context.fill(renderedCell.view.frame)
        }

        if isBordered {
            let lineWidth = AgentRichMessageMetrics.tableBorderWidth
            context.setStrokeColor(AgentTableColors.border.cgColor)
            context.setLineWidth(lineWidth)
            for renderedCell in renderedCells {
                let frame = renderedCell.view.frame
                if frame.minX > 0 {
                    context.move(to: CGPoint(x: frame.minX, y: frame.minY))
                    context.addLine(to: CGPoint(x: frame.minX, y: frame.maxY))
                }
                if frame.minY > 0 {
                    context.move(to: CGPoint(x: frame.minX, y: frame.minY))
                    context.addLine(to: CGPoint(x: frame.maxX, y: frame.minY))
                }
            }
            context.strokePath()
            AgentTableColors.border.setStroke()
            let inset = lineWidth / 2
            let border = UIBezierPath(
                roundedRect: bounds.insetBy(dx: inset, dy: inset),
                cornerRadius: AgentRichMessageMetrics.tableCornerRadius - inset
            )
            border.lineWidth = lineWidth
            border.stroke()
        }
        context.restoreGState()
    }

    private func applyGridLayout(grid: AgentMessageTableGrid) {
        let columnCount = max(grid.columnCount, 1)
        let rowCount = max(grid.rowCount, 1)
        var columnWidths = Array(
            repeating: AgentRichMessageMetrics.minimumColumnWidth,
            count: columnCount
        )
        var rowHeights = Array(
            repeating: AgentRichMessageMetrics.minimumRowHeight,
            count: rowCount
        )

        for renderedCell in renderedCells where renderedCell.placement.cell.columnSpan == 1 {
            let column = renderedCell.placement.column
            guard columnWidths.indices.contains(column) else { continue }
            columnWidths[column] = max(
                columnWidths[column],
                min(renderedCell.view.naturalWidth, AgentRichMessageMetrics.maximumColumnWidth)
            )
        }
        for renderedCell in renderedCells where renderedCell.placement.cell.columnSpan > 1 {
            let columns = renderedCell.placement.column..<min(
                renderedCell.placement.column + renderedCell.placement.cell.columnSpan,
                columnCount
            )
            guard !columns.isEmpty else { continue }
            let currentWidth = columns.reduce(CGFloat.zero) { $0 + columnWidths[$1] }
            let desiredWidth = min(
                renderedCell.view.naturalWidth,
                AgentRichMessageMetrics.maximumColumnWidth * CGFloat(columns.count)
            )
            distribute(max(0, desiredWidth - currentWidth), across: columns, values: &columnWidths)
        }

        for renderedCell in renderedCells where renderedCell.placement.cell.rowSpan == 1 {
            let row = renderedCell.placement.row
            guard rowHeights.indices.contains(row) else { continue }
            let width = spannedSize(
                values: columnWidths,
                start: renderedCell.placement.column,
                span: renderedCell.placement.cell.columnSpan
            )
            rowHeights[row] = max(rowHeights[row], renderedCell.view.height(forWidth: width))
        }
        for renderedCell in renderedCells where renderedCell.placement.cell.rowSpan > 1 {
            let rows = renderedCell.placement.row..<min(
                renderedCell.placement.row + renderedCell.placement.cell.rowSpan,
                rowCount
            )
            guard !rows.isEmpty else { continue }
            let width = spannedSize(
                values: columnWidths,
                start: renderedCell.placement.column,
                span: renderedCell.placement.cell.columnSpan
            )
            let currentHeight = rows.reduce(CGFloat.zero) { $0 + rowHeights[$1] }
            distribute(
                max(0, renderedCell.view.height(forWidth: width) - currentHeight),
                across: rows,
                values: &rowHeights
            )
        }

        let columnOrigins = origins(for: columnWidths)
        let rowOrigins = origins(for: rowHeights)
        for renderedCell in renderedCells {
            let placement = renderedCell.placement
            guard columnOrigins.indices.contains(placement.column),
                  rowOrigins.indices.contains(placement.row) else { continue }
            renderedCell.view.frame = CGRect(
                x: columnOrigins[placement.column],
                y: rowOrigins[placement.row],
                width: spannedSize(
                    values: columnWidths,
                    start: placement.column,
                    span: placement.cell.columnSpan
                ),
                height: spannedSize(
                    values: rowHeights,
                    start: placement.row,
                    span: placement.cell.rowSpan
                )
            )
        }
        tableSize = CGSize(
            width: ceil(columnWidths.reduce(0, +)),
            height: ceil(rowHeights.reduce(0, +))
        )
    }

    private func distribute(
        _ amount: CGFloat,
        across indices: Range<Int>,
        values: inout [CGFloat]
    ) {
        guard amount > 0, !indices.isEmpty else { return }
        let increment = amount / CGFloat(indices.count)
        for index in indices where values.indices.contains(index) {
            values[index] += increment
        }
    }

    private func origins(for values: [CGFloat]) -> [CGFloat] {
        var result: [CGFloat] = []
        result.reserveCapacity(values.count)
        var origin: CGFloat = 0
        for value in values {
            result.append(origin)
            origin += value
        }
        return result
    }

    private func spannedSize(values: [CGFloat], start: Int, span: Int) -> CGFloat {
        guard start < values.count else { return 0 }
        return values[start..<min(start + max(span, 1), values.count)].reduce(0, +)
    }
}

@MainActor
private final class AgentTableCellView: UIView {
    private let textView = AgentRichTextView()
    private let verticalAlignment: AgentMessageTableVerticalAlignment

    init(verticalAlignment: AgentMessageTableVerticalAlignment) {
        self.verticalAlignment = verticalAlignment
        super.init(frame: .zero)
        isOpaque = false
        addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var naturalWidth: CGFloat {
        guard let attributedText = textView.attributedText, attributedText.length > 0 else {
            return AgentRichMessageMetrics.minimumColumnWidth
        }
        let textWidth = attributedText.boundingRect(
            with: CGSize(
                width: AgentRichMessageMetrics.maximumColumnWidth
                    - AgentRichMessageMetrics.cellHorizontalPadding * 2,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).width
        return ceil(textWidth) + AgentRichMessageMetrics.cellHorizontalPadding * 2
    }

    func configure(
        cell: AgentMessageTableCell,
        textColor: UIColor,
        detectsLinks: Bool,
        markdownProfile: AgentMessageMarkdownProfile,
        baseFont: UIFont,
        onURLTap: ((URL) -> Void)?
    ) {
        textView.configure(
            text: cell.text,
            textColor: textColor,
            detectsLinks: detectsLinks && !cell.isPlainText,
            markdownProfile: markdownProfile,
            rendersMarkdown: !cell.isPlainText,
            baseFont: baseFont,
            isHeader: cell.isHeader,
            alignment: cell.alignment,
            onURLTap: onURLTap
        )
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        let textWidth = max(width - AgentRichMessageMetrics.cellHorizontalPadding * 2, 1)
        let height = textView.sizeThatFits(CGSize(
            width: textWidth,
            height: .greatestFiniteMagnitude
        )).height
        return max(
            ceil(height) + AgentRichMessageMetrics.cellVerticalPadding * 2,
            AgentRichMessageMetrics.minimumRowHeight
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let horizontalPadding = AgentRichMessageMetrics.cellHorizontalPadding
        let verticalPadding = AgentRichMessageMetrics.cellVerticalPadding
        let availableWidth = max(bounds.width - horizontalPadding * 2, 1)
        let availableHeight = max(bounds.height - verticalPadding * 2, 1)
        let measuredHeight = min(
            textView.sizeThatFits(CGSize(
                width: availableWidth,
                height: .greatestFiniteMagnitude
            )).height,
            availableHeight
        )
        let originY: CGFloat = switch verticalAlignment {
        case .top:
            verticalPadding
        case .middle:
            (bounds.height - measuredHeight) / 2
        case .bottom:
            bounds.height - verticalPadding - measuredHeight
        }
        textView.frame = CGRect(
            x: horizontalPadding,
            y: originY,
            width: availableWidth,
            height: measuredHeight
        )
    }
}
