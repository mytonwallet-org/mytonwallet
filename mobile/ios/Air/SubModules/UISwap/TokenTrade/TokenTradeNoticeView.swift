import UIKit
import UIComponents
import WalletContext

final class TokenTradeNoticeView: UIView {
    struct Configuration: Equatable {
        let title: String
        let message: String
        var isWarning = false
        var actionTitle: String?
    }

    var onAction: (() -> Void)?
    private(set) var configuration: Configuration?
    private let textReplacement = BlurReplaceView()
    private var textLabel = UILabel()
    private let action = TokenTradePressButton(frame: .zero)
    private lazy var actionPresence = TokenTradePresenceView(action)
    private let actionLabel = UILabel()
    private let sideBars = CAShapeLayer()
    private var previousBounds = CGRect.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 26
        layer.cornerCurve = .continuous
        layer.addSublayer(sideBars)
        addSubview(textReplacement)
        addSubview(actionPresence)
        textReplacement.maximumBlurRadius = 4
        textReplacement.animationDuration = TokenTradeMotion.duration
        action.content.addSubview(actionLabel)
        action.content.layer.cornerRadius = 13
        action.content.layer.cornerCurve = .continuous
        actionLabel.textAlignment = .center
        actionLabel.adjustsFontForContentSizeCategory = true
        action.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)
        action.accessibilityIdentifier = "tokenTrade.hintAction"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ configuration: Configuration, animated: Bool) {
        guard self.configuration != configuration else { return }
        self.configuration = configuration
        updateContent(animated: animated)
    }

    private var color: UIColor {
        configuration?.isWarning == true ? .air.error : UIColor(light: "#DE8C00", dark: "#FFAB2F")
    }

    private func updateContent(animated: Bool) {
        guard let configuration else { return }
        let font = UIFont.preferredFont(forTextStyle: .footnote, compatibleWith: traitCollection)
        let bold = UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.baseWritingDirection = .natural
        let attributed = NSMutableAttributedString(string: configuration.title,
            attributes: [.font: bold, .foregroundColor: color, .paragraphStyle: paragraph])
        attributed.append(NSAttributedString(string: "\n" + configuration.message,
            attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]))
        let label = UILabel()
        label.attributedText = attributed
        label.numberOfLines = 0
        label.accessibilityLabel = configuration.title + " " + configuration.message
        label.isAccessibilityElement = true
        textLabel = label
        textReplacement.replaceContent(with: label, animated: animated && TokenTradeMotion.enabled)
        actionLabel.text = configuration.actionTitle
        actionLabel.font = WTypography.uiFont(.supportingBold, scaling: .dynamic, compatibleWith: traitCollection)
        actionLabel.textColor = color
        action.accessibilityLabel = configuration.actionTitle
        actionPresence.setVisible(configuration.actionTitle != nil, animated: animated)
        action.content.backgroundColor = color.withAlphaComponent(0.12)
        backgroundColor = color.withAlphaComponent(0.12)
        sideBars.fillColor = color.resolvedColor(with: traitCollection).cgColor
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private var stacksAction: Bool { traitCollection.preferredContentSizeCategory.isAccessibilityCategory }
    private var actionSize: CGSize {
        guard configuration?.actionTitle != nil else { return .zero }
        let text = actionLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: ceil(text.width) + 24, height: max(44, ceil(text.height) + 12))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let actionSize = actionSize
        let textWidth = max(1, size.width - 36 - (!stacksAction && actionSize.width > 0 ? actionSize.width + 12 : 0))
        let textHeight = ceil(textLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height) + 4
        let height = stacksAction && actionSize.height > 0 ? textHeight + 8 + actionSize.height : max(textHeight, actionSize.height)
        return CGSize(width: size.width, height: height + 24)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let actionSize = actionSize
        let textWidth = max(1, bounds.width - 36 - (!stacksAction && actionSize.width > 0 ? actionSize.width + 12 : 0))
        let textHeight = ceil(textLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height)
        let textY = stacksAction && actionSize.height > 0 ? 14 : (bounds.height - textHeight) / 2
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let textX = !stacksAction && actionSize.width > 0 && rtl ? 18 + actionSize.width + 12 : 18
        TokenTradeMotion.place(textReplacement, in: CGRect(x: textX, y: textY, width: textWidth, height: textHeight))
        let actionX = rtl ? 18 : bounds.width - 18 - actionSize.width
        let actionY = stacksAction ? bounds.height - 12 - actionSize.height : (bounds.height - actionSize.height) / 2
        if actionSize.width > 0 {
            TokenTradeMotion.place(actionPresence, in: CGRect(x: stacksAction ? (rtl ? actionX : 18) : actionX,
                                                             y: actionY, width: actionSize.width, height: actionSize.height))
            actionLabel.frame = CGRect(origin: .zero, size: actionSize)
        }
        guard previousBounds != bounds else { return }
        previousBounds = bounds
        let radius = min(26, bounds.height / 2, bounds.width / 2)
        let path = CGMutablePath()
        path.addRoundedRect(in: bounds, cornerWidth: radius, cornerHeight: radius)
        path.addRoundedRect(in: bounds.insetBy(dx: 4, dy: 0), cornerWidth: max(0, radius - 4), cornerHeight: radius)
        sideBars.fillRule = .evenOdd
        sideBars.path = path
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateContent(animated: false)
    }
}
