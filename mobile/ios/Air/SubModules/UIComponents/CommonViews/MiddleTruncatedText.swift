import SwiftUI
import UIKit

public struct MiddleTruncatedText: UIViewRepresentable {
    private let text: String
    private let font: UIFont
    private let separator: String
    private let textColor: Color?
    private let separatorColor: Color?
    private let alignment: NSTextAlignment

    public init(
        _ text: String,
        font: UIFont = .systemFont(ofSize: 17),
        separator: String = "···",
        textColor: Color? = nil,
        separatorColor: Color? = nil,
        alignment: NSTextAlignment = .natural
    ) {
        self.text = text
        self.font = font
        self.separator = separator
        self.textColor = textColor
        self.separatorColor = separatorColor
        self.alignment = alignment
    }

    public func makeUIView(context: Context) -> MiddleTruncatingLabel {
        let label = MiddleTruncatingLabel()
        label.numberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    public func updateUIView(_ label: MiddleTruncatingLabel, context: Context) {
        label.font = font
        label.separator = separator
        label.textAlignment = alignment
        label.resolvedTextColor = textColor.map(UIColor.init) ?? .label
        label.resolvedSeparatorColor = separatorColor.map(UIColor.init)
        label.fullText = text
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView label: MiddleTruncatingLabel, context: Context) -> CGSize? {
        let full = label.fullTextSize()
        let width: CGFloat
        switch proposal.width {
        case .none, .some(.infinity):
            width = full.width
        case .some(let proposed):
            width = min(full.width, max(0, proposed))
        }
        return CGSize(width: width, height: full.height)
    }
}

public class MiddleTruncatingLabel: UILabel {

    public var fullText: String = "" {
        didSet { if oldValue != fullText { invalidateIntrinsicContentSize(); setNeedsLayout() } }
    }
    public var separator: String = "···" {
        didSet { if oldValue != separator { setNeedsLayout() } }
    }
    public var resolvedTextColor: UIColor = .label {
        didSet { if oldValue != resolvedTextColor { lastAppliedKey = nil; setNeedsLayout() } }
    }
    public var resolvedSeparatorColor: UIColor? {
        didSet { if oldValue != resolvedSeparatorColor { lastAppliedKey = nil; setNeedsLayout() } }
    }

    public override var font: UIFont! {
        didSet { lastAppliedKey = nil; invalidateIntrinsicContentSize(); setNeedsLayout() }
    }

    private var lastAppliedKey: String?
    
    public override var intrinsicContentSize: CGSize { fullTextSize() }

    func fullTextSize() -> CGSize {
        guard let font else { return .zero }
        let size = (fullText as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        applyTruncation(maxWidth: bounds.width)
    }

    private func applyTruncation(maxWidth: CGFloat) {
        guard let font else { return }

        let key = "\(Int(maxWidth.rounded()))|\(fullText)|\(separator)|\(resolvedTextColor.hashValue)|\(resolvedSeparatorColor?.hashValue ?? 0)"
        if key == lastAppliedKey { return }
        lastAppliedKey = key

        let split = middleTruncated(fullText, separator: separator, font: font, maxWidth: maxWidth)

        let result = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: resolvedTextColor]
        result.append(NSAttributedString(string: split.head, attributes: base))
        if split.isTruncated {
            let separatorAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: resolvedSeparatorColor ?? resolvedTextColor,
            ]
            result.append(NSAttributedString(string: separator, attributes: separatorAttrs))
            result.append(NSAttributedString(string: split.tail, attributes: base))
        }
        attributedText = result
    }

    private struct Split {
        var head: String
        var tail: String
        var isTruncated: Bool
    }

    private func middleTruncated(_ string: String, separator: String, font: UIFont, maxWidth: CGFloat) -> Split {
        guard maxWidth > 0, !string.isEmpty else {
            return Split(head: string, tail: "", isTruncated: false)
        }

        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        func fits(_ candidate: String) -> Bool {
            (candidate as NSString).size(withAttributes: attributes).width <= maxWidth
        }

        if fits(string) {
            return Split(head: string, tail: "", isTruncated: false)
        }

        let characters = Array(string)
        let count = characters.count

        var low = 0
        var high = count
        var best = Split(head: "", tail: "", isTruncated: true)
        while low <= high {
            let keep = (low + high) / 2
            let headCount = (keep + 1) / 2
            let tailCount = keep / 2
            let head = String(characters.prefix(headCount))
            let tail = String(characters.suffix(tailCount))

            if fits(head + separator + tail) {
                best = Split(head: head, tail: tail, isTruncated: true)
                low = keep + 1
            } else {
                high = keep - 1
            }
        }
        return best
    }
}
