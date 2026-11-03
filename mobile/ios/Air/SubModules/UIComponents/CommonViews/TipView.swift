import UIKit
import WalletContext

/// Tip content. WAlertController owns the glass surface and modal presentation.
public final class TipView: UIStackView {
    static let lineSpacing: CGFloat = 2

    public enum Kind {
        case info
        case warning
        case danger
    }

    public init(title: String, kind: Kind = .info, contentView: UIView?) {
        super.init(frame: .zero)
        axis = .vertical
        spacing = 10

        if kind != .info {
            let icon = UIImageView(image: UIImage(systemName: "exclamationmark.circle.fill"))
            icon.tintColor = kind == .danger ? .air.error : .systemOrange
            icon.contentMode = .scaleAspectFit
            icon.isAccessibilityElement = false
            let container = UIView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(icon)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                icon.topAnchor.constraint(equalTo: container.topAnchor),
                icon.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                icon.widthAnchor.constraint(equalToConstant: 36),
                icon.heightAnchor.constraint(equalToConstant: 36),
            ])
            addArrangedSubview(container)
        }

        let titleLabel = UILabel()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = Self.lineSpacing
        titleLabel.attributedText = NSAttributedString(string: title, attributes: [.paragraphStyle: paragraph])
        titleLabel.applyTextStyle(.bodyStrong, scaling: .dynamic)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .natural
        titleLabel.accessibilityTraits.insert(.header)
        addArrangedSubview(titleLabel)
        if let contentView { addArrangedSubview(contentView) }
    }

    public convenience init(title: String, message: String?, kind: Kind = .info, usesMarkdown: Bool = false) {
        let contentView = message.flatMap { $0.isEmpty ? nil : TipMessageView(message: $0, usesMarkdown: usesMarkdown) }
        self.init(title: title, kind: kind, contentView: contentView)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class TipMessageView: UITextView {
    private let message: AttributedString

    init(message: String, usesMarkdown: Bool) {
        if usesMarkdown {
            self.message = (try? AttributedString(markdown: message, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message)
        } else {
            self.message = AttributedString(message)
        }
        super.init(frame: .zero, textContainer: nil)
        backgroundColor = .clear
        isEditable = false
        isScrollEnabled = false
        isSelectable = self.message.runs.contains { $0.link != nil }
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        textAlignment = .natural
        updateText()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            updateText()
        }
    }

    private func updateText() {
        var attributed = message
        attributed.foregroundColor = UIColor.label
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = TipView.lineSpacing
        attributed.paragraphStyle = paragraph
        for run in message.runs {
            let intent = run.inlinePresentationIntent ?? []
            var font = WTypography.uiFont(intent.contains(.stronglyEmphasized) ? .bodyBold : .body, scaling: .dynamic, compatibleWith: traitCollection)
            if intent.contains(.emphasized), let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic)) {
                font = UIFont(descriptor: descriptor, size: font.pointSize)
            }
            attributed[run.range].font = font
        }
        attributedText = NSAttributedString(attributed)
    }
}
