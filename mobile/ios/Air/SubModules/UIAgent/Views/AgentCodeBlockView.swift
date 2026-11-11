import UIKit
import UIComponents
import WalletContext

private enum AgentCodeBlockMetrics {
    static let cornerRadius: CGFloat = 5
    static let barWidth: CGFloat = 3
    static let headerHeight: CGFloat = 20
    static let headerFontSize: CGFloat = 12
    static let copyIconSize: CGFloat = 14
    static let leadingPadding: CGFloat = 10
    static let trailingPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 2
}

/// A fenced code block as Telegram draws one in a message: a rounded rect in the accent's tint with the accent's bar on
/// its leading edge, and over the code a strip with the fence's language, or Copy, and a copy icon. A tap on the strip
/// copies the code. Its lines don't wrap: the code scrolls sideways, as Telegram's does.
@MainActor
final class AgentCodeBlockView: UIView {
    /// The block's colors for the accent in the light or the dark theme
    struct Colors: Equatable {
        let background: UIColor
        let bar: UIColor
        let header: UIColor
        let title: UIColor
        let copyIcon: UIColor
        let code: UIColor

        static func make(accent: UIColor, isDark: Bool) -> Colors {
            Colors(
                background: isDark ? UIColor.black.withAlphaComponent(0.75) : accent.withAlphaComponent(0.12),
                bar: accent.withAlphaComponent(0.9),
                header: accent.withAlphaComponent(0.3),
                title: accent,
                copyIcon: accent.withAlphaComponent(0.6),
                code: accent
            )
        }
    }

    var onCopy: (() -> Void)?

    private let barView = UIView()
    private let headerControl = UIControl()
    private let titleLabel = UILabel()
    private let copyIconView = UIImageView(image: UIImage(systemName: "doc.on.doc"))
    private let codeScrollView = UIScrollView()
    let codeLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerRadius = AgentCodeBlockMetrics.cornerRadius
        layer.cornerCurve = .continuous
        for view in [barView, headerControl, titleLabel, copyIconView, codeScrollView, codeLabel] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        titleLabel.font = .systemFont(ofSize: AgentCodeBlockMetrics.headerFontSize, weight: .semibold)
        titleLabel.isUserInteractionEnabled = false
        copyIconView.contentMode = .scaleAspectFit
        copyIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: AgentCodeBlockMetrics.copyIconSize,
            weight: .regular
        )
        copyIconView.isUserInteractionEnabled = false
        headerControl.isAccessibilityElement = true
        headerControl.accessibilityTraits = .button
        headerControl.accessibilityLabel = lang("Copy")
        headerControl.addTarget(self, action: #selector(copyCode), for: .touchUpInside)
        codeScrollView.showsHorizontalScrollIndicator = false
        codeScrollView.showsVerticalScrollIndicator = false
        codeScrollView.alwaysBounceVertical = false
        codeScrollView.isDirectionalLockEnabled = true
        codeScrollView.delaysContentTouches = false
        codeLabel.numberOfLines = 0
        codeLabel.lineBreakMode = .byClipping
        // As wide as its longest line, which the code scrolls to
        codeLabel.preferredMaxLayoutWidth = 10_000
        addSubview(barView)
        addSubview(headerControl)
        headerControl.addSubview(titleLabel)
        headerControl.addSubview(copyIconView)
        addSubview(codeScrollView)
        codeScrollView.addSubview(codeLabel)
        let content = codeScrollView.contentLayoutGuide
        let frame = codeScrollView.frameLayoutGuide
        NSLayoutConstraint.activate([
            barView.leadingAnchor.constraint(equalTo: leadingAnchor),
            barView.topAnchor.constraint(equalTo: topAnchor),
            barView.bottomAnchor.constraint(equalTo: bottomAnchor),
            barView.widthAnchor.constraint(equalToConstant: AgentCodeBlockMetrics.barWidth),

            headerControl.leadingAnchor.constraint(equalTo: barView.trailingAnchor),
            headerControl.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerControl.topAnchor.constraint(equalTo: topAnchor),
            headerControl.heightAnchor.constraint(equalToConstant: AgentCodeBlockMetrics.headerHeight),

            titleLabel.leadingAnchor.constraint(
                equalTo: headerControl.leadingAnchor,
                constant: AgentCodeBlockMetrics.leadingPadding
            ),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: copyIconView.leadingAnchor,
                constant: -AgentCodeBlockMetrics.trailingPadding
            ),
            titleLabel.centerYAnchor.constraint(equalTo: headerControl.centerYAnchor),
            copyIconView.trailingAnchor.constraint(
                equalTo: headerControl.trailingAnchor,
                constant: -AgentCodeBlockMetrics.trailingPadding
            ),
            copyIconView.centerYAnchor.constraint(equalTo: headerControl.centerYAnchor),
            copyIconView.widthAnchor.constraint(equalToConstant: AgentCodeBlockMetrics.copyIconSize),
            copyIconView.heightAnchor.constraint(equalToConstant: AgentCodeBlockMetrics.copyIconSize),

            // The code scrolls under the strip's width from the bar to the block's trailing edge
            codeScrollView.leadingAnchor.constraint(equalTo: barView.trailingAnchor),
            codeScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            codeScrollView.topAnchor.constraint(equalTo: headerControl.bottomAnchor),
            codeScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            frame.heightAnchor.constraint(equalTo: content.heightAnchor),

            codeLabel.leadingAnchor.constraint(
                equalTo: content.leadingAnchor,
                constant: AgentCodeBlockMetrics.leadingPadding
            ),
            codeLabel.trailingAnchor.constraint(
                equalTo: content.trailingAnchor,
                constant: -AgentCodeBlockMetrics.trailingPadding
            ),
            codeLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: AgentCodeBlockMetrics.verticalPadding),
            codeLabel.bottomAnchor.constraint(
                equalTo: content.bottomAnchor,
                constant: -AgentCodeBlockMetrics.verticalPadding
            ),
            content.widthAnchor.constraint(greaterThanOrEqualTo: frame.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The strip's title: the fence's language, or Copy for a fence without one
    static func makeTitle(language: String?) -> String {
        language?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? lang("Copy")
    }

    /// Shows `code` at the size code blocks take under `baseFont`'s text
    func configure(code: AgentMessageCode, baseFont: UIFont) {
        titleLabel.text = Self.makeTitle(language: code.language)
        let font = AgentMessageTextRenderer.makeCodeBlockFont(baseFont: baseFont)
        codeLabel.attributedText = NSAttributedString(string: code.text, attributes: [
            .font: font,
            .paragraphStyle: AgentMessageTextRenderer.makeCodeBlockParagraphStyle(font: font, lineBreakMode: .byClipping),
        ])
        codeLabel.accessibilityLabel = code.text
        applyColors()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applyColors()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        applyColors()
    }

    private func applyColors() {
        let colors = Colors.make(
            accent: tintColor.resolvedColor(with: traitCollection),
            isDark: traitCollection.userInterfaceStyle == .dark
        )
        backgroundColor = colors.background
        barView.backgroundColor = colors.bar
        headerControl.backgroundColor = colors.header
        titleLabel.textColor = colors.title
        copyIconView.tintColor = colors.copyIcon
        codeLabel.textColor = colors.code
    }

    @objc private func copyCode() {
        onCopy?()
    }
}
