import SwiftUI
import UIKit

private let amountIconRowIconBaselineInset: CGFloat = 5

public struct AmountIconRow<Amount: View, Icon: View>: View {
    private let text: NSAttributedString
    private let spacing: CGFloat
    private let showsIcon: Bool
    private let iconSize: CGFloat
    private let amount: (AmountIconRowText) -> Amount
    private let icon: () -> Icon

    public init(
        text: NSAttributedString,
        spacing: CGFloat = 8,
        showsIcon: Bool = true,
        iconSize: CGFloat = 28,
        @ViewBuilder amount: @escaping (AmountIconRowText) -> Amount,
        @ViewBuilder icon: @escaping () -> Icon
    ) {
        self.text = text
        self.spacing = spacing
        self.showsIcon = showsIcon
        self.iconSize = iconSize
        self.amount = amount
        self.icon = icon
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            singleLine
            multiline
        }
    }

    private var singleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            amount(AmountIconRowText(text: text))
                .layoutPriority(1)

            if showsIcon {
                icon()
                    .frame(width: iconSize, height: iconSize)
                    .alignmentGuide(.firstTextBaseline) { dimensions in
                        dimensions.height - amountIconRowIconBaselineInset
                    }
            }
        }
    }

    private var multiline: some View {
        let layout = InlineAmountTextLayout(text: text, spacing: spacing, iconSize: showsIcon ? iconSize : 0)
        return InlineAmountLayout(textLayout: layout) {
            amount(AmountIconRowText(text: text, layout: layout))
            if showsIcon {
                icon()
                    .frame(width: iconSize, height: iconSize)
            }
        }
    }
}

public extension AmountIconRow where Amount == AmountIconRowText {
    init(
        text: NSAttributedString,
        spacing: CGFloat = 8,
        showsIcon: Bool = true,
        iconSize: CGFloat = 28,
        @ViewBuilder icon: @escaping () -> Icon
    ) {
        self.init(text: text, spacing: spacing, showsIcon: showsIcon, iconSize: iconSize, amount: { $0 }, icon: icon)
    }
}

/// The amount content, kept separate from the icon so privacy masking only hides the text.
public struct AmountIconRowText: View {
    fileprivate let text: NSAttributedString
    fileprivate var layout: InlineAmountTextLayout? = nil

    public var body: some View {
        if let layout {
            InlineAmountLabel(layout: layout)
                .accessibilityLabel(Text(text.string))
        } else {
            Text(text)
        }
    }
}

private struct InlineAmountLayout: Layout {
    let textLayout: InlineAmountTextLayout

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        textLayout.measure(width: proposal.width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let measurement = textLayout.measure(width: bounds.width)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(measurement.size))
        if subviews.count > 1 {
            let frame = measurement.iconFrame
            subviews[1].place(
                at: CGPoint(x: bounds.minX + frame.midX, y: bounds.minY + frame.midY),
                anchor: .center,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }
}

// SwiftUI can measure layouts off the main thread; all TextKit access is serialized.
private final class InlineAmountTextLayout: @unchecked Sendable {
    private let lock = NSLock()
    private let storage: NSTextStorage
    private let manager = NSLayoutManager()
    private let container = NSTextContainer(size: .zero)
    private let spacing: CGFloat
    private let iconSize: CGFloat

    init(text: NSAttributedString, spacing: CGFloat, iconSize: CGFloat) {
        self.spacing = spacing
        self.iconSize = iconSize
        let content = NSMutableAttributedString(attributedString: text)
        if iconSize > 0 {
            let attributes = text.length > 0 ? text.attributes(at: text.length - 1, effectiveRange: nil) : [:]
            // A word joiner prevents the icon from wrapping onto a line by itself.
            content.append(NSAttributedString(string: "\u{2060}", attributes: attributes))
            let attachment = NSTextAttachment()
            attachment.image = UIImage()
            attachment.bounds = CGRect(x: 0, y: -amountIconRowIconBaselineInset, width: spacing + iconSize, height: iconSize)
            let placeholder = NSMutableAttributedString(attachment: attachment)
            placeholder.addAttributes(attributes, range: NSRange(location: 0, length: placeholder.length))
            content.append(placeholder)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        content.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: content.length))
        storage = NSTextStorage(attributedString: content)
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
    }

    func measure(width: CGFloat?) -> (size: CGSize, iconFrame: CGRect) {
        lock.withLock {
            let size = sizeThatFits(width: width)
            return (size, iconFrame)
        }
    }

    func draw(width: CGFloat) {
        lock.withLock {
            _ = sizeThatFits(width: width)
            let range = manager.glyphRange(for: container)
            manager.drawBackground(forGlyphRange: range, at: .zero)
            manager.drawGlyphs(forGlyphRange: range, at: .zero)
        }
    }

    private func sizeThatFits(width: CGFloat?) -> CGSize {
        let width = max(1, width.flatMap { $0.isFinite ? $0 : nil } ?? ceil(storage.size().width))
        container.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        return CGSize(width: width, height: ceil(manager.usedRect(for: container).maxY))
    }

    private var iconFrame: CGRect {
        guard iconSize > 0, storage.length > 0 else { return .zero }
        let glyph = manager.glyphIndexForCharacter(at: storage.length - 1)
        let frame = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        return CGRect(
            x: frame.minX + spacing,
            y: frame.minY,
            width: iconSize,
            height: iconSize
        )
    }
}

private struct InlineAmountLabel: UIViewRepresentable {
    let layout: InlineAmountTextLayout

    func makeUIView(context: Context) -> InlineAmountLabelView {
        InlineAmountLabelView()
    }

    func updateUIView(_ view: InlineAmountLabelView, context: Context) {
        view.layout = layout
        view.setNeedsDisplay()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: InlineAmountLabelView, context: Context) -> CGSize? {
        layout.measure(width: proposal.width).size
    }
}

private final class InlineAmountLabelView: UIView {
    var layout: InlineAmountTextLayout?

    init() {
        super.init(frame: .zero)
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        layout?.draw(width: bounds.width)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsDisplay()
    }
}
